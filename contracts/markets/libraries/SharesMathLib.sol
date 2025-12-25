// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {MathLib} from "./MathLib.sol";

/// @title SharesMathLib
/// @notice Shares math utilities for Markets
library SharesMathLib {
    using MathLib for uint256;

    /// @notice Virtual assets for share calculations (prevents inflation attacks)
    uint256 internal constant VIRTUAL_ASSETS = 1;
    
    /// @notice Virtual shares for share calculations
    uint256 internal constant VIRTUAL_SHARES = 1e6;

    /// @notice Converts assets to shares, rounding down
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @notice Converts assets to shares, rounding up
    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @notice Converts shares to assets, rounding down
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivDown(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /// @notice Converts shares to assets, rounding up
    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivUp(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }
}
