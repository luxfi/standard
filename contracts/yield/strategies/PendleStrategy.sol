// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title PendleStrategy
 * @notice Yield strategies for Pendle yield tokenization protocol
 * @dev Implements three strategies:
 *   1. PendleLPStrategy - LP positions (PT-SY + YT) for yield + trading fees
 *   2. PendlePTStrategy - Fixed yield via Principal Tokens (hold to maturity)
 *   3. VePendleStrategy - vePENDLE locking + protocol fee share + vote incentives
 *
 * Pendle Overview:
 * - Splits yield-bearing assets into PT (Principal) and YT (Yield) tokens
 * - PT: Fixed yield, redeemable 1:1 at maturity for underlying
 * - YT: Floating yield, receives all yield until maturity then worthless
 * - SY: Standardized Yield wrapper for any yield source
 * - LP: Provides PT/SY liquidity, earns trading fees + PENDLE incentives
 * - vePENDLE: Locked PENDLE, earns protocol fees + vote incentives
 *
 * Yield sources per strategy:
 * - PendleLPStrategy: Trading fees + PENDLE rewards + underlying yield exposure
 * - PendlePTStrategy: Fixed discount (implied APY) + capital guarantee at maturity
 * - VePendleStrategy: Protocol fees (ETH) + vote incentives + boosted rewards
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// PENDLE INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Pendle Router for swaps and liquidity operations
interface IPendleRouter {
    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain;
        uint256 maxIteration;
        uint256 eps;
    }

    struct TokenInput {
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        address bulk;
        address pendleSwap;
        SwapData swapData;
    }

    struct TokenOutput {
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        address bulk;
        address pendleSwap;
        SwapData swapData;
    }

    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        ETH_WETH
    }

    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netSyFee);

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyFee);

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input
    ) external payable returns (uint256 netPtOut, uint256 netSyFee);

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyFee);

    function redeemPyToToken(
        address receiver,
        address YT,
        uint256 netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut);
}

/// @notice Pendle Market (AMM pool for PT-SY trading)
interface IPendleMarket {
    function readTokens() external view returns (address _SY, address _PT, address _YT);

    function getRewardTokens() external view returns (address[] memory);

    function redeemRewards(address user) external returns (uint256[] memory rewardAmounts);

    function activeBalance(address user) external view returns (uint256);

    function totalActiveSupply() external view returns (uint256);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);
}

/// @notice Pendle Standardized Yield wrapper
interface IPendleSY {
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable returns (uint256 amountSharesOut);

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    function exchangeRate() external view returns (uint256);

    function yieldToken() external view returns (address);

    function getTokensIn() external view returns (address[] memory);

    function getTokensOut() external view returns (address[] memory);
}

/// @notice Pendle Yield Token
interface IPendleYT {
    function redeemDueInterestAndRewards(
        address user,
        bool redeemInterest,
        bool redeemRewards
    ) external returns (uint256 interestOut, uint256[] memory rewardsOut);

    function redeemPY(address receiver) external returns (uint256 amountSyOut);

    function SY() external view returns (address);

    function PT() external view returns (address);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);

    function userInterest(address user) external view returns (uint128 lastPYIndex, uint128 accruedInterest);

    function pyIndexLastUpdatedBlock() external view returns (uint128);

    function pyIndexCurrent() external returns (uint256);
}

/// @notice Pendle Principal Token
interface IPendlePT {
    function SY() external view returns (address);

    function YT() external view returns (address);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);
}

/// @notice vePENDLE voting escrow
interface IVePendle {
    function increaseLockPosition(uint128 additionalAmountToLock, uint128 newExpiry)
        external
        returns (uint128 newVeBalance);

    function withdraw() external returns (uint128 amount);

    function positionData(address user) external view returns (uint128 amount, uint128 expiry);

    function balanceOf(address user) external view returns (uint128);

    function totalSupplyStored() external view returns (uint128);
}

/// @notice Pendle Fee Distributor for vePENDLE holders
interface IPendleFeeDistributor {
    function claimProtocol(address user, address[] calldata pools)
        external
        returns (uint256 totalAmountOut, uint256[] memory amountsOut);

    function getProtocolClaimables(address user, address[] calldata pools)
        external
        view
        returns (uint256 totalClaimable, uint256[] memory claimables);
}

/// @notice Pendle Voting Controller for gauge voting
interface IPendleVotingController {
    function vote(address[] calldata pools, uint64[] calldata weights) external;

    function getUserPoolVote(address user, address pool) external view returns (uint64 weight, uint64 lastVotedEpoch);
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Emitted when Principal Tokens are minted
/// @param user User receiving PT
/// @param market Pendle market address
/// @param ptAmount Amount of PT minted
/// @param underlyingAmount Amount of underlying used
event PTMinted(address indexed user, address indexed market, uint256 ptAmount, uint256 underlyingAmount);

/// @notice Emitted when Yield Tokens are minted
/// @param user User receiving YT
/// @param market Pendle market address
/// @param ytAmount Amount of YT minted
/// @param underlyingAmount Amount of underlying used
event YTMinted(address indexed user, address indexed market, uint256 ytAmount, uint256 underlyingAmount);

/// @notice Emitted when LP tokens are deposited
/// @param user User depositing
/// @param market Pendle market address
/// @param lpAmount Amount of LP tokens received
/// @param underlyingAmount Amount of underlying deposited
event LPDeposited(address indexed user, address indexed market, uint256 lpAmount, uint256 underlyingAmount);

/// @notice Emitted when PENDLE is locked as vePENDLE
/// @param user User locking
/// @param amount Amount of PENDLE locked
/// @param expiry Lock expiry timestamp
/// @param veBalance Resulting vePENDLE balance
event VePendleLocked(address indexed user, uint256 amount, uint256 expiry, uint256 veBalance);

/// @notice Emitted when rewards are claimed
/// @param user User claiming
/// @param rewardToken Reward token address
/// @param amount Amount claimed
event RewardsClaimed(address indexed user, address indexed rewardToken, uint256 amount);

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM ERRORS
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Market has expired
error MarketExpired(address market, uint256 expiry);

/// @notice Invalid market address
error InvalidMarket(address market);

/// @notice Slippage exceeded
error SlippageExceeded(uint256 expected, uint256 received);

/// @notice Insufficient balance
error InsufficientBalance(uint256 required, uint256 available);

/// @notice Lock not expired
error LockNotExpired(uint256 expiry, uint256 currentTime);

/// @notice Lock already expired
error LockAlreadyExpired(uint256 expiry, uint256 currentTime);

/// @notice Invalid lock duration
error InvalidLockDuration(uint256 duration);

/// @notice Zero amount
error ZeroAmount();

/// @notice Strategy is paused
error StrategyPaused();

/// @notice Invalid recipient
error InvalidRecipient();

/// @notice PT not matured
error PTNotMatured(uint256 expiry, uint256 currentTime);

// ═══════════════════════════════════════════════════════════════════════════════
// PENDLE LP STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title PendleLPStrategy
 * @notice Strategy for Pendle LP positions earning trading fees + PENDLE rewards
 * @dev Deposits underlying into PT-SY LP pool
 *
 * Yield sources:
 * 1. Trading fees from PT-SY swaps
 * 2. PENDLE liquidity mining rewards
 * 3. Underlying yield exposure through SY component
 *
 * Risks:
 * - Impermanent loss (PT price moves vs SY)
 * - Market expiry (must exit before expiry or roll to new market)
 * - Smart contract risk
 */
contract PendleLPStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Maximum slippage allowed (5%)
    uint256 public constant MAX_SLIPPAGE = 500;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Pendle router
    IPendleRouter public immutable router;

    /// @notice Pendle market (PT-SY pool)
    IPendleMarket public immutable market;

    /// @notice SY token
    IPendleSY public immutable sy;

    /// @notice PT token
    address public immutable pt;

    /// @notice YT token
    address public immutable yt;

    /// @notice Underlying asset
    address public immutable underlyingAsset;

    /// @notice Strategy name
    string private _strategyName;

    /// @notice Is strategy active
    bool public active;

    /// @notice Total LP shares held by this strategy
    uint256 public totalLPShares;

    /// @notice Total deposited for yield tracking
    uint256 public totalDeposited;

    /// @notice Accumulated rewards ready for distribution
    uint256 public pendingRewards;

    /// @notice Slippage tolerance in BPS
    uint256 public slippageTolerance;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize Pendle LP strategy
     * @param _router Pendle router address
     * @param _market Pendle market address
     * @param _underlying Underlying asset address
     * @param strategyName Name for this strategy
     */
    constructor(
        address _router,
        address _market,
        address _underlying,
        string memory strategyName
    ) Ownable(msg.sender) {
        if (_router == address(0) || _market == address(0)) revert InvalidMarket(_market);

        router = IPendleRouter(_router);
        market = IPendleMarket(_market);

        (address _sy, address _pt, address _yt) = market.readTokens();
        sy = IPendleSY(_sy);
        pt = _pt;
        yt = _yt;
        underlyingAsset = _underlying;

        _strategyName = strategyName;
        active = true;
        slippageTolerance = 100; // 1% default
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenActive() {
        if (!active) revert StrategyPaused();
        _;
    }

    modifier notExpired() {
        if (market.isExpired()) revert MarketExpired(address(market), market.expiry());
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit underlying and add liquidity to Pendle market
     * @param amount Amount of underlying to deposit
     * @return shares LP shares received
     */
    function deposit(uint256 amount) external nonReentrant whenActive notExpired returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer underlying from user
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve router
        IERC20(underlyingAsset).safeIncreaseAllowance(address(router), amount);

        // Build token input
        IPendleRouter.TokenInput memory input = IPendleRouter.TokenInput({
            tokenIn: underlyingAsset,
            netTokenIn: amount,
            tokenMintSy: underlyingAsset,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: IPendleRouter.SwapData({
                swapType: IPendleRouter.SwapType.NONE,
                extRouter: address(0),
                extCalldata: "",
                needScale: false
            })
        });

        // Build approx params for PT guess
        IPendleRouter.ApproxParams memory approx = IPendleRouter.ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 1e15 // 0.1%
        });

        uint256 minLpOut = (amount * (BPS - slippageTolerance)) / BPS;

        // Add liquidity
        (shares,) = router.addLiquiditySingleToken(
            address(this),
            address(market),
            minLpOut,
            approx,
            input
        );

        totalLPShares += shares;
        totalDeposited += amount;

        emit LPDeposited(msg.sender, address(market), shares, amount);
    }

    /**
     * @notice Withdraw LP and convert back to underlying
     * @param amount Amount of shares to redeem
     * @return assets Underlying received
     */
    function withdraw(uint256 amount) external nonReentrant returns (uint256 assets) {
        uint256 shares = amount; // amount parameter represents shares for this strategy
        if (shares == 0) revert ZeroAmount();
        if (shares > totalLPShares) revert InsufficientBalance(shares, totalLPShares);

        // Build token output
        IPendleRouter.TokenOutput memory output = IPendleRouter.TokenOutput({
            tokenOut: underlyingAsset,
            minTokenOut: 0,
            tokenRedeemSy: underlyingAsset,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: IPendleRouter.SwapData({
                swapType: IPendleRouter.SwapType.NONE,
                extRouter: address(0),
                extCalldata: "",
                needScale: false
            })
        });

        // Remove liquidity
        (assets,) = router.removeLiquiditySingleToken(
            msg.sender,
            address(market),
            shares,
            output
        );

        totalLPShares -= shares;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
    }

    /**
     * @notice Get total assets in underlying terms
     * @return Total value of LP position in underlying
     */
    function totalAssets() external view returns (uint256) {
        if (totalLPShares == 0) return 0;

        // LP value approximation based on SY exchange rate
        uint256 syRate = sy.exchangeRate();
        uint256 activeSupply = market.totalActiveSupply();

        if (activeSupply == 0) return 0;

        // Simplified: assume LP value tracks SY value
        return (totalLPShares * syRate) / 1e18;
    }

    /**
     * @notice Get current APY
     * @return APY in basis points
     */
    function currentAPY() external view returns (uint256) {
        // APY from trading fees + PENDLE rewards
        // Simplified estimate - actual APY varies with volume and incentives
        return 1000; // 10% placeholder - should integrate with Pendle's APY oracle
    }

    /**
     * @notice Get underlying asset
     * @return Underlying asset address
     */
    function asset() external view returns (address) {
        return underlyingAsset;
    }

    /**
     * @notice Harvest PENDLE rewards
     * @return harvested Amount harvested in underlying terms
     */
    function harvest() external nonReentrant returns (uint256 harvested) {
        uint256[] memory rewards = market.redeemRewards(address(this));

        address[] memory rewardTokens = market.getRewardTokens();
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewards[i] > 0) {
                emit RewardsClaimed(address(this), rewardTokens[i], rewards[i]);
                harvested += rewards[i]; // Simplified - should convert to underlying
            }
        }

        pendingRewards += harvested;
    }

    /**
     * @notice Check if strategy is active
     * @return True if active and not expired
     */
    function isActive() external view returns (bool) {
        return active && !market.isExpired();
    }

    /**
     * @notice Get strategy name
     * @return Strategy name
     */
    function name() external view returns (string memory) {
        return _strategyName;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set slippage tolerance
     * @param _slippage New slippage in BPS
     */
    function setSlippageTolerance(uint256 _slippage) external onlyOwner {
        if (_slippage > MAX_SLIPPAGE) revert SlippageExceeded(MAX_SLIPPAGE, _slippage);
        slippageTolerance = _slippage;
    }

    /**
     * @notice Pause/unpause strategy
     * @param _active New active state
     */
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /**
     * @notice Emergency withdraw all LP
     */
    function emergencyWithdraw(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 lpBalance = IERC20(address(market)).balanceOf(address(this));
        if (lpBalance > 0) {
            IERC20(address(market)).safeTransfer(msg.sender, lpBalance);
        }

        active = false;
        totalLPShares = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PENDLE PT STRATEGY (FIXED YIELD)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title PendlePTStrategy
 * @notice Strategy for holding Principal Tokens to maturity for fixed yield
 * @dev Buys PT at discount, holds until maturity, redeems 1:1 for underlying
 *
 * Yield mechanism:
 * - PT trades at discount to underlying (e.g., 0.95 ETH for 1 PT-stETH)
 * - At maturity, PT redeems 1:1 for underlying (1 PT = 1 stETH)
 * - Yield = discount captured (e.g., 5.26% if bought at 0.95)
 *
 * Advantages:
 * - Fixed, guaranteed yield (if held to maturity)
 * - No impermanent loss
 * - Simple strategy
 *
 * Risks:
 * - Opportunity cost if rates rise
 * - Must hold to maturity for guaranteed yield
 * - Smart contract risk
 */
contract PendlePTStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Seconds per year for APY calculation
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Pendle router
    IPendleRouter public immutable router;

    /// @notice Pendle market
    IPendleMarket public immutable market;

    /// @notice PT token
    IPendlePT public immutable pt;

    /// @notice SY token
    IPendleSY public immutable sy;

    /// @notice YT token for redemption
    address public immutable yt;

    /// @notice Underlying asset
    address public immutable underlyingAsset;

    /// @notice Strategy name
    string private _strategyName;

    /// @notice Is strategy active
    bool public active;

    /// @notice Total PT held
    uint256 public totalPT;

    /// @notice Total deposited for yield tracking
    uint256 public totalDeposited;

    /// @notice Average purchase price (in underlying terms, scaled by 1e18)
    uint256 public averagePurchasePrice;

    /// @notice Slippage tolerance in BPS
    uint256 public slippageTolerance;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize Pendle PT strategy
     * @param _router Pendle router address
     * @param _market Pendle market address
     * @param _underlying Underlying asset address
     * @param strategyName Name for this strategy
     */
    constructor(
        address _router,
        address _market,
        address _underlying,
        string memory strategyName
    ) Ownable(msg.sender) {
        if (_router == address(0) || _market == address(0)) revert InvalidMarket(_market);

        router = IPendleRouter(_router);
        market = IPendleMarket(_market);

        (address _sy, address _pt, address _yt) = market.readTokens();
        sy = IPendleSY(_sy);
        pt = IPendlePT(_pt);
        yt = _yt;
        underlyingAsset = _underlying;

        _strategyName = strategyName;
        active = true;
        slippageTolerance = 100; // 1% default
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenActive() {
        if (!active) revert StrategyPaused();
        _;
    }

    modifier notExpired() {
        if (pt.isExpired()) revert MarketExpired(address(market), pt.expiry());
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit underlying and swap for PT
     * @param amount Amount of underlying to deposit
     * @return shares PT tokens received
     */
    function deposit(uint256 amount) external nonReentrant whenActive notExpired returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer underlying
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Approve router
        IERC20(underlyingAsset).safeIncreaseAllowance(address(router), amount);

        // Build token input
        IPendleRouter.TokenInput memory input = IPendleRouter.TokenInput({
            tokenIn: underlyingAsset,
            netTokenIn: amount,
            tokenMintSy: underlyingAsset,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: IPendleRouter.SwapData({
                swapType: IPendleRouter.SwapType.NONE,
                extRouter: address(0),
                extCalldata: "",
                needScale: false
            })
        });

        // Build approx params
        IPendleRouter.ApproxParams memory approx = IPendleRouter.ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 1e15
        });

        uint256 minPtOut = (amount * (BPS - slippageTolerance)) / BPS;

        // Swap underlying for PT
        (shares,) = router.swapExactTokenForPt(
            address(this),
            address(market),
            minPtOut,
            approx,
            input
        );

        // Update average purchase price
        if (totalPT == 0) {
            averagePurchasePrice = (amount * 1e18) / shares;
        } else {
            uint256 totalCost = (averagePurchasePrice * totalPT) / 1e18 + amount;
            averagePurchasePrice = (totalCost * 1e18) / (totalPT + shares);
        }

        totalPT += shares;
        totalDeposited += amount;

        emit PTMinted(msg.sender, address(market), shares, amount);
    }

    /**
     * @notice Withdraw PT - either swap or redeem at maturity
     * @param amount Amount of shares to redeem
     * @return assets Underlying received
     */
    function withdraw(uint256 amount) external nonReentrant returns (uint256 assets) {
        uint256 shares = amount; // amount parameter represents shares for this strategy
        if (shares == 0) revert ZeroAmount();
        if (shares > totalPT) revert InsufficientBalance(shares, totalPT);

        if (pt.isExpired()) {
            // At maturity: redeem PT+YT for underlying via SY
            // Note: Assumes strategy holds matching YT (or YT has expired worthless)
            IPendleRouter.TokenOutput memory output = IPendleRouter.TokenOutput({
                tokenOut: underlyingAsset,
                minTokenOut: 0,
                tokenRedeemSy: underlyingAsset,
                bulk: address(0),
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });

            // Approve and redeem
            IERC20(address(pt)).safeIncreaseAllowance(address(router), shares);
            assets = router.redeemPyToToken(msg.sender, yt, shares, output);
        } else {
            // Before maturity: swap PT back to underlying
            IPendleRouter.TokenOutput memory outputSwap = IPendleRouter.TokenOutput({
                tokenOut: underlyingAsset,
                minTokenOut: 0,
                tokenRedeemSy: underlyingAsset,
                bulk: address(0),
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });

            IERC20(address(pt)).safeIncreaseAllowance(address(router), shares);
            (assets,) = router.swapExactPtForToken(msg.sender, address(market), shares, outputSwap);
        }

        totalPT -= shares;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
    }

    /**
     * @notice Get total assets (PT valued at maturity value)
     * @return Total underlying value at maturity
     */
    function totalAssets() external view returns (uint256) {
        // PT redeems 1:1 at maturity, so totalPT equals underlying at maturity
        return totalPT;
    }

    /**
     * @notice Get fixed yield APY based on discount
     * @return APY in basis points
     */
    function currentAPY() external view returns (uint256) {
        if (averagePurchasePrice == 0 || averagePurchasePrice >= 1e18) return 0;

        uint256 expiry = pt.expiry();
        if (block.timestamp >= expiry) return 0;

        uint256 remaining = expiry - block.timestamp;
        if (remaining == 0) return 0;

        // APY = ((1 / purchasePrice) - 1) * (SECONDS_PER_YEAR / timeToMaturity) * 10000
        // If purchasePrice = 0.95e18, yield = 5.26%
        uint256 yieldMultiplier = (1e18 * 1e18) / averagePurchasePrice; // e.g., 1.0526e18
        uint256 absoluteYield = yieldMultiplier - 1e18; // e.g., 0.0526e18

        uint256 annualizedYield = (absoluteYield * SECONDS_PER_YEAR) / remaining;

        return (annualizedYield * BPS) / 1e18;
    }

    /**
     * @notice Get underlying asset
     * @return Underlying asset address
     */
    function asset() external view returns (address) {
        return underlyingAsset;
    }

    /**
     * @notice Harvest - no yield until maturity for PT strategy
     * @return harvested Always 0 for PT strategy
     */
    function harvest() external returns (uint256 harvested) {
        return 0; // PT yield is captured at maturity, not through harvest
    }

    /**
     * @notice Check if strategy is active
     * @return True if active
     */
    function isActive() external view returns (bool) {
        return active;
    }

    /**
     * @notice Get strategy name
     * @return Strategy name
     */
    function name() external view returns (string memory) {
        return _strategyName;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get time to maturity in seconds
     * @return Time remaining until expiry
     */
    function timeToMaturity() external view returns (uint256) {
        uint256 expiry = pt.expiry();
        if (block.timestamp >= expiry) return 0;
        return expiry - block.timestamp;
    }

    /**
     * @notice Check if PT has matured
     * @return True if expired
     */
    function isMatured() external view returns (bool) {
        return pt.isExpired();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set slippage tolerance
     * @param _slippage New slippage in BPS
     */
    function setSlippageTolerance(uint256 _slippage) external onlyOwner {
        slippageTolerance = _slippage;
    }

    /**
     * @notice Set active state
     * @param _active New active state
     */
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /**
     * @notice Emergency withdraw all PT
     */
    function emergencyWithdraw(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 balance = IERC20(address(pt)).balanceOf(address(this));
        if (balance > 0) {
            IERC20(address(pt)).safeTransfer(msg.sender, balance);
        }

        active = false;
        totalPT = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// vePENDLE STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title VePendleStrategy
 * @notice Strategy for locking PENDLE as vePENDLE for protocol fees + vote incentives
 * @dev Locks PENDLE tokens, claims protocol fees, votes for gauges
 *
 * Yield sources:
 * 1. Protocol fees (share of all Pendle trading fees in ETH)
 * 2. Vote incentives (bribes from protocols wanting gauge votes)
 * 3. Boosted LP rewards (if used to boost LP positions)
 *
 * vePENDLE mechanics:
 * - Lock PENDLE for up to 2 years
 * - Longer lock = more voting power
 * - Vote power decays linearly to 0 at expiry
 * - Can extend lock or add more PENDLE
 * - Cannot withdraw until lock expires
 */
contract VePendleStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Minimum lock duration (1 week)
    uint256 public constant MIN_LOCK_DURATION = 7 days;

    /// @notice Maximum lock duration (2 years)
    uint256 public constant MAX_LOCK_DURATION = 730 days;

    /// @notice Week in seconds (for Pendle epoch alignment)
    uint256 public constant WEEK = 7 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice PENDLE token
    IERC20 public immutable pendle;

    /// @notice vePENDLE contract
    IVePendle public immutable vePendle;

    /// @notice Fee distributor for claiming protocol fees
    IPendleFeeDistributor public immutable feeDistributor;

    /// @notice Voting controller for gauge votes
    IPendleVotingController public immutable votingController;

    /// @notice Strategy name
    string private _strategyName;

    /// @notice Is strategy active
    bool public active;

    /// @notice Current lock expiry
    uint128 public lockExpiry;

    /// @notice Pools to claim fees from
    address[] public feePools;

    /// @notice Total PENDLE deposited
    uint256 public totalPendleLocked;

    /// @notice Total deposited for yield tracking
    uint256 public totalDeposited;

    /// @notice Accumulated ETH fees
    uint256 public accumulatedFees;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize vePENDLE strategy
     * @param _pendle PENDLE token address
     * @param _vePendle vePENDLE contract address
     * @param _feeDistributor Fee distributor address
     * @param _votingController Voting controller address
     * @param strategyName Name for this strategy
     */
    constructor(
        address _pendle,
        address _vePendle,
        address _feeDistributor,
        address _votingController,
        string memory strategyName
    ) Ownable(msg.sender) {
        pendle = IERC20(_pendle);
        vePendle = IVePendle(_vePendle);
        feeDistributor = IPendleFeeDistributor(_feeDistributor);
        votingController = IPendleVotingController(_votingController);

        _strategyName = strategyName;
        active = true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenActive() {
        if (!active) revert StrategyPaused();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IYieldStrategy IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit PENDLE and lock as vePENDLE
     * @param amount Amount of PENDLE to lock
     * @return shares vePENDLE balance after deposit
     */
    function deposit(uint256 amount, bytes calldata /* data */) external nonReentrant whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer PENDLE
        pendle.safeTransferFrom(msg.sender, address(this), amount);

        // Approve vePENDLE
        pendle.safeIncreaseAllowance(address(vePendle), amount);

        // Calculate new expiry (extend to max or keep current if longer)
        uint128 newExpiry;
        if (lockExpiry == 0 || block.timestamp >= lockExpiry) {
            // New lock: set to 2 years, rounded to week
            newExpiry = uint128(((block.timestamp + MAX_LOCK_DURATION) / WEEK) * WEEK);
        } else {
            // Existing lock: keep expiry (could optionally extend here)
            newExpiry = lockExpiry;
        }

        // Lock PENDLE
        uint128 newVeBalance = vePendle.increaseLockPosition(uint128(amount), newExpiry);

        lockExpiry = newExpiry;
        totalPendleLocked += amount;
        totalDeposited += amount;
        shares = newVeBalance;

        emit VePendleLocked(msg.sender, amount, newExpiry, newVeBalance);
    }

    /**
     * @notice Withdraw PENDLE after lock expires
     * @param amount Amount to withdraw (must be full balance after expiry)
     * @return assets PENDLE received
     */
    function withdraw(uint256 amount, address recipient, bytes calldata /* data */) external nonReentrant returns (uint256 assets) {
        uint256 shares = amount; // amount parameter represents shares for this strategy
        if (shares == 0) revert ZeroAmount();
        if (block.timestamp < lockExpiry) revert LockNotExpired(lockExpiry, block.timestamp);

        // Withdraw all PENDLE
        assets = vePendle.withdraw();

        if (assets < shares) revert InsufficientBalance(shares, assets);

        // Transfer to recipient
        pendle.safeTransfer(msg.sender, assets);

        totalPendleLocked = 0;
        totalDeposited = 0;
        lockExpiry = 0;
    }

    /**
     * @notice Get total assets (locked PENDLE)
     * @return Total PENDLE locked
     */
    function totalAssets() external view returns (uint256) {
        return totalPendleLocked;
    }

    /**
     * @notice Get current APY from protocol fees
     * @return APY in basis points
     */
    function currentAPY() external view returns (uint256) {
        // APY from protocol fees - varies based on protocol revenue
        // Placeholder - should integrate with fee distributor for actual data
        return 500; // 5% placeholder
    }

    /**
     * @notice Get underlying asset (PENDLE)
     * @return PENDLE token address
     */
    function asset() external view returns (address) {
        return address(pendle);
    }

    /**
     * @notice Harvest protocol fees
     * @return harvested ETH fees claimed
     */
    function harvest() external nonReentrant returns (uint256 harvested) {
        if (feePools.length == 0) return 0;

        (harvested,) = feeDistributor.claimProtocol(address(this), feePools);
        accumulatedFees += harvested;

        emit RewardsClaimed(address(this), address(0), harvested); // address(0) = ETH
    }

    /**
     * @notice Check if strategy is active
     * @return True if active
     */
    function isActive() external view returns (bool) {
        return active;
    }

    /**
     * @notice Get strategy name
     * @return Strategy name
     */
    function name() external view returns (string memory) {
        return _strategyName;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Vote for Pendle gauges
     * @param pools Pool addresses to vote for
     * @param weights Vote weights (must sum to 10000)
     */
    function vote(address[] calldata pools, uint64[] calldata weights) external onlyOwner {
        votingController.vote(pools, weights);
    }

    /**
     * @notice Get vote status for a pool
     * @param pool Pool address
     * @return weight Current vote weight
     * @return lastEpoch Last voted epoch
     */
    function getVoteStatus(address pool) external view returns (uint64 weight, uint64 lastEpoch) {
        return votingController.getUserPoolVote(address(this), pool);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current vePENDLE balance
     * @return Current voting power
     */
    function veBalance() external view returns (uint128) {
        return vePendle.balanceOf(address(this));
    }

    /**
     * @notice Get lock position details
     * @return amount PENDLE locked
     * @return expiry Lock expiry timestamp
     */
    function getLockPosition() external view returns (uint128 amount, uint128 expiry) {
        return vePendle.positionData(address(this));
    }

    /**
     * @notice Get claimable fees
     * @return claimable Total claimable fees
     */
    function getClaimableFees() external view returns (uint256 claimable) {
        if (feePools.length == 0) return 0;

        (claimable,) = feeDistributor.getProtocolClaimables(address(this), feePools);
    }

    /**
     * @notice Get time until lock expires
     * @return Time in seconds
     */
    function timeToUnlock() external view returns (uint256) {
        if (block.timestamp >= lockExpiry) return 0;
        return lockExpiry - block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set fee pools to claim from
     * @param pools Array of pool addresses
     */
    function setFeePools(address[] calldata pools) external onlyOwner {
        feePools = pools;
    }

    /**
     * @notice Extend lock duration
     * @param newExpiry New expiry timestamp (must be >= current)
     */
    function extendLock(uint128 newExpiry) external onlyOwner {
        if (newExpiry <= lockExpiry) revert InvalidLockDuration(newExpiry);

        // Extend without adding more PENDLE
        vePendle.increaseLockPosition(0, newExpiry);
        lockExpiry = newExpiry;
    }

    /**
     * @notice Set active state
     * @param _active New active state
     */
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /**
     * @notice Withdraw accumulated ETH fees
     */
    function withdrawFees(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = recipient.call{value: balance}("");
            require(success, "ETH transfer failed");
            accumulatedFees = 0;
        }
    }

    /// @notice Receive ETH from fee claims
    receive() external payable {}
}
