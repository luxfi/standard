// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IComplianceModule } from "../interfaces/IComplianceModule.sol";

/**
 * @title JurisdictionModule
 * @notice Restricts transfers based on ISO 3166-1 alpha-2 country/jurisdiction codes.
 *         Blocked jurisdictions are stored as a set; accounts must have a jurisdiction assigned.
 *
 * Restriction codes:
 *   19 = SENDER_JURISDICTION_BLOCKED
 *   20 = RECEIVER_JURISDICTION_BLOCKED
 *   21 = SENDER_JURISDICTION_UNSET
 *   22 = RECEIVER_JURISDICTION_UNSET
 */
contract JurisdictionModule is IComplianceModule, AccessControl {
    bytes32 public constant JURISDICTION_ADMIN_ROLE = keccak256("JURISDICTION_ADMIN_ROLE");

    /// @notice ISO 3166-1 alpha-2 code for each account (e.g., "US", "GB").
    mapping(address => bytes2) public accountJurisdiction;

    /// @notice True if the country code is blocked.
    mapping(bytes2 => bool) public blockedJurisdiction;

    /// @notice Whether accounts without a jurisdiction set are blocked.
    bool public requireJurisdiction;

    event AccountJurisdictionSet(address indexed account, bytes2 countryCode);
    event JurisdictionBlocked(bytes2 indexed countryCode);
    event JurisdictionUnblocked(bytes2 indexed countryCode);
    event RequireJurisdictionSet(bool required);

    error ZeroAddress();

    constructor(address admin, bool _requireJurisdiction) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(JURISDICTION_ADMIN_ROLE, admin);
        requireJurisdiction = _requireJurisdiction;
    }

    // ── Admin functions ──────────────────────────────────────────────────────

    function setAccountJurisdiction(address account, bytes2 countryCode) external onlyRole(JURISDICTION_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        accountJurisdiction[account] = countryCode;
        emit AccountJurisdictionSet(account, countryCode);
    }

    function setAccountJurisdictionBatch(address[] calldata accounts, bytes2 countryCode)
        external
        onlyRole(JURISDICTION_ADMIN_ROLE)
    {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            accountJurisdiction[accounts[i]] = countryCode;
            emit AccountJurisdictionSet(accounts[i], countryCode);
        }
    }

    function blockJurisdiction(bytes2 countryCode) external onlyRole(JURISDICTION_ADMIN_ROLE) {
        blockedJurisdiction[countryCode] = true;
        emit JurisdictionBlocked(countryCode);
    }

    function unblockJurisdiction(bytes2 countryCode) external onlyRole(JURISDICTION_ADMIN_ROLE) {
        blockedJurisdiction[countryCode] = false;
        emit JurisdictionUnblocked(countryCode);
    }

    function setRequireJurisdiction(bool required) external onlyRole(DEFAULT_ADMIN_ROLE) {
        requireJurisdiction = required;
        emit RequireJurisdictionSet(required);
    }

    // ── IComplianceModule ────────────────────────────────────────────────────

    function checkTransfer(
        address from,
        address to,
        uint256 /* amount */
    )
        external
        view
        override
        returns (bool allowed, uint8 restrictionCode)
    {
        bytes2 fromJurisdiction = accountJurisdiction[from];
        bytes2 toJurisdiction = accountJurisdiction[to];

        if (requireJurisdiction) {
            if (fromJurisdiction == bytes2(0)) return (false, 21);
            if (toJurisdiction == bytes2(0)) return (false, 22);
        }

        if (fromJurisdiction != bytes2(0) && blockedJurisdiction[fromJurisdiction]) {
            return (false, 19);
        }
        if (toJurisdiction != bytes2(0) && blockedJurisdiction[toJurisdiction]) {
            return (false, 20);
        }

        return (true, 0);
    }

    function moduleName() external pure override returns (string memory) {
        return "JurisdictionModule";
    }
}
