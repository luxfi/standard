// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {MarketParams, Id} from "../interfaces/IMarkets.sol";

/// @title MarketParamsLib
/// @notice Library for MarketParams operations
library MarketParamsLib {
    /// @notice Computes the market ID from market parameters
    function id(MarketParams memory marketParams) internal pure returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams)));
    }
}
