// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;


interface ITimelockController {
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external payable;
}
