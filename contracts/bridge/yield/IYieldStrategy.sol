// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

/**
 * @title IYieldStrategy
 * @notice Interface for yield strategies on source chains
 * @dev Each strategy wraps a yield source (Lido, Rocket Pool, Aave, etc.)
 */
interface IYieldStrategy {
    /// @notice Deposit assets into the yield strategy
    /// @param amount Amount of underlying to deposit
    /// @return shares Amount of strategy shares received
    function deposit(uint256 amount) external payable returns (uint256 shares);

    /// @notice Withdraw assets from the yield strategy
    /// @param shares Amount of shares to redeem
    /// @return assets Amount of underlying received
    function withdraw(uint256 shares) external returns (uint256 assets);

    /// @notice Get total assets managed by this strategy
    /// @return Total assets in underlying terms
    function totalAssets() external view returns (uint256);

    /// @notice Get current yield rate (APY in basis points, e.g., 500 = 5%)
    /// @return APY in basis points
    function currentAPY() external view returns (uint256);

    /// @notice Get the underlying asset address
    /// @return Underlying asset address
    function asset() external view returns (address);

    /// @notice Harvest yield and return amount harvested
    /// @return harvested Amount of yield harvested in underlying terms
    function harvest() external returns (uint256 harvested);

    /// @notice Check if strategy is active
    /// @return True if strategy is accepting deposits
    function isActive() external view returns (bool);

    /// @notice Get strategy name for identification
    /// @return Strategy name
    function name() external view returns (string memory);

    /// @notice Get total deposited (tracked separately from totalAssets for accounting)
    /// @return Total deposited amount
    function totalDeposited() external view returns (uint256);
}

/**
 * @title IYieldStrategyFactory
 * @notice Factory for deploying yield strategies
 */
interface IYieldStrategyFactory {
    /// @notice Deploy a new yield strategy
    /// @param strategyType Type of strategy (LIDO, RETH, AAVE, etc.)
    /// @param underlying Underlying asset address
    /// @param params Strategy-specific parameters
    /// @return strategy Address of deployed strategy
    function deploy(
        bytes32 strategyType,
        address underlying,
        bytes calldata params
    ) external returns (address strategy);
}
