// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.31;

/// @title IYieldAdapter
/// @notice Common interface for all yield-generating protocol adapters
/// @dev Implement this interface to integrate with Lux Alchemist vaults
interface IYieldAdapter {
    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Get the adapter version
    function version() external view returns (string memory);
    
    /// @notice Get the yield-bearing token address
    function token() external view returns (address);
    
    /// @notice Get the underlying asset address
    function underlyingToken() external view returns (address);
    
    /// @notice Get the current price per share (underlying per token)
    function price() external view returns (uint256);
    
    /// @notice Get current APY in basis points (100 = 1%)
    function apy() external view returns (uint256);
    
    /// @notice Get total value locked in underlying terms
    function tvl() external view returns (uint256);
    
    /// @notice Get available liquidity for withdrawals
    function availableLiquidity() external view returns (uint256);
    
    /// @notice Check if adapter is currently active
    function isActive() external view returns (bool);
    
    /// @notice Get protocol name
    function protocol() external view returns (string memory);
    
    /// @notice Get chain ID where the yield is generated
    function chainId() external view returns (uint256);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATIVE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════
    
    /// @notice Deposit underlying tokens and receive yield-bearing tokens
    /// @param amount Amount of underlying to deposit
    /// @param recipient Address to receive yield-bearing tokens
    /// @return shares Amount of yield-bearing tokens minted
    function wrap(uint256 amount, address recipient) external returns (uint256 shares);
    
    /// @notice Withdraw underlying tokens by burning yield-bearing tokens
    /// @param amount Amount of yield-bearing tokens to burn
    /// @param recipient Address to receive underlying tokens
    /// @return underlyingAmount Amount of underlying tokens returned
    function unwrap(uint256 amount, address recipient) external returns (uint256 underlyingAmount);
    
    /// @notice Harvest pending rewards
    /// @return rewards Amount of rewards harvested
    function harvest() external returns (uint256 rewards);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event Harvested(uint256 rewards);
}

/// @title ILendingAdapter
/// @notice Extended interface for lending protocol adapters (borrow + supply)
interface ILendingAdapter is IYieldAdapter {
    /// @notice Get max LTV ratio in basis points (8000 = 80%)
    function maxLTV() external view returns (uint256);
    
    /// @notice Get current borrow rate in basis points per year
    function borrowRate() external view returns (uint256);
    
    /// @notice Get current supply/lending rate in basis points per year  
    function supplyRate() external view returns (uint256);
    
    /// @notice Get utilization rate in basis points
    function utilizationRate() external view returns (uint256);
    
    /// @notice Borrow against deposited collateral
    /// @param amount Amount to borrow
    /// @param recipient Address to receive borrowed funds
    function borrow(uint256 amount, address recipient) external;
    
    /// @notice Repay borrowed amount
    /// @param amount Amount to repay
    function repay(uint256 amount) external;
    
    /// @notice Get user's borrowed amount
    function borrowedAmount(address user) external view returns (uint256);
    
    /// @notice Get user's collateral value
    function collateralValue(address user) external view returns (uint256);
    
    /// @notice Get user's health factor (>1 means safe)
    function healthFactor(address user) external view returns (uint256);
    
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
}
