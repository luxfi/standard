// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IBridge {
    function wrap(uint256 _amount, address _receiver) external;
    function unwrap(uint256 _amount, address _receiver) external;
}
