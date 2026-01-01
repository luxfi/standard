// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

/// @title IWETH
/// @notice Wrapped native token interface
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}
