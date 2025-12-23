// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

contract MockGaslessTarget {
    // First function to whitelist
    function foo(
        uint32 someNumber,
        uint8 someFlag
    ) external pure returns (bool) {
        // Just a dummy implementation
        return someNumber > 0 && someFlag > 0;
    }

    // Second function to whitelist
    function bar(
        address someAddress,
        uint256 someAmount
    ) external pure returns (uint256) {
        // Just a dummy implementation
        return someAddress != address(0) ? someAmount : 0;
    }
}
