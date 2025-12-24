// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {MarketParams, Market} from "./IMarkets.sol";

/// @title IRateModel
/// @notice Interest Rate Model interface for Markets
interface IRateModel {
    /// @notice Returns the borrow rate per second (scaled by 1e18)
    /// @param marketParams The market parameters
    /// @param market The current market state
    /// @return The borrow rate per second with 18 decimals
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256);

    /// @notice Returns the borrow rate per second for a given utilization
    /// @param id The market ID
    /// @param utilization The utilization rate (scaled by 1e18)
    /// @return The borrow rate per second with 18 decimals
    function borrowRateView(bytes32 id, uint256 utilization) external view returns (uint256);
}
