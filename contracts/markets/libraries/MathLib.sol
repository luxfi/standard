// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

/// @title MathLib
/// @notice Math utilities for Markets
library MathLib {
    uint256 internal constant WAD = 1e18;

    /// @notice Returns the minimum of two values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Returns the maximum of two values
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Multiplies two numbers and divides by a third, rounding down
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @notice Multiplies two numbers and divides by a third, rounding up
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + d - 1) / d;
    }

    /// @notice Returns the WAD value of a number
    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    /// @notice Returns the WAD value of a number, rounding up
    function wMulUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD);
    }

    /// @notice Divides a number by WAD, rounding down
    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    /// @notice Divides a number by WAD, rounding up
    function wDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }
}
