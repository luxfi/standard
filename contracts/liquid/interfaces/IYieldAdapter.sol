// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

/**
 * @title IYieldAdapter
 * @notice Interface for yield-bearing token adapters
 * @dev Used by LiquidVault to interact with various yield sources
 */
interface IYieldAdapter {
    /// @notice Wrap underlying tokens into yield-bearing tokens
    /// @param amount Amount of underlying to wrap
    /// @param recipient Address to receive the wrapped tokens
    /// @return wrapped Amount of yield-bearing tokens minted
    function wrap(uint256 amount, address recipient) external returns (uint256 wrapped);

    /// @notice Unwrap yield-bearing tokens back to underlying
    /// @param amount Amount of yield-bearing tokens to unwrap
    /// @param recipient Address to receive the underlying tokens
    /// @return unwrapped Amount of underlying tokens returned
    function unwrap(uint256 amount, address recipient) external returns (uint256 unwrapped);

    /// @notice Harvest accrued yield
    /// @return harvested Amount of yield harvested
    function harvest() external returns (uint256 harvested);

    /// @notice Get the underlying token address
    function underlyingToken() external view returns (address);

    /// @notice Get the yield-bearing token address
    function token() external view returns (address);

    /// @notice Get current price of yield token in underlying terms
    function price() external view returns (uint256);

    /// @notice Get adapter version
    function version() external pure returns (string memory);
}
