// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title ILiquidStrategy
 * @author Lux Industries
 * @notice Interface for ETH yield strategy adapters used by LiquidVault
 * @dev Strategies receive ETH and return ETH + yield
 *
 * Implemented by:
 * - YearnWETHStrategy (Yearn Finance wETH vault)
 * - LidoStrategy (stETH staking)
 * - AaveV3Strategy (Aave V3 ETH lending)
 * - EigenLayerStrategy (restaking)
 */
interface ILiquidStrategy {
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 amount, uint256 shares);
    event Withdrawn(uint256 amount, uint256 shares);
    event Harvested(uint256 yield);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotVault();
    error ZeroAmount();
    error InsufficientBalance();
    error WithdrawalFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit ETH into the strategy
     * @dev Only callable by LiquidVault
     */
    function deposit() external payable;

    /**
     * @notice Withdraw ETH from the strategy
     * @param amount Amount to withdraw (in ETH terms)
     * @return withdrawn Actual amount withdrawn (may differ due to slippage)
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawn);

    /**
     * @notice Harvest yield and send back to vault as ETH
     * @return yield Amount of yield harvested
     */
    function harvest() external returns (uint256 yield);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the current balance in ETH terms
     * @return Current value of strategy holdings
     */
    function balance() external view returns (uint256);

    /**
     * @notice Get pending yield (not yet harvested)
     * @return Estimated pending yield
     */
    function pendingYield() external view returns (uint256);

    /**
     * @notice Get the vault address that controls this strategy
     */
    function vault() external view returns (address);

    /**
     * @notice Get human-readable strategy name
     */
    function name() external view returns (string memory);

    /**
     * @notice Get strategy version
     */
    function version() external view returns (string memory);

    /**
     * @notice Check if the strategy is healthy
     * @return True if strategy can accept deposits/withdrawals
     */
    function isHealthy() external view returns (bool);
}
