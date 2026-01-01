// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ICapital, RiskTier, CapitalState} from "@luxfi/contracts/interfaces/core/ICapital.sol";
import {IYield, YieldType, AccrualPattern} from "@luxfi/contracts/interfaces/core/IYield.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                         GMX YIELD ADAPTER                                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  ✅ FEE-BASED YIELD (Shariah-compliant)                                       ║
 * ║                                                                               ║
 * ║  GMX generates yield from TRADING FEES, not interest.                        ║
 * ║  This is fundamentally different from Compound/Morpho.                       ║
 * ║                                                                               ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐     ║
 * ║  │   INTEREST vs FEES - The Critical Distinction                       │     ║
 * ║  │                                                                     │     ║
 * ║  │   Interest (Compound/Morpho):                                      │     ║
 * ║  │     • Payment for the passage of TIME                              │     ║
 * ║  │     • Borrower pays just for using money                           │     ║
 * ║  │     • No real service provided                                     │     ║
 * ║  │     • Riba (usury) - forbidden in Islamic finance                  │     ║
 * ║  │                                                                     │     ║
 * ║  │   Fees (GMX):                                                      │     ║
 * ║  │     • Payment for a SERVICE (providing liquidity)                  │     ║
 * ║  │     • Traders pay to access deep markets                           │     ║
 * ║  │     • Real value provided (market making)                          │     ║
 * ║  │     • Halal - legitimate business income                           │     ║
 * ║  └─────────────────────────────────────────────────────────────────────┘     ║
 * ║                                                                               ║
 * ║  How GMX works:                                                              ║
 * ║    1. LPs deposit into GLP (multi-asset pool)                               ║
 * ║    2. Traders use GLP for leverage trading                                  ║
 * ║    3. LPs earn 70% of trading fees                                          ║
 * ║    4. No interest - pure fee income                                         ║
 * ║                                                                               ║
 * ║  Risk profile:                                                               ║
 * ║    • Impermanent loss from asset rebalancing                                ║
 * ║    • Counterparty risk (if traders profit, LP loses)                        ║
 * ║    • But: No obligation creation                                            ║
 * ║                                                                               ║
 * ║  Role in Capital OS:                                                         ║
 * ║    YIELD SOURCE only - never used to create obligations                     ║
 * ║    Feeds into Alchemic to settle decreasing obligations                     ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

/// @notice GLP vault interface (simplified)
interface IGLPManager {
    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
    function removeLiquidity(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
}

/// @notice GLP token interface
interface IGLP {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Fee distributor interface
interface IFeeGlpTracker {
    function claimable(address _account) external view returns (uint256);
    function claim(address _receiver) external returns (uint256);
    function cumulativeRewards(address _account) external view returns (uint256);
}

/// @notice Staking rewards
interface IRewardRouter {
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}

/// @notice Position data
struct YieldPosition {
    uint256 glpAmount;          // GLP tokens held
    uint256 depositValue;       // Original deposit value (USD)
    uint256 feesClaimed;        // Total fees claimed
    uint256 lastClaimTime;      // Last claim timestamp
    address depositToken;       // Token used for deposit
    bool active;                // Position is active
}

/// @notice Adapter errors
error ZeroAmount();
error PositionNotActive();
error InsufficientGLP();
error NoFeesToClaim();

/**
 * @title GMXYieldAdapter
 * @notice Fee-based yield source for Capital OS
 * @dev Wraps GMX GLP for Shariah-compliant yield generation
 */
contract GMXYieldAdapter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice GMX reward router
    IRewardRouter public immutable rewardRouter;

    /// @notice GLP manager
    IGLPManager public immutable glpManager;

    /// @notice GLP token
    IGLP public immutable glp;

    /// @notice Fee tracker for GLP
    IFeeGlpTracker public immutable feeGlpTracker;

    /// @notice WETH for fee claims
    IERC20 public immutable weth;

    /// @notice User positions
    mapping(address => YieldPosition) public positions;

    /// @notice Total GLP in adapter
    uint256 public totalGLP;

    /// @notice Total fees generated
    uint256 public totalFeesGenerated;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, address token, uint256 amount, uint256 glpReceived);
    event Withdrawn(address indexed user, address token, uint256 glpBurned, uint256 received);
    event FeesClaimed(address indexed user, uint256 amount);
    event FeesHarvested(uint256 totalFees, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _rewardRouter,
        address _glpManager,
        address _glp,
        address _feeGlpTracker,
        address _weth
    ) {
        rewardRouter = IRewardRouter(_rewardRouter);
        glpManager = IGLPManager(_glpManager);
        glp = IGLP(_glp);
        feeGlpTracker = IFeeGlpTracker(_feeGlpTracker);
        weth = IERC20(_weth);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAPITAL OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit capital to earn fee-based yield
     * @param token Token to deposit (WETH, USDC, etc.)
     * @param amount Amount to deposit
     * @param minGlp Minimum GLP to receive
     * @return glpReceived Amount of GLP minted
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minGlp
    ) external nonReentrant returns (uint256 glpReceived) {
        if (amount == 0) revert ZeroAmount();

        // Transfer token
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(glpManager), amount);

        // Mint and stake GLP
        glpReceived = rewardRouter.mintAndStakeGlp(token, amount, 0, minGlp);

        // Update position
        YieldPosition storage pos = positions[msg.sender];
        pos.glpAmount += glpReceived;
        pos.depositValue += _getTokenValue(token, amount);
        pos.depositToken = token;
        pos.lastClaimTime = block.timestamp;
        pos.active = true;

        totalGLP += glpReceived;

        emit Deposited(msg.sender, token, amount, glpReceived);
    }

    /**
     * @notice Withdraw capital
     * @param tokenOut Token to receive
     * @param glpAmount GLP to burn
     * @param minOut Minimum tokens to receive
     * @return received Amount received
     */
    function withdraw(
        address tokenOut,
        uint256 glpAmount,
        uint256 minOut
    ) external nonReentrant returns (uint256 received) {
        YieldPosition storage pos = positions[msg.sender];
        if (!pos.active) revert PositionNotActive();
        if (glpAmount > pos.glpAmount) revert InsufficientGLP();

        // Claim pending fees first
        _claimFees(msg.sender);

        // Unstake and redeem
        received = rewardRouter.unstakeAndRedeemGlp(tokenOut, glpAmount, minOut, msg.sender);

        // Update position
        pos.glpAmount -= glpAmount;
        if (pos.glpAmount == 0) {
            pos.active = false;
        }

        totalGLP -= glpAmount;

        emit Withdrawn(msg.sender, tokenOut, glpAmount, received);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD OPERATIONS (FEE-BASED)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim accrued fees
     * @dev This is FEE yield, not interest
     * @return claimed Amount of fees claimed
     */
    function claimFees() external nonReentrant returns (uint256 claimed) {
        return _claimFees(msg.sender);
    }

    /**
     * @notice Internal fee claim
     */
    function _claimFees(address user) internal returns (uint256 claimed) {
        uint256 pending = getPendingFees(user);
        if (pending == 0) return 0;

        // Claim WETH fees from GMX
        rewardRouter.handleRewards(
            false,  // don't claim GMX
            false,  // don't stake GMX
            false,  // don't claim esGMX
            false,  // don't stake esGMX
            false,  // don't stake multiplier points
            true,   // claim WETH
            false   // keep as WETH
        );

        // Calculate user's share
        YieldPosition storage pos = positions[user];
        claimed = (pending * pos.glpAmount) / totalGLP;

        pos.feesClaimed += claimed;
        pos.lastClaimTime = block.timestamp;
        totalFeesGenerated += claimed;

        // Transfer fees to user
        weth.safeTransfer(user, claimed);

        emit FeesClaimed(user, claimed);
    }

    /**
     * @notice Harvest all fees (callable by anyone)
     * @dev Triggers fee distribution from GMX
     */
    function harvestFees() external {
        rewardRouter.handleRewards(
            false, false, false, false, false, true, false
        );

        uint256 balance = weth.balanceOf(address(this));
        emit FeesHarvested(balance, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get pending fees for a user
     */
    function getPendingFees(address user) public view returns (uint256) {
        YieldPosition storage pos = positions[user];
        if (!pos.active || pos.glpAmount == 0) return 0;

        uint256 totalPending = feeGlpTracker.claimable(address(this));
        return (totalPending * pos.glpAmount) / totalGLP;
    }

    /**
     * @notice Get position summary
     */
    function getPosition(address user) external view returns (
        uint256 glpAmount,
        uint256 depositValue,
        uint256 currentValue,
        uint256 feesClaimed,
        uint256 pendingFees,
        uint256 totalReturn,
        uint256 apy
    ) {
        YieldPosition storage pos = positions[user];

        glpAmount = pos.glpAmount;
        depositValue = pos.depositValue;
        feesClaimed = pos.feesClaimed;
        pendingFees = getPendingFees(user);

        // Estimate current GLP value
        if (glpAmount > 0 && glp.totalSupply() > 0) {
            // Simplified - real impl would use GLP price
            currentValue = depositValue; // Placeholder
        }

        totalReturn = currentValue + feesClaimed + pendingFees - depositValue;

        // Calculate APY from fees
        if (pos.lastClaimTime > 0 && depositValue > 0) {
            uint256 elapsed = block.timestamp - pos.lastClaimTime;
            if (elapsed > 0) {
                uint256 annualized = ((feesClaimed + pendingFees) * 365 days * 10000) / (depositValue * elapsed);
                apy = annualized;
            }
        }
    }

    /**
     * @notice Get yield type
     * @dev Returns FEE - not INTEREST
     */
    function yieldType() external pure returns (YieldType) {
        return YieldType.FEE;
    }

    /**
     * @notice Get accrual pattern
     */
    function accrualPattern() external pure returns (AccrualPattern) {
        return AccrualPattern.CONTINUOUS;
    }

    /**
     * @notice Check if yield is Shariah-compliant
     * @dev YES - fees for service are halal
     */
    function isShariahCompliant() external pure returns (bool) {
        return true; // Fee-based yield is permissible
    }

    /**
     * @notice Explain why this is Shariah-compliant
     */
    function shariahCompliance() external pure returns (
        bool compliant,
        string memory reason,
        string memory yieldSource,
        string memory comparisonToInterest
    ) {
        compliant = true;
        reason = "Fees represent payment for a legitimate service (market making / liquidity provision)";
        yieldSource = "Trading fees from perpetual traders using GLP liquidity";
        comparisonToInterest = "Unlike interest (riba), fees are earned through active service provision, not passive time-based extraction";
    }

    /**
     * @notice Get risk tier
     * @dev SPECULATIVE due to trader counterparty risk
     */
    function riskTier() external pure returns (RiskTier) {
        return RiskTier.SPECULATIVE;
    }

    /**
     * @notice Get capital state
     */
    function capitalState(address user) external view returns (CapitalState) {
        YieldPosition storage pos = positions[user];
        if (!pos.active || pos.glpAmount == 0) return CapitalState.IDLE;
        return CapitalState.DEPLOYED;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get token value in USD (placeholder)
     */
    function _getTokenValue(address token, uint256 amount) internal view returns (uint256) {
        // Real implementation would use oracle
        // Simplified: assume stablecoins = $1, WETH = $2000
        return amount; // Placeholder
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION WITH ALCHEMIC
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Route fees directly to settlement
     * @dev Called by Alchemic to auto-settle obligations
     * @param recipient Settlement contract address
     * @param maxAmount Maximum amount to route
     * @return routed Amount actually routed
     */
    function routeToSettlement(
        address recipient,
        uint256 maxAmount
    ) external nonReentrant returns (uint256 routed) {
        uint256 pending = getPendingFees(msg.sender);
        if (pending == 0) revert NoFeesToClaim();

        routed = pending > maxAmount ? maxAmount : pending;

        // Claim and transfer directly to settlement
        _claimFees(msg.sender);
        weth.safeTransfer(recipient, routed);
    }

    /**
     * @notice Project yield for settlement planning
     * @param user Position owner
     * @param timeHorizon Time to project (seconds)
     * @return projected Estimated fees over period
     */
    function projectYield(
        address user,
        uint256 timeHorizon
    ) external view returns (uint256 projected) {
        YieldPosition storage pos = positions[user];
        if (!pos.active || pos.glpAmount == 0) return 0;

        // Use historical rate to project
        if (pos.lastClaimTime > 0 && pos.feesClaimed > 0) {
            uint256 elapsed = block.timestamp - pos.lastClaimTime;
            if (elapsed > 0) {
                uint256 rate = (pos.feesClaimed * 1e18) / elapsed;
                projected = (rate * timeHorizon) / 1e18;
            }
        }
    }
}

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                              FACTORY                                         ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

contract GMXYieldAdapterFactory {
    event AdapterCreated(address indexed adapter);

    function create(
        address rewardRouter,
        address glpManager,
        address glp,
        address feeGlpTracker,
        address weth
    ) external returns (address) {
        GMXYieldAdapter adapter = new GMXYieldAdapter(
            rewardRouter,
            glpManager,
            glp,
            feeGlpTracker,
            weth
        );
        emit AdapterCreated(address(adapter));
        return address(adapter);
    }
}
