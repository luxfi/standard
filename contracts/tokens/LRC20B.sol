// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ERC20B
 * @author Lux Industries
 * @notice Bridgeable ERC20 token with admin roles for cross-chain operations
 * @dev Combines Ownable (single owner) with AccessControl (admin roles) for flexible access control
 */
contract LRC20B is ERC20, Ownable, AccessControl {
    /// @notice Emitted when tokens are minted
    event LogMint(address indexed account, uint256 amount);

    /// @notice Emitted when tokens are burned
    event LogBurn(address indexed account, uint256 amount);

    /// @notice Emitted when admin role is granted
    event AdminGranted(address indexed to);

    /// @notice Emitted when admin role is revoked
    event AdminRevoked(address indexed to);

    /**
     * @notice Initializes the token with name, symbol, and sets deployer as owner/admin
     * @param name_ Token name
     * @param symbol_ Token symbol
     */
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Restricts function to admin role holders
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERC20B: caller is not admin");
        _;
    }

    /**
     * @notice Grants admin role to an address
     * @param to Address to grant admin role
     */
    function grantAdmin(address to) public onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminGranted(to);
    }

    /**
     * @notice Revokes admin role from an address
     * @param to Address to revoke admin role from
     */
    function revokeAdmin(address to) public onlyAdmin {
        require(hasRole(DEFAULT_ADMIN_ROLE, to), "ERC20B: not an admin");
        revokeRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminRevoked(to);
    }

    /**
     * @notice Mints tokens to an address (admin only)
     * @param account Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @return success True if mint succeeded
     */
    function mint(address account, uint256 amount) public onlyAdmin returns (bool) {
        _mint(account, amount);
        emit LogMint(account, amount);
        return true;
    }

    /**
     * @notice Burns tokens from an address (admin only)
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     * @return success True if burn succeeded
     */
    function burnIt(address account, uint256 amount) public onlyAdmin returns (bool) {
        _burn(account, amount);
        emit LogBurn(account, amount);
        return true;
    }
}
