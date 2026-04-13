// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IOracleMirroredAMM
/// @notice Interface for Oracle-Mirrored AMM — oracle-priced swap against settlement account
interface IOracleMirroredAMM {
    /// @notice Execute a swap (buy or sell) against the oracle price
    /// @param symbol The asset symbol (e.g., "AAPL", "BTC")
    /// @param isBuy True = buy asset with base token, false = sell asset for base token
    /// @param amountIn Amount of input token (18 decimals)
    /// @param minAmountOut Minimum acceptable output (slippage protection)
    /// @return amountOut Actual output amount
    function swap(string calldata symbol, bool isBuy, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    /// @notice Get the execution price for a symbol including margin
    /// @param symbol The asset symbol
    /// @param isBuy True for buy price (higher), false for sell price (lower)
    /// @return execPrice The execution price with margin applied (18 decimals)
    /// @return oraclePrice The raw oracle price without margin (18 decimals)
    function getExecutionPrice(string calldata symbol, bool isBuy)
        external
        view
        returns (uint256 execPrice, uint256 oraclePrice);

    /// @notice Register a symbol-to-token mapping
    /// @param symbol The asset symbol
    /// @param token The SecurityToken address for that symbol
    function registerSymbol(string calldata symbol, address token) external;

    /// @notice Update the margin in basis points
    /// @param newMarginBps New margin (max 500 = 5%)
    function setMargin(uint256 newMarginBps) external;

    event Swap(
        address indexed user,
        bytes32 indexed symbolHash,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionPrice
    );
    event SymbolRegistered(bytes32 indexed symbolHash, string symbol, address token);
    event MarginUpdated(uint256 oldMargin, uint256 newMargin);
    event MaxDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);
    event MaxStalenessUpdated(uint256 oldStaleness, uint256 newStaleness);
}
