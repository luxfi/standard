// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

interface IMultisend {
    function multiSend(bytes memory encodedOperations) external payable;
}
