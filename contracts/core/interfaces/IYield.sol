// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IYield - Universal Yield Primitive
 * @notice How does capital grow or produce cashflow?
 * @dev Yield is the engine that transforms capital over time
 * 
 * CRITICAL DISTINCTION:
 *   Yield ≠ Interest
 *   Interest is just ONE yield mechanism (time-based obligation growth)
 * 
 * Yield Sources:
 *   - Compound: Interest from borrowers (time-based)
 *   - GMX: Trading fees from perpetuals (activity-based)
 *   - RWAs: Lease payments, coupons (contract-based)
 *   - Validators: Block rewards (consensus-based)
 *   - Protocol: Revenue share (fee-based)
 *   - Alchemix: Strategy returns (investment-based)
 */

/// @notice Classification of yield generation mechanism
enum YieldType {
    INTEREST,       // Time-based obligation growth (riba-adjacent)
    FEE,            // Activity-based (trading, transactions)
    REWARD,         // Protocol incentives, mining
    COUPON,         // Fixed periodic payments (RWA)
    DIVIDEND,       // Profit distribution
    APPRECIATION    // Asset value growth
}

/// @notice Yield accrual pattern
enum AccrualPattern {
    CONTINUOUS,     // Per-second/block accrual
    DISCRETE,       // Event-triggered
    PERIODIC,       // Fixed intervals (daily, weekly)
    ON_DEMAND       // Manual trigger required
}

interface IYield {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event YieldAccrued(uint256 amount, uint256 timestamp);
    event YieldRealized(uint256 amount, address indexed recipient);
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);
    event YieldSourceAdded(address indexed source, YieldType yieldType);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Type of yield this engine produces
    function yieldType() external view returns (YieldType);
    
    /// @notice How yield accrues
    function accrualPattern() external view returns (AccrualPattern);
    
    /// @notice Current yield rate (basis points or absolute)
    function currentRate() external view returns (uint256);
    
    /// @notice Total yield generated lifetime
    function totalGenerated() external view returns (uint256);
    
    /// @notice Yield pending distribution
    function pending() external view returns (uint256);
    
    /// @notice Yield already distributed
    function distributed() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Trigger yield accrual calculation
    /// @dev For continuous patterns, updates internal accounting
    /// @return accrued Amount of yield accrued since last call
    function accrue() external returns (uint256 accrued);
    
    /// @notice Realize pending yield (make available for distribution)
    /// @return realized Amount of yield realized
    function realize() external returns (uint256 realized);
    
    /// @notice Harvest yield to a specific recipient
    /// @param recipient Address to receive yield
    /// @param amount Amount to harvest (0 = all available)
    /// @return harvested Actual amount harvested
    function harvest(address recipient, uint256 amount) external returns (uint256 harvested);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // PROJECTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Project yield over a time period
    /// @param principal Capital amount
    /// @param duration Time period in seconds
    /// @return projected Expected yield
    function project(uint256 principal, uint256 duration) external view returns (uint256 projected);
    
    /// @notice Annual percentage yield (APY) in basis points
    function apy() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SHARIAH COMPLIANCE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Whether this yield type is Shariah-compliant
    /// @dev Interest-based yield (INTEREST type) is NOT compliant
    /// Fee, reward, dividend, appreciation types CAN be compliant
    function isShariahCompliant() external view returns (bool);
}
