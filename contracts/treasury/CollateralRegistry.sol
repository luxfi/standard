// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "@luxfi/standard/access/Access.sol";
import {EnumerableSet} from "@luxfi/standard/utils/Utils.sol";

/**
 * @title CollateralRegistry
 * @author Lux Industries Inc
 * @notice Registry for bondable collateral assets with risk tiers
 * @dev Manages whitelist of assets accepted for bonding with configurable parameters
 *
 * Integration with Liquid Protocol:
 * - All L* tokens (LUSD, LETH, LBTC, etc.) can be whitelisted
 * - Native ecosystem tokens (CYRUS, MIGA, PARS) get preferential rates
 * - External assets (ETH, stables) accepted at standard rates
 * - LP tokens with ASHA pairs get bonus discounts
 *
 * Risk Tiers:
 * - TIER_1: Native L* tokens, ecosystem tokens (lowest risk, best discount)
 * - TIER_2: Major stables, ETH, BTC (medium risk, standard discount)
 * - TIER_3: LP tokens, other whitelisted (higher risk, lower discount)
 * - TIER_4: Volatile assets (highest risk, minimal discount)
 */
contract CollateralRegistry is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Risk tier for collateral
    enum RiskTier {
        TIER_1,  // Native ecosystem (LUSD, LETH, CYRUS, MIGA, PARS)
        TIER_2,  // Major assets (USDC, USDT, ETH, BTC)
        TIER_3,  // LP tokens, wrapped assets
        TIER_4   // Other volatile assets
    }

    /// @notice Collateral configuration
    struct CollateralConfig {
        bool whitelisted;           // Whether asset is accepted
        RiskTier tier;              // Risk tier for pricing
        uint256 discountBonus;      // Additional discount in basis points (on top of base)
        uint256 maxCapacity;        // Maximum amount that can be bonded (0 = unlimited)
        uint256 totalBonded;        // Total amount bonded so far
        address priceFeed;          // Chainlink price feed (optional)
        bool isLiquidToken;         // True if this is an L* token
        bool isLPToken;             // True if this is an LP token
        bool requiresSwap;          // True if must swap to target collateral
        address swapTarget;         // Target collateral after swap (if requiresSwap)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Collateral configurations
    mapping(address => CollateralConfig) public collaterals;

    /// @notice Set of whitelisted collateral addresses
    EnumerableSet.AddressSet private _whitelistedCollaterals;

    /// @notice Base discount per tier (in basis points)
    mapping(RiskTier => uint256) public tierBaseDiscount;

    /// @notice Swap router for converting non-whitelisted assets
    address public swapRouter;

    /// @notice Primary collateral (e.g., LUSD) - target for swaps
    address public primaryCollateral;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event CollateralAdded(address indexed token, RiskTier tier, uint256 discountBonus);
    event CollateralRemoved(address indexed token);
    event CollateralUpdated(address indexed token, RiskTier tier, uint256 discountBonus);
    event TierDiscountUpdated(RiskTier tier, uint256 discount);
    event SwapRouterUpdated(address indexed router);
    event PrimaryCollateralUpdated(address indexed token);
    event CapacityUpdated(address indexed token, uint256 capacity);
    event BondedAmountUpdated(address indexed token, uint256 newTotal);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error NotWhitelisted(address token);
    error AlreadyWhitelisted(address token);
    error CapacityExceeded(address token, uint256 requested, uint256 available);
    error InvalidTier();
    error InvalidAddress();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address owner_, address primaryCollateral_) Ownable(owner_) {
        primaryCollateral = primaryCollateral_;

        // Set default tier discounts (basis points)
        tierBaseDiscount[RiskTier.TIER_1] = 2500;  // 25% discount for native
        tierBaseDiscount[RiskTier.TIER_2] = 2000;  // 20% discount for majors
        tierBaseDiscount[RiskTier.TIER_3] = 1500;  // 15% discount for LP
        tierBaseDiscount[RiskTier.TIER_4] = 1000;  // 10% discount for volatile
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a collateral asset to whitelist
     * @param token Token address
     * @param tier Risk tier
     * @param discountBonus Additional discount bonus (basis points)
     * @param maxCapacity Maximum bondable amount (0 = unlimited)
     * @param priceFeed Chainlink price feed address
     * @param isLiquidToken Whether this is an L* token
     * @param isLPToken Whether this is an LP token
     */
    function addCollateral(
        address token,
        RiskTier tier,
        uint256 discountBonus,
        uint256 maxCapacity,
        address priceFeed,
        bool isLiquidToken,
        bool isLPToken
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (collaterals[token].whitelisted) revert AlreadyWhitelisted(token);

        collaterals[token] = CollateralConfig({
            whitelisted: true,
            tier: tier,
            discountBonus: discountBonus,
            maxCapacity: maxCapacity,
            totalBonded: 0,
            priceFeed: priceFeed,
            isLiquidToken: isLiquidToken,
            isLPToken: isLPToken,
            requiresSwap: false,
            swapTarget: address(0)
        });

        _whitelistedCollaterals.add(token);

        emit CollateralAdded(token, tier, discountBonus);
    }

    /**
     * @notice Add a collateral that requires swap to primary
     * @param token Token address
     * @param tier Risk tier
     * @param discountBonus Additional discount bonus
     */
    function addSwapCollateral(
        address token,
        RiskTier tier,
        uint256 discountBonus
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (collaterals[token].whitelisted) revert AlreadyWhitelisted(token);

        collaterals[token] = CollateralConfig({
            whitelisted: true,
            tier: tier,
            discountBonus: discountBonus,
            maxCapacity: 0,
            totalBonded: 0,
            priceFeed: address(0),
            isLiquidToken: false,
            isLPToken: false,
            requiresSwap: true,
            swapTarget: primaryCollateral
        });

        _whitelistedCollaterals.add(token);

        emit CollateralAdded(token, tier, discountBonus);
    }

    /**
     * @notice Remove collateral from whitelist
     * @param token Token address
     */
    function removeCollateral(address token) external onlyOwner {
        if (!collaterals[token].whitelisted) revert NotWhitelisted(token);

        delete collaterals[token];
        _whitelistedCollaterals.remove(token);

        emit CollateralRemoved(token);
    }

    /**
     * @notice Update collateral configuration
     * @param token Token address
     * @param tier New risk tier
     * @param discountBonus New discount bonus
     */
    function updateCollateral(
        address token,
        RiskTier tier,
        uint256 discountBonus
    ) external onlyOwner {
        if (!collaterals[token].whitelisted) revert NotWhitelisted(token);

        collaterals[token].tier = tier;
        collaterals[token].discountBonus = discountBonus;

        emit CollateralUpdated(token, tier, discountBonus);
    }

    /**
     * @notice Update capacity for a collateral
     * @param token Token address
     * @param capacity New capacity (0 = unlimited)
     */
    function setCapacity(address token, uint256 capacity) external onlyOwner {
        if (!collaterals[token].whitelisted) revert NotWhitelisted(token);
        collaterals[token].maxCapacity = capacity;
        emit CapacityUpdated(token, capacity);
    }

    /**
     * @notice Update tier base discount
     * @param tier Risk tier
     * @param discount New base discount (basis points)
     */
    function setTierDiscount(RiskTier tier, uint256 discount) external onlyOwner {
        tierBaseDiscount[tier] = discount;
        emit TierDiscountUpdated(tier, discount);
    }

    /**
     * @notice Set swap router
     * @param router Router address
     */
    function setSwapRouter(address router) external onlyOwner {
        swapRouter = router;
        emit SwapRouterUpdated(router);
    }

    /**
     * @notice Set primary collateral
     * @param token Token address
     */
    function setPrimaryCollateral(address token) external onlyOwner {
        primaryCollateral = token;
        emit PrimaryCollateralUpdated(token);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOND INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record bonded amount (called by LiquidBond)
     * @param token Collateral token
     * @param amount Amount bonded
     */
    function recordBond(address token, uint256 amount) external {
        // Note: Should add access control for only authorized bond contracts
        CollateralConfig storage config = collaterals[token];
        if (!config.whitelisted) revert NotWhitelisted(token);

        if (config.maxCapacity > 0) {
            uint256 available = config.maxCapacity - config.totalBonded;
            if (amount > available) revert CapacityExceeded(token, amount, available);
        }

        config.totalBonded += amount;
        emit BondedAmountUpdated(token, config.totalBonded);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if token is whitelisted
     * @param token Token address
     * @return True if whitelisted
     */
    function isWhitelisted(address token) external view returns (bool) {
        return collaterals[token].whitelisted;
    }

    /**
     * @notice Get total discount for a collateral
     * @param token Token address
     * @return Total discount in basis points
     */
    function getDiscount(address token) external view returns (uint256) {
        CollateralConfig storage config = collaterals[token];
        if (!config.whitelisted) return 0;
        return tierBaseDiscount[config.tier] + config.discountBonus;
    }

    /**
     * @notice Get collateral configuration
     * @param token Token address
     * @return config Collateral configuration
     */
    function getCollateral(address token) external view returns (CollateralConfig memory) {
        return collaterals[token];
    }

    /**
     * @notice Get all whitelisted collaterals
     * @return Array of collateral addresses
     */
    function getWhitelistedCollaterals() external view returns (address[] memory) {
        return _whitelistedCollaterals.values();
    }

    /**
     * @notice Get available capacity for a collateral
     * @param token Token address
     * @return Available amount (type(uint256).max if unlimited)
     */
    function getAvailableCapacity(address token) external view returns (uint256) {
        CollateralConfig storage config = collaterals[token];
        if (!config.whitelisted) return 0;
        if (config.maxCapacity == 0) return type(uint256).max;
        return config.maxCapacity - config.totalBonded;
    }

    /**
     * @notice Check if collateral requires swap
     * @param token Token address
     * @return requiresSwap Whether swap is required
     * @return target Target collateral after swap
     */
    function getSwapInfo(address token) external view returns (bool requiresSwap, address target) {
        CollateralConfig storage config = collaterals[token];
        return (config.requiresSwap, config.swapTarget);
    }

    /**
     * @notice Get number of whitelisted collaterals
     * @return Count of whitelisted collaterals
     */
    function collateralCount() external view returns (uint256) {
        return _whitelistedCollaterals.length();
    }
}
