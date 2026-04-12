// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title ISecurityToken
/// @notice Minimal interface for security tokens used by Oracle-Mirrored AMM
/// @dev SecurityToken in securities/token/ implements these via MINTER_ROLE
interface ISecurityToken {
    /// @notice Mint tokens to an address (requires MINTER_ROLE)
    /// @param to Recipient address
    /// @param amount Amount to mint (18 decimals)
    function mint(address to, uint256 amount) external;

    /// @notice Burn tokens from an address (requires approval or MINTER_ROLE)
    /// @param from Address to burn from
    /// @param amount Amount to burn (18 decimals)
    function burnFrom(address from, uint256 amount) external;
}
