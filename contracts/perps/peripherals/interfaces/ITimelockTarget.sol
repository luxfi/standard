// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface ITimelockTarget {
    function setGov(address _gov) external;
    function withdrawToken(address _token, address _account, uint256 _amount) external;
}
