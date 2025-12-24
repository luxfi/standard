// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IPositionRouterCallbackReceiver {
    function lpxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external;
}
