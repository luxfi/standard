// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

interface IHandlerTarget {
    function isHandler(address _account) external returns (bool);
    function setHandler(address _handler, bool _isActive) external;
}
