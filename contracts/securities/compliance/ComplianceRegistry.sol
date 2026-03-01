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
 * @title ComplianceRegistry
 * @notice Central registry for KYC/AML/accreditation status and pluggable compliance modules.
 *
 * Ported from Arca Labs' Registry.sol (whitelist + blacklist) with the following additions:
 *   - Role-based access control (COMPLIANCE_ROLE, not Ownable)
 *   - Lockup expiry tracking (Rule 144 holding periods)
 *   - Jurisdiction (ISO 3166-1 alpha-2 country code)
 *   - Accreditation status
 *   - Pluggable compliance module iteration
 *   - Batch operations
 *
 * Restriction codes (shared across the securities module):
 *   0 = SUCCESS
 *   1 = SENDER_NOT_WHITELISTED
 *   2 = RECEIVER_NOT_WHITELISTED
 *   3 = SENDER_BLACKLISTED
 *   4 = RECEIVER_BLACKLISTED
 *   5 = SENDER_LOCKED
 *   6 = JURISDICTION_BLOCKED
 *   7 = ACCREDITATION_REQUIRED
 *   8-15 = reserved for future core codes
 *   16+ = module-specific codes
 */
contract ComplianceRegistry is AccessControl {
    // ──────────────────────────────────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────────────────────────────────

    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isBlacklisted;
    mapping(address => uint256) public lockupExpiry;
    mapping(address => bytes2) public jurisdiction;
    mapping(address => uint8) public accreditationStatus;

    /// @dev Ordered list of pluggable compliance modules.
    IComplianceModule[] private _modules;

    // ──────────────────────────────────────────────────────────────────────────
    // Events (ported from Arca Registry)
    // ──────────────────────────────────────────────────────────────────────────

    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event BlacklistAdded(address indexed account);
    event BlacklistRemoved(address indexed account);
    event LockupSet(address indexed account, uint256 expiry);
    event JurisdictionSet(address indexed account, bytes2 countryCode);
    event AccreditationSet(address indexed account, uint8 status);
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error ModuleAlreadyAdded(address module);
    error ModuleNotFound(address module);

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Whitelist / Blacklist (ported from Arca Registry)
    // ──────────────────────────────────────────────────────────────────────────

    function whitelistAdd(address account) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isWhitelisted[account] = true;
        emit WhitelistAdded(account);
    }

    function whitelistRemove(address account) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isWhitelisted[account] = false;
        emit WhitelistRemoved(account);
    }

    function blacklistAdd(address account) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isBlacklisted[account] = true;
        emit BlacklistAdded(account);
    }

    function blacklistRemove(address account) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isBlacklisted[account] = false;
        emit BlacklistRemoved(account);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Batch operations
    // ──────────────────────────────────────────────────────────────────────────

    function whitelistAddBatch(address[] calldata accounts) external onlyRole(COMPLIANCE_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            isWhitelisted[accounts[i]] = true;
            emit WhitelistAdded(accounts[i]);
        }
    }

    function whitelistRemoveBatch(address[] calldata accounts) external onlyRole(COMPLIANCE_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            isWhitelisted[accounts[i]] = false;
            emit WhitelistRemoved(accounts[i]);
        }
    }

    function blacklistAddBatch(address[] calldata accounts) external onlyRole(COMPLIANCE_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            isBlacklisted[accounts[i]] = true;
            emit BlacklistAdded(accounts[i]);
        }
    }

    function blacklistRemoveBatch(address[] calldata accounts) external onlyRole(COMPLIANCE_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            isBlacklisted[accounts[i]] = false;
            emit BlacklistRemoved(accounts[i]);
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // KYC / Accreditation / Jurisdiction
    // ──────────────────────────────────────────────────────────────────────────

    function setLockup(address account, uint256 expiry) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        lockupExpiry[account] = expiry;
        emit LockupSet(account, expiry);
    }

    function setJurisdiction(address account, bytes2 countryCode) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        jurisdiction[account] = countryCode;
        emit JurisdictionSet(account, countryCode);
    }

    function setAccreditation(address account, uint8 status) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        accreditationStatus[account] = status;
        emit AccreditationSet(account, status);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Approval check (ported from Arca: isApproved = whitelisted && !blacklisted)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Core approval check — mirrors Arca's `Registry.isApproved`.
     */
    function isApproved(address account) public view returns (bool) {
        return isWhitelisted[account] && !isBlacklisted[account];
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Transfer restriction check
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check whether a transfer is permitted, returning a restriction code.
     * @return allowed         True if transfer is permitted
     * @return restrictionCode 0 = SUCCESS, non-zero = reason for restriction
     */
    function canTransfer(address from, address to, uint256 amount)
        external
        view
        returns (bool allowed, uint8 restrictionCode)
    {
        // Core checks (ported from Arca SecurityToken.verifyTransfer)
        if (!isWhitelisted[from]) return (false, 1);
        if (!isWhitelisted[to]) return (false, 2);
        if (isBlacklisted[from]) return (false, 3);
        if (isBlacklisted[to]) return (false, 4);
        if (lockupExpiry[from] > block.timestamp) return (false, 5);

        // Pluggable module checks
        uint256 len = _modules.length;
        for (uint256 i; i < len; ++i) {
            (bool moduleAllowed, uint8 moduleCode) = _modules[i].checkTransfer(from, to, amount);
            if (!moduleAllowed) return (false, moduleCode);
        }

        return (true, 0);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Module management
    // ──────────────────────────────────────────────────────────────────────────

    function addModule(IComplianceModule module) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(module) == address(0)) revert ZeroAddress();
        uint256 len = _modules.length;
        for (uint256 i; i < len; ++i) {
            if (address(_modules[i]) == address(module)) revert ModuleAlreadyAdded(address(module));
        }
        _modules.push(module);
        emit ModuleAdded(address(module));
    }

    function removeModule(IComplianceModule module) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = _modules.length;
        for (uint256 i; i < len; ++i) {
            if (address(_modules[i]) == address(module)) {
                _modules[i] = _modules[len - 1];
                _modules.pop();
                emit ModuleRemoved(address(module));
                return;
            }
        }
        revert ModuleNotFound(address(module));
    }

    function getModules() external view returns (IComplianceModule[] memory) {
        return _modules;
    }

    function moduleCount() external view returns (uint256) {
        return _modules.length;
    }
}
