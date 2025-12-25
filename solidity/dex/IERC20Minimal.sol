// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC20Minimal
/// @notice Minimal ERC20 interface for DEX token interactions
interface IERC20Minimal {
    /// @notice Transfer tokens from the contract to a recipient
    /// @dev Used by PoolManager to transfer tokens during settle/take
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfer tokens from one address to another
    /// @param from The sender address
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Approve tokens for spending
    /// @param spender The spender address
    /// @param amount The amount to approve
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Get the balance of an address
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get the allowance from a spender to an owner
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Get the total supply of tokens
    function totalSupply() external view returns (uint256);
}

/// @title IERC20
/// @notice Full ERC20 interface with events
interface IERC20 is IERC20Minimal {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
