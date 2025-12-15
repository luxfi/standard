// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IAllowList
 * @dev Base interface for allow-list managed precompiles
 *
 * The AllowList is a permission system used across multiple Lux EVM precompiles.
 * It defines four roles with different permission levels:
 *
 * Roles:
 * - None (0): No permissions
 * - Enabled (1): Can use the precompile functionality
 * - Admin (2): Can modify roles for any address
 * - Manager (3): Can modify roles for non-admin addresses (added in Durango)
 *
 * Role Hierarchy:
 * - Admin > Manager > Enabled > None
 * - Admins can set any role for any address
 * - Managers can set roles for Enabled and None addresses only
 *
 * Events:
 * - RoleSet: Emitted when a role is changed
 */
interface IAllowList {
    /**
     * @notice Emitted when a role is set
     * @param role The new role being set
     * @param account The address receiving the role
     * @param sender The address setting the role
     * @param oldRole The previous role of the account
     */
    event RoleSet(uint256 indexed role, address indexed account, address indexed sender, uint256 oldRole);

    /**
     * @notice Read the allow list role for an address
     * @param addr The address to check
     * @return role The role of the address (0=None, 1=Enabled, 2=Admin, 3=Manager)
     */
    function readAllowList(address addr) external view returns (uint256 role);

    /**
     * @notice Set an address as Admin (role 2)
     * @dev Only callable by Admin
     * @param addr The address to set as Admin
     */
    function setAdmin(address addr) external;

    /**
     * @notice Set an address as Enabled (role 1)
     * @dev Callable by Admin or Manager
     * @param addr The address to enable
     */
    function setEnabled(address addr) external;

    /**
     * @notice Set an address as Manager (role 3)
     * @dev Only callable by Admin. Added in Durango upgrade.
     * @param addr The address to set as Manager
     */
    function setManager(address addr) external;

    /**
     * @notice Remove all permissions from an address (role 0)
     * @dev Callable by Admin or Manager (for non-admin addresses)
     * @param addr The address to remove permissions from
     */
    function setNone(address addr) external;
}

/**
 * @title AllowListLib
 * @dev Library for working with AllowList precompiles
 */
library AllowListLib {
    /// @dev Role constants
    uint256 constant ROLE_NONE = 0;
    uint256 constant ROLE_ENABLED = 1;
    uint256 constant ROLE_ADMIN = 2;
    uint256 constant ROLE_MANAGER = 3;

    /// @dev Gas costs
    uint256 constant READ_ALLOWLIST_GAS = 2600;
    uint256 constant MODIFY_ALLOWLIST_GAS = 20000;

    error NotAdmin();
    error NotEnabled();
    error NotManager();

    /**
     * @notice Check if an address has at least Enabled role
     * @param allowList The allow list precompile address
     * @param addr The address to check
     * @return True if enabled, admin, or manager
     */
    function isEnabled(address allowList, address addr) internal view returns (bool) {
        uint256 role = IAllowList(allowList).readAllowList(addr);
        return role >= ROLE_ENABLED;
    }

    /**
     * @notice Check if an address is Admin
     * @param allowList The allow list precompile address
     * @param addr The address to check
     * @return True if admin
     */
    function isAdmin(address allowList, address addr) internal view returns (bool) {
        return IAllowList(allowList).readAllowList(addr) == ROLE_ADMIN;
    }

    /**
     * @notice Check if an address is Manager
     * @param allowList The allow list precompile address
     * @param addr The address to check
     * @return True if manager
     */
    function isManager(address allowList, address addr) internal view returns (bool) {
        return IAllowList(allowList).readAllowList(addr) == ROLE_MANAGER;
    }

    /**
     * @notice Require caller to be enabled
     * @param allowList The allow list precompile address
     */
    function requireEnabled(address allowList) internal view {
        if (!isEnabled(allowList, msg.sender)) {
            revert NotEnabled();
        }
    }

    /**
     * @notice Require caller to be admin
     * @param allowList The allow list precompile address
     */
    function requireAdmin(address allowList) internal view {
        if (!isAdmin(allowList, msg.sender)) {
            revert NotAdmin();
        }
    }
}
