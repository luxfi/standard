// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IRewardRouterV2 {
    function feeGlpTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
}
