// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Monotonicity} from "./IObligation.sol";

/**
 * @title ISettlement - Universal Settlement Primitive
 * @notice How obligations are reduced or fulfilled
 * @dev Settlement is the bridge between yield and obligations
 * 
 * Settlement connects:
 *   Capital → Yield → Settlement → Obligation Reduction
 * 
 * Examples:
 *   - Alchemix transmutation (yield → debt paydown)
 *   - GMX fee distribution (fees → LP rewards)
 *   - RWA coupon payments (cash → bond redemption)
 *   - Card transaction settlement (spend → obligation creation + yield application)
 *   - Loan repayment (principal → obligation reduction)
 */

/// @notice Type of settlement mechanism
enum SettlementType {
    DIRECT,         // Direct payment reduces obligation
    TRANSMUTATION,  // Yield converts to settlement (Alchemix)
    NETTING,        // Offset multiple obligations
    STREAMING,      // Continuous settlement over time
    LIQUIDATION     // Forced settlement via collateral
}

/// @notice Settlement state
enum SettlementState {
    PENDING,        // Settlement initiated, not complete
    PROCESSING,     // In progress (multi-step settlement)
    COMPLETED,      // Successfully settled
    FAILED,         // Settlement failed
    REVERSED        // Settlement was reversed
}

interface ISettlement {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event SettlementInitiated(bytes32 indexed id, bytes32 indexed obligationId, uint256 amount);
    event SettlementApplied(bytes32 indexed id, uint256 amount, uint256 remainingObligation);
    event SettlementCompleted(bytes32 indexed id, uint256 totalSettled);
    event SettlementFailed(bytes32 indexed id, string reason);
    event YieldRouted(address indexed from, bytes32 indexed obligationId, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Type of settlement this engine performs
    function settlementType() external view returns (SettlementType);
    
    /// @notice Total amount settled through this engine
    function totalSettled() external view returns (uint256);
    
    /// @notice Amount currently pending settlement
    function pendingSettlement() external view returns (uint256);
    
    /// @notice Settlement rate (for streaming settlements)
    function settlementRate() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SETTLEMENT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Apply direct settlement to an obligation
    /// @param obligationId Target obligation
    /// @param amount Amount to settle
    /// @return settled Actual amount settled
    function settle(bytes32 obligationId, uint256 amount) external returns (uint256 settled);
    
    /// @notice Settle obligation using yield from a source
    /// @param obligationId Target obligation
    /// @param yieldSource Source of yield
    /// @param amount Amount of yield to use
    /// @return settled Amount of obligation settled
    function settleWithYield(
        bytes32 obligationId,
        address yieldSource,
        uint256 amount
    ) external returns (uint256 settled);
    
    /// @notice Transmute asset into settlement credit (Alchemix-style)
    /// @param asset Asset to transmute
    /// @param amount Amount to transmute
    /// @return credit Settlement credit generated
    function transmute(address asset, uint256 amount) external returns (uint256 credit);
    
    /// @notice Process streaming settlement
    /// @param obligationId Target obligation
    /// @return settled Amount settled this call
    function stream(bytes32 obligationId) external returns (uint256 settled);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ROUTING
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Route yield from a source to obligation settlement
    /// @param yieldSource Source generating yield
    /// @param obligationId Target obligation
    /// @param percentage Percentage of yield to route (basis points)
    function routeYield(
        address yieldSource,
        bytes32 obligationId,
        uint256 percentage
    ) external;
    
    /// @notice Set up automatic settlement from yield
    /// @param yieldSource Yield generator
    /// @param obligationId Obligation to settle
    function autoSettle(address yieldSource, bytes32 obligationId) external;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // PROJECTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Estimate settlement capacity from yield
    /// @param yieldSource Yield generator
    /// @param duration Time period
    /// @return capacity Expected settlement amount
    function projectSettlementCapacity(
        address yieldSource,
        uint256 duration
    ) external view returns (uint256 capacity);
    
    /// @notice Calculate time to full settlement
    /// @param obligationId Target obligation
    /// @param yieldSource Yield source
    /// @return time Estimated seconds to settlement
    function timeToFullSettlement(
        bytes32 obligationId,
        address yieldSource
    ) external view returns (uint256 time);
}

/**
 * @title SettlementLib
 * @notice Helper functions for settlement calculations
 */
library SettlementLib {
    /// @notice Check if settlement type is compatible with obligation direction
    function isCompatible(
        SettlementType sType,
        Monotonicity direction
    ) internal pure returns (bool) {
        // TRANSMUTATION only works with DECREASING obligations
        if (sType == SettlementType.TRANSMUTATION) {
            return direction == Monotonicity.DECREASING;
        }
        // All other types work with any direction
        return true;
    }
    
    /// @notice Check if settlement type supports streaming
    function supportsStreaming(SettlementType sType) internal pure returns (bool) {
        return sType == SettlementType.STREAMING || 
               sType == SettlementType.TRANSMUTATION;
    }
}
