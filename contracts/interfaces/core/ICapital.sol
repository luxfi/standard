// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title ICapital - Universal Capital Primitive
 * @notice Where does value originate?
 * @dev Capital is the foundational primitive - all DeFi reduces to capital flows
 * 
 * Examples:
 *   - Compound supply pool
 *   - GMX liquidity pool  
 *   - Alchemix yield vault
 *   - Maple RWA SPV
 *   - Olympus treasury
 *   - Validator stake
 */

/// @notice Risk classification for capital
enum RiskTier {
    SOVEREIGN,      // Protocol-owned, no external risk
    SECURED,        // Overcollateralized, liquidatable
    UNSECURED,      // Credit-based, reputation risk
    SPECULATIVE     // High volatility, trading exposure
}

/// @notice Capital state
enum CapitalState {
    IDLE,           // Available for deployment
    DEPLOYED,       // Actively generating yield
    LOCKED,         // Time-locked or vesting
    LIQUIDATING     // Being unwound
}

interface ICapital {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event CapitalDeposited(address indexed from, uint256 amount, bytes32 indexed sourceId);
    event CapitalWithdrawn(address indexed to, uint256 amount, bytes32 indexed sourceId);
    event CapitalDeployed(bytes32 indexed sourceId, address indexed yieldEngine, uint256 amount);
    event CapitalRecalled(bytes32 indexed sourceId, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CORE STATE
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Total principal deposited (excludes yield)
    function principal() external view returns (uint256);
    
    /// @notice Expected yield based on current deployments
    function expectedYield() external view returns (uint256);
    
    /// @notice Realized but unclaimed yield
    function realizedYield() external view returns (uint256);
    
    /// @notice Risk classification of this capital source
    function riskTier() external view returns (RiskTier);
    
    /// @notice Current operational state
    function state() external view returns (CapitalState);
    
    /// @notice Underlying asset (address(0) for native)
    function asset() external view returns (address);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CAPITAL OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Deposit capital into the source
    /// @param amount Amount to deposit
    /// @return sourceId Unique identifier for this capital position
    function deposit(uint256 amount) external returns (bytes32 sourceId);
    
    /// @notice Withdraw capital from the source
    /// @param sourceId Position identifier
    /// @param amount Amount to withdraw
    function withdraw(bytes32 sourceId, uint256 amount) external;
    
    /// @notice Deploy capital to a yield engine
    /// @param amount Amount to deploy
    /// @param yieldEngine Target yield generator
    function deploy(uint256 amount, address yieldEngine) external;
    
    /// @notice Recall capital from deployment
    /// @param amount Amount to recall
    /// @param yieldEngine Source yield engine
    function recall(uint256 amount, address yieldEngine) external;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ACCOUNTING
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Total value = principal + realized yield + expected yield
    function totalValue() external view returns (uint256);
    
    /// @notice Available for withdrawal (not deployed or locked)
    function available() external view returns (uint256);
    
    /// @notice Currently deployed amount
    function deployed() external view returns (uint256);
}
