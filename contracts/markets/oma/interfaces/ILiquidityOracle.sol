// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title ILiquidityOracle
/// @notice Minimal oracle interface for Oracle-Mirrored AMM price feeds
/// @dev All prices are 18 decimals in USD terms
interface ILiquidityOracle {
    /// @notice Get the latest price for a symbol
    /// @param symbol The asset symbol (e.g., "AAPL", "BTC")
    /// @return price The price in USD with 18 decimals
    /// @return timestamp When the price was last updated
    function getPrice(string calldata symbol) external view returns (uint256 price, uint256 timestamp);

    /// @notice Get prices for multiple symbols in a single call
    /// @param symbols Array of asset symbols
    /// @return prices Array of prices (18 decimals USD)
    /// @return timestamps Array of update timestamps
    function getPriceBatch(string[] calldata symbols)
        external
        view
        returns (uint256[] memory prices, uint256[] memory timestamps);
}
