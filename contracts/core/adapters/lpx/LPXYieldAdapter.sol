// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ICapital, RiskTier, CapitalState} from "../../interfaces/ICapital.sol";
import {IYield, YieldType, AccrualPattern} from "../../interfaces/IYield.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                         LPX YIELD ADAPTER                                     ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  ✅ FEE-BASED YIELD (Shariah-compliant)                                       ║
 * ║                                                                               ║
 * ║  LPX generates yield from TRADING FEES, not interest.                        ║
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
 * ║  │   Fees (LPX):                                                      │     ║
 * ║  │     • Payment for a SERVICE (providing liquidity)                  │     ║
 * ║  │     • Traders pay to access deep markets                           │     ║
 * ║  │     • Real value provided (market making)                          │     ║
 * ║  │     • Halal - legitimate business income                           │     ║
 * ║  └─────────────────────────────────────────────────────────────────────┘     ║
 * ║                                                                               ║
 * ║  How LPX works:                                                              ║
 * ║    1. LPs deposit into LLP (multi-asset pool)                               ║
 * ║    2. Traders use LLP for leverage trading                                  ║
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

/// @notice LLP vault interface (simplified)
interface ILLPManager {
    function addLiquidity(address _token, uint256 _amount, uint256 _minLpusd, uint256 _minLlp) external returns (uint256);
    function removeLiquidity(address _tokenOut, uint256 _llpAmount, uint256 _minOut, address _receiver) external returns (uint256);
}

/// @notice LLP token interface
interface ILLP {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Fee distributor interface
interface IFeeLlpTracker {
    function claimable(address _account) external view returns (uint256);
    function claim(address _receiver) external returns (uint256);
    function cumulativeRewards(address _account) external view returns (uint256);
}

/// @notice Staking rewards
interface ILPXRewardRouter {
    function mintAndStakeLlp(address _token, uint256 _amount, uint256 _minLpusd, uint256 _minLlp) external returns (uint256);
    function unstakeAndRedeemLlp(address _tokenOut, uint256 _llpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function handleRewards(
        bool _shouldClaimLpx,
        bool _shouldStakeLpx,
        bool _shouldClaimEsLpx,
        bool _shouldStakeEsLpx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
}

/// @notice Position data
struct YieldPosition {
    uint256 llpAmount;          // LLP tokens held
    uint256 depositValue;       // Original deposit value (USD)
    uint256 feesClaimed;        // Total fees claimed
    uint256 lastClaimTime;      // Last claim timestamp
    address depositToken;       // Token used for deposit
    bool active;                // Position is active
}

/// @notice Adapter errors
error ZeroAmount();
error PositionNotActive();
error InsufficientLLP();
error NoFeesToClaim();

/**
 * @title LPXYieldAdapter
 * @notice Fee-based yield source for Capital OS
 * @dev Wraps LPX LLP for Shariah-compliant yield generation
 */
contract LPXYieldAdapter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice LPX reward router
    ILPXRewardRouter public immutable rewardRouter;

    /// @notice LLP manager
    ILLPManager public immutable llpManager;

    /// @notice LLP token
    ILLP public immutable llp;

    /// @notice Fee tracker for LLP
    IFeeLlpTracker public immutable feeLlpTracker;

    /// @notice WETH for fee claims
    IERC20 public immutable weth;

    /// @notice User positions
    mapping(address => YieldPosition) public positions;

    /// @notice Total LLP in adapter
    uint256 public totalLLP;

    /// @notice Total fees generated
    uint256 public totalFeesGenerated;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, address token, uint256 amount, uint256 llpReceived);
    event Withdrawn(address indexed user, address token, uint256 llpBurned, uint256 received);
    event FeesClaimed(address indexed user, uint256 amount);
    event FeesHarvested(uint256 totalFees, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _rewardRouter,
        address _llpManager,
        address _llp,
        address _feeLlpTracker,
        address _weth
    ) {
        rewardRouter = ILPXRewardRouter(_rewardRouter);
        llpManager = ILLPManager(_llpManager);
        llp = ILLP(_llp);
        feeLlpTracker = IFeeLlpTracker(_feeLlpTracker);
        weth = IERC20(_weth);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAPITAL OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit capital to earn fee-based yield
     * @param token Token to deposit (WETH, USDC, etc.)
     * @param amount Amount to deposit
     * @param minLlp Minimum LLP to receive
     * @return llpReceived Amount of LLP minted
     */
    function deposit(
        address token,
        uint256 amount,
        uint256 minLlp
    ) external nonReentrant returns (uint256 llpReceived) {
        if (amount == 0) revert ZeroAmount();

        // Transfer token
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(llpManager), amount);

        // Mint and stake LLP
        llpReceived = rewardRouter.mintAndStakeLlp(token, amount, 0, minLlp);

        // Update position
        YieldPosition storage pos = positions[msg.sender];
        pos.llpAmount += llpReceived;
        pos.depositValue += _getTokenValue(token, amount);
        pos.depositToken = token;
        pos.lastClaimTime = block.timestamp;
        pos.active = true;

        totalLLP += llpReceived;

        emit Deposited(msg.sender, token, amount, llpReceived);
    }

    /**
     * @notice Withdraw capital
     * @param tokenOut Token to receive
     * @param llpAmount LLP to burn
     * @param minOut Minimum tokens to receive
     * @return received Amount received
     */
    function withdraw(
        address tokenOut,
        uint256 llpAmount,
        uint256 minOut
    ) external nonReentrant returns (uint256 received) {
        YieldPosition storage pos = positions[msg.sender];
        if (!pos.active) revert PositionNotActive();
        if (llpAmount > pos.llpAmount) revert InsufficientLLP();

        // Claim pending fees first
        _claimFees(msg.sender);

        // Unstake and redeem
        received = rewardRouter.unstakeAndRedeemLlp(tokenOut, llpAmount, minOut, msg.sender);

        // Update position
        pos.llpAmount -= llpAmount;
        if (pos.llpAmount == 0) {
            pos.active = false;
        }

        totalLLP -= llpAmount;

        emit Withdrawn(msg.sender, tokenOut, llpAmount, received);
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

        // Claim WETH fees from LPX
        rewardRouter.handleRewards(
            false,  // don't claim LPX
            false,  // don't stake LPX
            false,  // don't claim esLPX
            false,  // don't stake esLPX
            false,  // don't stake multiplier points
            true,   // claim WETH
            false   // keep as WETH
        );

        // Calculate user's share
        YieldPosition storage pos = positions[user];
        claimed = (pending * pos.llpAmount) / totalLLP;

        pos.feesClaimed += claimed;
        pos.lastClaimTime = block.timestamp;
        totalFeesGenerated += claimed;

        // Transfer fees to user
        weth.safeTransfer(user, claimed);

        emit FeesClaimed(user, claimed);
    }

    /**
     * @notice Harvest all fees (callable by anyone)
     * @dev Triggers fee distribution from LPX
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
        if (!pos.active || pos.llpAmount == 0) return 0;

        uint256 totalPending = feeLlpTracker.claimable(address(this));
        return (totalPending * pos.llpAmount) / totalLLP;
    }

    /**
     * @notice Get position summary
     */
    function getPosition(address user) external view returns (
        uint256 llpAmount,
        uint256 depositValue,
        uint256 currentValue,
        uint256 feesClaimed,
        uint256 pendingFees,
        uint256 totalReturn,
        uint256 apy
    ) {
        YieldPosition storage pos = positions[user];

        llpAmount = pos.llpAmount;
        depositValue = pos.depositValue;
        feesClaimed = pos.feesClaimed;
        pendingFees = getPendingFees(user);

        // Estimate current LLP value
        if (llpAmount > 0 && llp.totalSupply() > 0) {
            // Simplified - real impl would use LLP price
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
        yieldSource = "Trading fees from perpetual traders using LLP liquidity";
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
        if (!pos.active || pos.llpAmount == 0) return CapitalState.IDLE;
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
        if (!pos.active || pos.llpAmount == 0) return 0;

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

contract LPXYieldAdapterFactory {
    event AdapterCreated(address indexed adapter);

    function create(
        address rewardRouter,
        address llpManager,
        address llp,
        address feeLlpTracker,
        address weth
    ) external returns (address) {
        LPXYieldAdapter adapter = new LPXYieldAdapter(
            rewardRouter,
            llpManager,
            llp,
            feeLlpTracker,
            weth
        );
        emit AdapterCreated(address(adapter));
        return address(adapter);
    }
}
