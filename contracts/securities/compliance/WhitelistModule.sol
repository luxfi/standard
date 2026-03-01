// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IComplianceModule} from "../interfaces/IComplianceModule.sol";

/**
 * @title WhitelistModule
 * @notice Standalone compliance module that restricts transfers to whitelisted addresses.
 *         Can be plugged into ComplianceRegistry for layered compliance.
 *
 * Ported from Arca Labs' whitelist logic (Registry.sol + hanzo-solidity Whitelist).
 *
 * Restriction codes:
 *   16 = SENDER_NOT_ON_WHITELIST
 *   17 = RECEIVER_NOT_ON_WHITELIST
 */
contract WhitelistModule is IComplianceModule, AccessControl {
    bytes32 public constant WHITELIST_ADMIN_ROLE = keccak256("WHITELIST_ADMIN_ROLE");

    mapping(address => bool) public listed;

    event Added(address indexed account);
    event Removed(address indexed account);

    error ZeroAddress();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(WHITELIST_ADMIN_ROLE, admin);
    }

    function add(address account) external onlyRole(WHITELIST_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        listed[account] = true;
        emit Added(account);
    }

    function remove(address account) external onlyRole(WHITELIST_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        listed[account] = false;
        emit Removed(account);
    }

    function addBatch(address[] calldata accounts) external onlyRole(WHITELIST_ADMIN_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            listed[accounts[i]] = true;
            emit Added(accounts[i]);
        }
    }

    function removeBatch(address[] calldata accounts) external onlyRole(WHITELIST_ADMIN_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            listed[accounts[i]] = false;
            emit Removed(accounts[i]);
        }
    }

    // ── IComplianceModule ────────────────────────────────────────────────────

    function checkTransfer(address from, address to, uint256 /* amount */ )
        external
        view
        override
        returns (bool allowed, uint8 restrictionCode)
    {
        if (!listed[from]) return (false, 16);
        if (!listed[to]) return (false, 17);
        return (true, 0);
    }

    function moduleName() external pure override returns (string memory) {
        return "WhitelistModule";
    }
}
