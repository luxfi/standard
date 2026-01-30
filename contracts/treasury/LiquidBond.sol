// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20, SafeERC20} from "@luxfi/standard/tokens/ERC20.sol";
import {Ownable} from "@luxfi/standard/access/Access.sol";
import {ReentrancyGuard} from "@luxfi/standard/utils/Utils.sol";

/**
 * @title LiquidBond
 * @author Lux Industries Inc
 * @notice OHM-style bonding for ASHA with multi-collateral support
 * @dev Unified bonding system integrated with Liquid Protocol
 *
 * DESIGN PHILOSOPHY:
 * ==================
 * - ALL pricing in sats (satoshis) - BTC is the base unit
 * - Commodity-to-commodity swaps only (no USD rails)
 * - Designed for global regulatory compliance
 * - Real DAOs and non-profits can use this safely
 *
 * WHY SATS-BASED:
 * ===============
 * 1. BTC is a commodity, not regulated money
 * 2. Swapping commodities (ETH→ASHA) is cleaner legally
 * 3. Avoids touching fiat-pegged stablecoins
 * 4. Universal unit of account across all chains
 *
 * BONDING FLOW:
 * =============
 * 1. User deposits whitelisted collateral (LETH, LBTC, CYRUS, etc.)
 * 2. Protocol calculates collateral value in sats
 * 3. User receives ASHA at discounted sats-price, vested over time
 * 4. Treasury accumulates collateral as backing for ASHA
 * 5. Bonded funds are NON-RECALLABLE by parent DAOs
 *
 * COLLATERAL TIERS:
 * =================
 * TIER_1: Native ecosystem (LUSD, LETH, LBTC, CYRUS, MIGA, PARS) → 25% discount
 * TIER_2: Major commodities (ETH, BTC wrappers) → 20% discount
 * TIER_3: LP tokens (ASHA pairs) → 15% discount + LP bonus
 * TIER_4: Other volatile assets → 10% discount
 *
 * NOTE: USD stablecoins NOT RECOMMENDED - use LBTC or LETH instead
 */

interface ICollateralRegistry {
    enum RiskTier { TIER_1, TIER_2, TIER_3, TIER_4 }

    struct CollateralConfig {
        bool whitelisted;
        RiskTier tier;
        uint256 discountBonus;
        uint256 maxCapacity;
        uint256 totalBonded;
        address priceFeed;
        bool isLiquidToken;
        bool isLPToken;
        bool requiresSwap;
        address swapTarget;
    }

    function isWhitelisted(address token) external view returns (bool);
    function getDiscount(address token) external view returns (uint256);
    function getCollateral(address token) external view returns (CollateralConfig memory);
    function recordBond(address token, uint256 amount) external;
    function getSwapInfo(address token) external view returns (bool requiresSwap, address target);
    function swapRouter() external view returns (address);
}

interface IPriceFeed {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

interface ISwapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract LiquidBond is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS = 10000;

    /// @notice Sats per BTC (100 million)
    uint256 public constant SATS_PER_BTC = 1e8;

    /// @notice Price precision (8 decimals like BTC)
    uint256 public constant PRICE_PRECISION = 1e8;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice ASHA token (the OHM-like reserve asset)
    IERC20 public immutable asha;

    /// @notice Treasury Safe that receives bond payments
    address public immutable treasury;

    /// @notice Collateral registry
    ICollateralRegistry public collateralRegistry;

    /// @notice BTC price feed (for sats conversion)
    address public btcPriceFeed;

    /// @notice ASHA price in sats (manually set or from oracle)
    uint256 public ashaPriceInSats;

    /// @notice Vesting period for bonded ASHA
    uint256 public vestingPeriod = 7 days;

    /// @notice Minimum bond amount in sats
    uint256 public minBondSats = 100000; // 0.001 BTC worth

    /// @notice Maximum bond per address per epoch
    uint256 public maxBondPerAddress = type(uint256).max;

    /// @notice Current epoch (resets limits)
    uint256 public currentEpoch;

    /// @notice Epoch duration
    uint256 public epochDuration = 1 days;

    /// @notice Last epoch start time
    uint256 public epochStartTime;

    /// @notice Bond purchase tracking
    struct Purchase {
        address collateral;
        uint256 collateralAmount;
        uint256 ashaOwed;
        uint256 ashaClaimed;
        uint256 vestingStart;
        uint256 vestingEnd;
        uint256 priceInSats;  // Price at time of purchase
    }

    /// @notice User purchases
    mapping(address => Purchase[]) public userPurchases;

    /// @notice User bond amount per epoch
    mapping(uint256 => mapping(address => uint256)) public userEpochBonds;

    /// @notice Total ASHA owed (for supply tracking)
    uint256 public totalAshaOwed;

    /// @notice Total ASHA claimed
    uint256 public totalAshaClaimed;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Bonded(
        address indexed user,
        address indexed collateral,
        uint256 collateralAmount,
        uint256 collateralValueSats,
        uint256 ashaAmount,
        uint256 discount
    );
    event Claimed(address indexed user, uint256 purchaseIndex, uint256 amount);
    event AshaPriceUpdated(uint256 newPriceInSats);
    event VestingPeriodUpdated(uint256 newPeriod);
    event EpochAdvanced(uint256 newEpoch);
    event CollateralRegistryUpdated(address indexed registry);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error CollateralNotWhitelisted(address token);
    error BondTooSmall(uint256 valueSats, uint256 minSats);
    error ExceedsMaxBond(uint256 requested, uint256 max);
    error NothingToClaim();
    error InvalidPrice();
    error SwapFailed();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address asha_,
        address treasury_,
        address collateralRegistry_,
        address btcPriceFeed_,
        uint256 initialAshaPriceInSats_,
        address owner_
    ) Ownable(owner_) {
        asha = IERC20(asha_);
        treasury = treasury_;
        collateralRegistry = ICollateralRegistry(collateralRegistry_);
        btcPriceFeed = btcPriceFeed_;
        ashaPriceInSats = initialAshaPriceInSats_;
        epochStartTime = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BONDING
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Bond collateral for discounted ASHA
     * @param collateral Collateral token address
     * @param amount Amount of collateral to bond
     * @param minAshaOut Minimum ASHA to receive (slippage protection)
     * @return ashaAmount Amount of ASHA to receive (vested)
     */
    function bond(
        address collateral,
        uint256 amount,
        uint256 minAshaOut
    ) external nonReentrant returns (uint256 ashaAmount) {
        _advanceEpochIfNeeded();

        // Verify collateral is whitelisted
        if (!collateralRegistry.isWhitelisted(collateral)) {
            revert CollateralNotWhitelisted(collateral);
        }

        // Get collateral config
        ICollateralRegistry.CollateralConfig memory config =
            collateralRegistry.getCollateral(collateral);

        // Handle swap if required
        address finalCollateral = collateral;
        uint256 finalAmount = amount;

        if (config.requiresSwap) {
            (finalCollateral, finalAmount) = _swapCollateral(
                collateral,
                amount,
                config.swapTarget
            );
        }

        // Calculate collateral value in sats
        uint256 collateralValueSats = _getValueInSats(finalCollateral, finalAmount);

        if (collateralValueSats < minBondSats) {
            revert BondTooSmall(collateralValueSats, minBondSats);
        }

        // Check epoch limits
        uint256 userEpochTotal = userEpochBonds[currentEpoch][msg.sender] + collateralValueSats;
        if (userEpochTotal > maxBondPerAddress) {
            revert ExceedsMaxBond(userEpochTotal, maxBondPerAddress);
        }
        userEpochBonds[currentEpoch][msg.sender] = userEpochTotal;

        // Get discount
        uint256 discount = collateralRegistry.getDiscount(collateral);

        // Calculate ASHA amount with discount
        // ashaAmount = (collateralValueSats * (BPS + discount)) / (ashaPriceInSats * BPS / PRICE_PRECISION)
        ashaAmount = (collateralValueSats * (BPS + discount) * PRICE_PRECISION) / (ashaPriceInSats * BPS);

        require(ashaAmount >= minAshaOut, "Slippage exceeded");

        // Transfer collateral to treasury
        IERC20(collateral).safeTransferFrom(msg.sender, treasury, amount);

        // Record in registry
        collateralRegistry.recordBond(finalCollateral, finalAmount);

        // Create purchase record
        userPurchases[msg.sender].push(Purchase({
            collateral: finalCollateral,
            collateralAmount: finalAmount,
            ashaOwed: ashaAmount,
            ashaClaimed: 0,
            vestingStart: block.timestamp,
            vestingEnd: block.timestamp + vestingPeriod,
            priceInSats: ashaPriceInSats
        }));

        totalAshaOwed += ashaAmount;

        emit Bonded(
            msg.sender,
            collateral,
            amount,
            collateralValueSats,
            ashaAmount,
            discount
        );
    }

    /**
     * @notice Claim vested ASHA from a specific purchase
     * @param purchaseIndex Index of purchase to claim from
     */
    function claim(uint256 purchaseIndex) external nonReentrant {
        Purchase storage purchase = userPurchases[msg.sender][purchaseIndex];

        uint256 claimable = _claimable(purchase);
        if (claimable == 0) revert NothingToClaim();

        purchase.ashaClaimed += claimable;
        totalAshaClaimed += claimable;

        // Mint ASHA to user
        IMintable(address(asha)).mint(msg.sender, claimable);

        emit Claimed(msg.sender, purchaseIndex, claimable);
    }

    /**
     * @notice Claim all vested ASHA
     */
    function claimAll() external nonReentrant {
        Purchase[] storage purchases = userPurchases[msg.sender];
        uint256 totalClaimable = 0;

        for (uint256 i = 0; i < purchases.length; i++) {
            uint256 claimable = _claimable(purchases[i]);
            if (claimable > 0) {
                purchases[i].ashaClaimed += claimable;
                totalClaimable += claimable;
                emit Claimed(msg.sender, i, claimable);
            }
        }

        if (totalClaimable == 0) revert NothingToClaim();

        totalAshaClaimed += totalClaimable;
        IMintable(address(asha)).mint(msg.sender, totalClaimable);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get collateral value in sats
     * @param token Token address
     * @param amount Token amount
     * @return Value in sats
     */
    function _getValueInSats(address token, uint256 amount) internal view returns (uint256) {
        ICollateralRegistry.CollateralConfig memory config =
            collateralRegistry.getCollateral(token);

        if (config.priceFeed == address(0)) {
            // No price feed - assume 1:1 with BTC for L* tokens
            // This works for LBTC, for others need proper feed
            return amount;
        }

        // Get token price in USD from Chainlink
        (, int256 tokenPrice,,,) = IPriceFeed(config.priceFeed).latestRoundData();
        uint8 tokenDecimals = IPriceFeed(config.priceFeed).decimals();

        // Get BTC price in USD
        (, int256 btcPrice,,,) = IPriceFeed(btcPriceFeed).latestRoundData();
        uint8 btcDecimals = IPriceFeed(btcPriceFeed).decimals();

        if (tokenPrice <= 0 || btcPrice <= 0) revert InvalidPrice();

        // Convert to sats: (amount * tokenPriceUSD * SATS_PER_BTC) / btcPriceUSD
        // Normalize decimals
        uint256 tokenPriceNorm = uint256(tokenPrice) * (10 ** (18 - tokenDecimals));
        uint256 btcPriceNorm = uint256(btcPrice) * (10 ** (18 - btcDecimals));

        return (amount * tokenPriceNorm * SATS_PER_BTC) / (btcPriceNorm * 1e18);
    }

    /**
     * @notice Swap collateral to target (for non-whitelisted assets)
     */
    function _swapCollateral(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) internal returns (address, uint256) {
        address router = collateralRegistry.swapRouter();
        if (router == address(0)) revert SwapFailed();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(router, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = ISwapRouter(router).swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount (user protects via minAshaOut)
            path,
            address(this),
            block.timestamp
        );

        return (tokenOut, amounts[1]);
    }

    function _claimable(Purchase storage purchase) internal view returns (uint256) {
        if (purchase.ashaOwed == 0) return 0;

        uint256 elapsed = block.timestamp - purchase.vestingStart;
        uint256 vestingDuration = purchase.vestingEnd - purchase.vestingStart;

        uint256 vested;
        if (elapsed >= vestingDuration) {
            vested = purchase.ashaOwed;
        } else {
            vested = (purchase.ashaOwed * elapsed) / vestingDuration;
        }

        return vested - purchase.ashaClaimed;
    }

    function _advanceEpochIfNeeded() internal {
        if (block.timestamp >= epochStartTime + epochDuration) {
            currentEpoch++;
            epochStartTime = block.timestamp;
            emit EpochAdvanced(currentEpoch);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update ASHA price in sats
     * @param newPrice New price in sats
     */
    function setAshaPrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0) revert InvalidPrice();
        ashaPriceInSats = newPrice;
        emit AshaPriceUpdated(newPrice);
    }

    /**
     * @notice Update vesting period
     * @param newPeriod New vesting period in seconds
     */
    function setVestingPeriod(uint256 newPeriod) external onlyOwner {
        vestingPeriod = newPeriod;
        emit VestingPeriodUpdated(newPeriod);
    }

    /**
     * @notice Update collateral registry
     * @param registry New registry address
     */
    function setCollateralRegistry(address registry) external onlyOwner {
        collateralRegistry = ICollateralRegistry(registry);
        emit CollateralRegistryUpdated(registry);
    }

    /**
     * @notice Update bond limits
     */
    function setBondLimits(uint256 minSats, uint256 maxPerAddress) external onlyOwner {
        minBondSats = minSats;
        maxBondPerAddress = maxPerAddress;
    }

    /**
     * @notice Update BTC price feed
     */
    function setBtcPriceFeed(address feed) external onlyOwner {
        btcPriceFeed = feed;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get bond quote for collateral
     * @param collateral Collateral token
     * @param amount Amount to bond
     * @return ashaOut Expected ASHA amount
     * @return discount Applied discount
     * @return valueSats Collateral value in sats
     */
    function getBondQuote(
        address collateral,
        uint256 amount
    ) external view returns (uint256 ashaOut, uint256 discount, uint256 valueSats) {
        if (!collateralRegistry.isWhitelisted(collateral)) {
            return (0, 0, 0);
        }

        valueSats = _getValueInSats(collateral, amount);
        discount = collateralRegistry.getDiscount(collateral);
        ashaOut = (valueSats * (BPS + discount) * PRICE_PRECISION) / (ashaPriceInSats * BPS);
    }

    /**
     * @notice Get user's total claimable ASHA
     * @param user User address
     * @return Total claimable amount
     */
    function getClaimable(address user) external view returns (uint256) {
        Purchase[] storage purchases = userPurchases[user];
        uint256 total = 0;

        for (uint256 i = 0; i < purchases.length; i++) {
            total += _claimable(purchases[i]);
        }

        return total;
    }

    /**
     * @notice Get user's purchase count
     * @param user User address
     * @return Number of purchases
     */
    function getPurchaseCount(address user) external view returns (uint256) {
        return userPurchases[user].length;
    }

    /**
     * @notice Get user's purchase details
     * @param user User address
     * @param index Purchase index
     * @return Purchase details
     */
    function getPurchase(address user, uint256 index) external view returns (Purchase memory) {
        return userPurchases[user][index];
    }

    /**
     * @notice Get pending ASHA (owed - claimed)
     * @return Total pending ASHA supply
     */
    function getPendingAsha() external view returns (uint256) {
        return totalAshaOwed - totalAshaClaimed;
    }
}
