// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IRisk - Universal Risk Primitive
 * @notice What happens when assumptions break?
 * @dev Risk management is OPTIONAL, not mandatory for all positions
 * 
 * IMPORTANT DISTINCTIONS:
 *   - Liquidation is OPTIONAL
 *   - Seizure ≠ Default
 *   - Time-based penalties are NOT mandatory
 *   - Self-repaying positions may not need risk intervention
 * 
 * Risk Sources:
 *   - Collateral value decline (Compound, Aave)
 *   - Counterparty default (Maple RWAs)
 *   - Strategy failure (Alchemix yield)
 *   - Market volatility (GMX positions)
 *   - Smart contract risk (all protocols)
 */

/// @notice Risk intervention type
enum InterventionType {
    NONE,           // No intervention needed/allowed
    LIQUIDATION,    // Collateral seizure to cover obligation
    MARGIN_CALL,    // Request additional collateral
    WIND_DOWN,      // Gradual position reduction
    INSURANCE,      // Claim against reserve/insurance
    RESTRUCTURE     // Modify terms to prevent default
}

/// @notice Health status of a position
enum HealthStatus {
    HEALTHY,        // No intervention needed
    WARNING,        // Approaching risk threshold
    CRITICAL,       // Immediate action recommended
    LIQUIDATABLE,   // Can be liquidated
    INSOLVENT       // Cannot be made whole
}

interface IRisk {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event HealthUpdated(bytes32 indexed positionId, uint256 oldHealth, uint256 newHealth);
    event RiskWarning(bytes32 indexed positionId, HealthStatus status, string message);
    event InterventionTriggered(bytes32 indexed positionId, InterventionType intervention);
    event LiquidationExecuted(bytes32 indexed positionId, uint256 collateralSeized, uint256 debtCovered);
    event InsuranceClaimed(bytes32 indexed positionId, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Current health factor (scaled by 1e18, >1e18 = healthy)
    function health(bytes32 positionId) external view returns (uint256);
    
    /// @notice Current health status
    function healthStatus(bytes32 positionId) external view returns (HealthStatus);
    
    /// @notice Allowed intervention types for this position
    function allowedInterventions(bytes32 positionId) external view returns (InterventionType[] memory);
    
    /// @notice Liquidation threshold (health factor below which liquidation is allowed)
    function liquidationThreshold() external view returns (uint256);
    
    /// @notice Warning threshold (health factor below which warnings are issued)
    function warningThreshold() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // RISK ASSESSMENT
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Calculate health factor for a position
    /// @param positionId Position to assess
    /// @return healthFactor Scaled health (1e18 = 100%)
    function assessHealth(bytes32 positionId) external returns (uint256 healthFactor);
    
    /// @notice Check if position can be liquidated
    /// @param positionId Position to check
    /// @return canLiquidate True if liquidatable
    function isLiquidatable(bytes32 positionId) external view returns (bool canLiquidate);
    
    /// @notice Get collateral value for a position
    /// @param positionId Position to check
    /// @return value Current collateral value
    function collateralValue(bytes32 positionId) external view returns (uint256 value);
    
    /// @notice Get debt value for a position
    /// @param positionId Position to check
    /// @return value Current debt value
    function debtValue(bytes32 positionId) external view returns (uint256 value);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INTERVENTION
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Trigger intervention on an unhealthy position
    /// @param positionId Position to intervene on
    /// @return intervention Type of intervention executed
    function intervene(bytes32 positionId) external returns (InterventionType intervention);
    
    /// @notice Execute liquidation on a position
    /// @param positionId Position to liquidate
    /// @param amount Amount of debt to cover
    /// @return seized Collateral seized
    function liquidate(bytes32 positionId, uint256 amount) external returns (uint256 seized);
    
    /// @notice Request margin call (additional collateral)
    /// @param positionId Position needing collateral
    /// @return required Amount of collateral required
    function marginCall(bytes32 positionId) external returns (uint256 required);
    
    /// @notice Restructure position terms
    /// @param positionId Position to restructure
    /// @param newTerms Encoded new terms
    function restructure(bytes32 positionId, bytes calldata newTerms) external;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // INSURANCE & RESERVES
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Check if position is covered by insurance
    /// @param positionId Position to check
    /// @return covered True if insured
    function isInsured(bytes32 positionId) external view returns (bool covered);
    
    /// @notice Claim insurance for a defaulted position
    /// @param positionId Defaulted position
    /// @return claimed Amount claimed from insurance
    function claimInsurance(bytes32 positionId) external returns (uint256 claimed);
    
    /// @notice Available reserve/insurance pool balance
    function reserveBalance() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SELF-REPAYING POSITION HANDLING
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Check if position is self-repaying (decreasing obligation)
    /// @dev Self-repaying positions may not need traditional risk intervention
    /// @param positionId Position to check
    /// @return selfRepaying True if position settles itself over time
    function isSelfRepaying(bytes32 positionId) external view returns (bool selfRepaying);
    
    /// @notice For self-repaying positions: time until safe (fully settled)
    /// @param positionId Position to check
    /// @return time Seconds until position is fully settled
    function timeToSafe(bytes32 positionId) external view returns (uint256 time);
}

/**
 * @title RiskLib
 * @notice Helper functions for risk calculations
 */
library RiskLib {
    uint256 constant HEALTH_PRECISION = 1e18;
    uint256 constant DEFAULT_LIQUIDATION_THRESHOLD = 1e18; // 100%
    uint256 constant DEFAULT_WARNING_THRESHOLD = 1.25e18;  // 125%
    
    /// @notice Calculate health factor from collateral and debt
    function calculateHealth(
        uint256 collateral,
        uint256 debt
    ) internal pure returns (uint256) {
        if (debt == 0) return type(uint256).max;
        return (collateral * HEALTH_PRECISION) / debt;
    }
    
    /// @notice Check if position needs intervention
    function needsIntervention(
        uint256 healthFactor,
        uint256 threshold
    ) internal pure returns (bool) {
        return healthFactor < threshold;
    }
    
    /// @notice Self-repaying positions don't need traditional liquidation
    function shouldSkipLiquidation(bool isSelfRepaying) internal pure returns (bool) {
        return isSelfRepaying;
    }
}
