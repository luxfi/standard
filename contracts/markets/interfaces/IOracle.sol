// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

/// @title IOracle
/// @notice Oracle interface for Markets price feeds
interface IOracle {
    /// @notice Returns the price of the collateral asset in terms of the loan asset
    /// @dev Price is scaled by 1e36 (ORACLE_PRICE_SCALE)
    /// @return The price with 36 decimals of precision
    function price() external view returns (uint256);
}
