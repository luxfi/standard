// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

interface ILightAccount {
    function owner() external view returns (address owner);

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external;
}
