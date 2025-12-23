// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

contract UniFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
}
