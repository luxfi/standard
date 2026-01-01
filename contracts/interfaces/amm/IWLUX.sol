// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.31;

/// @title IWLUX - Wrapped LUX Interface
/// @notice Interface for WLUX (Wrapped LUX) token operations
interface IWLUX {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}
