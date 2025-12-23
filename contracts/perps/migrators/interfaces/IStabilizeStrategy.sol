// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IStabilizeStrategy {
    function governanceFinishMoveEsGMXFromDeprecatedRouter(address _sender) external;
}
