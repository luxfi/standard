// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

// This contract does not implement the ILightAccount interface
// Specifically, it does not have the owner() function
contract MockInvalidLightAccount {
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external {
        // Empty implementation - we only need this for generating calldata
    }
}
