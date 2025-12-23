// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.4;

/// @title Math
/// Library for non-standard Math functions
/// NOTE: This file is a clone of the dydx protocol's Decimal.sol contract.
/// It was forked from https://github.com/dydxprotocol/solo at commit
/// 2d8454e02702fe5bc455b848556660629c3cad36. Updated for Solidity 0.8+ with
/// native overflow checks (SafeMath no longer needed).
library Math {
    // ============ Library Functions ============

    /*
     * Return target * (numerator / denominator).
     */
    function getPartial(
        uint256 target,
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        return (target * numerator) / denominator;
    }

    /*
     * Return target * (numerator / denominator), but rounded up.
     */
    function getPartialRoundUp(
        uint256 target,
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        if (target == 0 || numerator == 0) {
            require(denominator > 0, "Math: division by zero");
            return 0;
        }
        return ((target * numerator) - 1) / denominator + 1;
    }

    function to128(uint256 number) internal pure returns (uint128) {
        uint128 result = uint128(number);
        require(result == number, "Math: Unsafe cast to uint128");
        return result;
    }

    function to96(uint256 number) internal pure returns (uint96) {
        uint96 result = uint96(number);
        require(result == number, "Math: Unsafe cast to uint96");
        return result;
    }

    function to32(uint256 number) internal pure returns (uint32) {
        uint32 result = uint32(number);
        require(result == number, "Math: Unsafe cast to uint32");
        return result;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
