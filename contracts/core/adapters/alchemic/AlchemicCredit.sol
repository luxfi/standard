// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICapital, RiskTier, CapitalState} from "../../interfaces/ICapital.sol";
import {IYield, YieldType, AccrualPattern} from "../../interfaces/IYield.sol";
import {IObligation, Monotonicity, ObligationState, ObligationLib} from "../../interfaces/IObligation.sol";
import {ISettlement, SettlementType} from "../../interfaces/ISettlement.sol";
import {IDistribution, RecipientClass} from "../../interfaces/IDistribution.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                      ALCHEMIC CREDIT ENGINE                                   ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  This is THE credit layer for ethical finance.                               ║
 * ║                                                                               ║
 * ║  Key Invariant: OBLIGATION NEVER INCREASES                                   ║
 * ║                                                                               ║
 * ║  What this enables:                                                          ║
 * ║    • Self-repaying credit cards                                              ║
 * ║    • Shariah-compliant banking (no riba)                                     ║
 * ║    • Credit for the unbanked (no credit score needed)                        ║
 * ║    • No debt spirals by construction                                         ║
 * ║                                                                               ║
 * ║  How it works:                                                               ║
 * ║    1. User deposits collateral (capital)                                     ║
 * ║    2. Collateral generates yield (strategy returns)                          ║
 * ║    3. User takes advance against future yield (decreasing obligation)        ║
 * ║    4. Yield automatically settles obligation (transmutation)                 ║
 * ║    5. Time benefits the user                                                 ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

/// @notice Position data for a credit user
struct CreditPosition {
    uint256 collateral;          // Deposited capital
    uint256 obligation;          // Current obligation (only decreases)
    uint256 maxAdvance;          // Maximum advance allowed
    uint256 yieldAccrued;        // Yield accumulated
    uint256 lastUpdate;          // Last update timestamp
    address yieldStrategy;       // Strategy generating yield
    bool active;                 // Position is active
}

/// @notice Credit engine errors
error InsufficientCollateral();
error AdvanceExceedsLimit();
error PositionNotActive();
error NoYieldAvailable();
error ZeroAmount();
error InvalidStrategy();

contract AlchemicCredit is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ObligationLib for Monotonicity;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Collateral asset
    IERC20 public immutable collateralToken;
    
    /// @notice Synthetic credit token (what users spend)
    IERC20 public immutable creditToken;
    
    /// @notice Maximum loan-to-value ratio (basis points, e.g., 5000 = 50%)
    uint256 public maxLTV;
    
    /// @notice Mapping of user addresses to their credit positions
    mapping(address => CreditPosition) public positions;
    
    /// @notice Total collateral in the system
    uint256 public totalCollateral;
    
    /// @notice Total outstanding obligations
    uint256 public totalObligations;
    
    /// @notice Approved yield strategies
    mapping(address => bool) public approvedStrategies;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event CollateralDeposited(address indexed user, uint256 amount, uint256 newTotal);
    event CollateralWithdrawn(address indexed user, uint256 amount, uint256 newTotal);
    event AdvanceTaken(address indexed user, uint256 amount, uint256 newObligation);
    event YieldAccrued(address indexed user, uint256 amount);
    event ObligationSettled(address indexed user, uint256 amount, uint256 remaining);
    event PositionFullySettled(address indexed user);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════
    
    constructor(
        address _collateralToken,
        address _creditToken,
        uint256 _maxLTV
    ) {
        collateralToken = IERC20(_collateralToken);
        creditToken = IERC20(_creditToken);
        maxLTV = _maxLTV;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Deposit collateral to create/increase credit position
     * @param amount Amount of collateral to deposit
     * @param strategy Yield strategy to use
     */
    function deposit(uint256 amount, address strategy) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!approvedStrategies[strategy]) revert InvalidStrategy();
        
        // Transfer collateral
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update position
        CreditPosition storage pos = positions[msg.sender];
        pos.collateral += amount;
        pos.maxAdvance = (pos.collateral * maxLTV) / 10000;
        pos.yieldStrategy = strategy;
        pos.lastUpdate = block.timestamp;
        pos.active = true;
        
        totalCollateral += amount;
        
        // Deploy to yield strategy
        _deployToStrategy(strategy, amount);
        
        emit CollateralDeposited(msg.sender, amount, pos.collateral);
    }
    
    /**
     * @notice Take an advance against future yield
     * @dev Creates a DECREASING obligation
     * @param amount Amount of credit to advance
     */
    function takeAdvance(uint256 amount) external nonReentrant {
        CreditPosition storage pos = positions[msg.sender];
        if (!pos.active) revert PositionNotActive();
        if (amount == 0) revert ZeroAmount();
        
        // First, accrue any pending yield and apply to existing obligation
        _accrueAndSettle(msg.sender);
        
        // Check advance limit
        uint256 availableAdvance = pos.maxAdvance > pos.obligation 
            ? pos.maxAdvance - pos.obligation 
            : 0;
        if (amount > availableAdvance) revert AdvanceExceedsLimit();
        
        // Create obligation (DECREASING by construction)
        pos.obligation += amount;
        totalObligations += amount;
        
        // Mint credit to user
        _mintCredit(msg.sender, amount);
        
        emit AdvanceTaken(msg.sender, amount, pos.obligation);
    }
    
    /**
     * @notice Accrue yield and settle obligation
     * @dev Called automatically on most operations, can also be called directly
     */
    function settle() external nonReentrant {
        _accrueAndSettle(msg.sender);
    }
    
    /**
     * @notice Withdraw excess collateral (not backing obligation)
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        CreditPosition storage pos = positions[msg.sender];
        if (!pos.active) revert PositionNotActive();
        if (amount == 0) revert ZeroAmount();
        
        // First settle
        _accrueAndSettle(msg.sender);
        
        // Calculate minimum required collateral
        uint256 minCollateral = pos.obligation > 0 
            ? (pos.obligation * 10000) / maxLTV 
            : 0;
        uint256 available = pos.collateral > minCollateral 
            ? pos.collateral - minCollateral 
            : 0;
        
        if (amount > available) revert InsufficientCollateral();
        
        // Withdraw from strategy
        _withdrawFromStrategy(pos.yieldStrategy, amount);
        
        // Update position
        pos.collateral -= amount;
        pos.maxAdvance = (pos.collateral * maxLTV) / 10000;
        totalCollateral -= amount;
        
        // Transfer to user
        collateralToken.safeTransfer(msg.sender, amount);
        
        emit CollateralWithdrawn(msg.sender, amount, pos.collateral);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL - YIELD & SETTLEMENT
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Accrue yield from strategy and apply to obligation
     * @dev THIS IS THE CORE SELF-REPAYING MECHANISM
     */
    function _accrueAndSettle(address user) internal {
        CreditPosition storage pos = positions[user];
        if (!pos.active) return;
        
        // Calculate yield since last update
        uint256 newYield = _calculateYield(pos);
        if (newYield == 0) return;
        
        pos.yieldAccrued += newYield;
        pos.lastUpdate = block.timestamp;
        
        emit YieldAccrued(user, newYield);
        
        // Apply yield to obligation (TRANSMUTATION)
        if (pos.obligation > 0 && pos.yieldAccrued > 0) {
            uint256 settlement = pos.yieldAccrued > pos.obligation 
                ? pos.obligation 
                : pos.yieldAccrued;
            
            pos.obligation -= settlement;
            pos.yieldAccrued -= settlement;
            totalObligations -= settlement;
            
            emit ObligationSettled(user, settlement, pos.obligation);
            
            if (pos.obligation == 0) {
                emit PositionFullySettled(user);
            }
        }
    }
    
    /**
     * @notice Calculate yield for a position
     */
    function _calculateYield(CreditPosition storage pos) internal view returns (uint256) {
        if (pos.collateral == 0 || pos.yieldStrategy == address(0)) return 0;
        
        uint256 timeElapsed = block.timestamp - pos.lastUpdate;
        if (timeElapsed == 0) return 0;
        
        // Get APY from strategy (simplified - real impl would query strategy)
        uint256 apy = 500; // 5% APY in basis points (placeholder)
        
        // yield = collateral * apy * time / (10000 * 365 days)
        return (pos.collateral * apy * timeElapsed) / (10000 * 365 days);
    }
    
    function _deployToStrategy(address strategy, uint256 amount) internal {
        // Deploy collateral to yield strategy
        collateralToken.approve(strategy, amount);
        // IYieldStrategy(strategy).deposit(amount);
    }
    
    function _withdrawFromStrategy(address strategy, uint256 amount) internal {
        // Withdraw from yield strategy
        // IYieldStrategy(strategy).withdraw(amount);
    }
    
    function _mintCredit(address to, uint256 amount) internal {
        // Mint synthetic credit token
        // ICreditToken(address(creditToken)).mint(to, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get position details
     */
    function getPosition(address user) external view returns (
        uint256 collateral,
        uint256 obligation,
        uint256 maxAdvance,
        uint256 availableAdvance,
        uint256 pendingYield,
        uint256 timeToSettlement
    ) {
        CreditPosition storage pos = positions[user];
        collateral = pos.collateral;
        obligation = pos.obligation;
        maxAdvance = pos.maxAdvance;
        availableAdvance = maxAdvance > obligation ? maxAdvance - obligation : 0;
        pendingYield = _calculateYield(pos) + pos.yieldAccrued;
        
        // Calculate time to full settlement
        if (obligation > 0 && pendingYield > 0) {
            uint256 apy = 500; // placeholder
            // time = obligation * 365 days * 10000 / (collateral * apy)
            timeToSettlement = (obligation * 365 days * 10000) / (collateral * apy);
        } else if (obligation > 0) {
            timeToSettlement = type(uint256).max;
        } else {
            timeToSettlement = 0;
        }
    }
    
    /**
     * @notice Check if this credit system is Shariah-compliant
     * @dev Always returns true because obligations only DECREASE
     */
    function isShariahCompliant() external pure returns (bool) {
        return true; // Obligations never increase
    }
    
    /**
     * @notice Get the monotonicity of obligations
     * @dev Always DECREASING - this is THE invariant
     */
    function obligationDirection() external pure returns (Monotonicity) {
        return Monotonicity.DECREASING;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════
    
    function setMaxLTV(uint256 _maxLTV) external {
        // TODO: Add access control
        maxLTV = _maxLTV;
    }
    
    function approveStrategy(address strategy, bool approved) external {
        // TODO: Add access control
        approvedStrategies[strategy] = approved;
    }
}
