// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IObligation - Universal Obligation Primitive
 * @notice What is owed, and how does it evolve over time?
 * @dev THIS IS THE THEOLOGICAL AND REGULATORY LINE
 * 
 * ╔════════════════════════════════════════════════════════════════════════════╗
 * ║  CRITICAL DISTINCTION: Only TWO types of obligations exist                 ║
 * ╠════════════════════════════════════════════════════════════════════════════╣
 * ║  INCREASING: Balance grows over time (Compound, Maple)                     ║
 * ║              - Interest accrues                                            ║
 * ║              - Borrower fights the clock                                   ║
 * ║              - NOT Shariah-compliant (riba)                               ║
 * ║              - Creates debt spirals                                        ║
 * ╠════════════════════════════════════════════════════════════════════════════╣
 * ║  DECREASING: Balance shrinks over time (Alchemix, prepaid)                ║
 * ║              - Yield settles obligation                                    ║
 * ║              - Time benefits the user                                      ║
 * ║              - Shariah-compliant                                           ║
 * ║              - Self-liquidating                                            ║
 * ╚════════════════════════════════════════════════════════════════════════════╝
 */

/// @notice The fundamental direction of obligation evolution
/// @dev This single enum is the ethical core of the entire system
enum Monotonicity {
    INCREASING,     // Obligation grows over time (traditional debt)
    DECREASING,     // Obligation shrinks over time (self-repaying)
    STATIC          // Fixed obligation, no time component
}

/// @notice Obligation lifecycle states
enum ObligationState {
    PENDING,        // Created but not yet active
    ACTIVE,         // Currently accruing/settling
    SETTLED,        // Fully paid/repaid
    DEFAULTED,      // Failed to meet terms
    LIQUIDATED      // Forcibly closed
}

interface IObligation {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event ObligationCreated(bytes32 indexed id, address indexed obligor, uint256 principal, Monotonicity direction);
    event ObligationUpdated(bytes32 indexed id, uint256 oldBalance, uint256 newBalance);
    event ObligationSettled(bytes32 indexed id, uint256 amount, uint256 remaining);
    event ObligationClosed(bytes32 indexed id, ObligationState finalState);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE STATE - THE FUNDAMENTAL QUESTION
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice How does this obligation evolve over time?
    /// @dev THIS IS THE SINGLE MOST IMPORTANT FUNCTION IN THE SYSTEM
    function direction() external view returns (Monotonicity);
    
    /// @notice Current obligation balance
    function balance() external view returns (uint256);
    
    /// @notice Original obligation amount
    function principal() external view returns (uint256);
    
    /// @notice Current state of the obligation
    function state() external view returns (ObligationState);
    
    /// @notice Who owes this obligation
    function obligor() external view returns (address);
    
    /// @notice When the obligation was created
    function inception() external view returns (uint256);
    
    /// @notice When the obligation must be settled (0 = no deadline)
    function maturity() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // OBLIGATION OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Create a new obligation
    /// @param obligor Address taking on the obligation
    /// @param amount Initial obligation amount
    /// @param direction Whether obligation increases or decreases
    /// @return id Unique obligation identifier
    function create(
        address obligor,
        uint256 amount,
        Monotonicity direction
    ) external returns (bytes32 id);
    
    /// @notice Update obligation balance (for increasing obligations)
    /// @dev Only valid for INCREASING obligations - accrues interest/fees
    function accrue() external returns (uint256 newBalance);
    
    /// @notice Reduce obligation balance
    /// @param amount Amount to reduce by
    /// @return remaining Balance after reduction
    function reduce(uint256 amount) external returns (uint256 remaining);
    
    /// @notice Apply settlement from yield (for decreasing obligations)
    /// @param yieldAmount Yield to apply against obligation
    /// @return settled Amount of obligation settled
    function applyYield(uint256 yieldAmount) external returns (uint256 settled);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // PROJECTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Project obligation balance at a future time
    /// @param timestamp Future timestamp
    /// @return projected Expected balance at that time
    function projectBalance(uint256 timestamp) external view returns (uint256 projected);
    
    /// @notice Time until obligation is fully settled (for decreasing)
    /// @return timeInSeconds Time to settlement (type(uint256).max if increasing)
    function timeToSettlement() external view returns (uint256 timeInSeconds);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SHARIAH COMPLIANCE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Is this obligation Shariah-compliant?
    /// @dev INCREASING obligations are NOT compliant (riba)
    /// DECREASING and STATIC obligations CAN be compliant
    function isShariahCompliant() external view returns (bool);
    
    /// @notice Does this obligation create a debt spiral risk?
    /// @dev Only INCREASING obligations can create debt spirals
    function hasDebtSpiralRisk() external view returns (bool);
}

/**
 * @title ObligationLib
 * @notice Helper functions for obligation calculations
 */
library ObligationLib {
    /// @notice Check if obligation direction is ethical (non-increasing)
    function isEthical(Monotonicity direction) internal pure returns (bool) {
        return direction != Monotonicity.INCREASING;
    }
    
    /// @notice Check if obligation can be used for credit cards
    function isCreditCardCompatible(Monotonicity direction) internal pure returns (bool) {
        // Only decreasing obligations work for self-repaying credit
        return direction == Monotonicity.DECREASING;
    }
}
