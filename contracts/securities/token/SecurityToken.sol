// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC1404} from "../interfaces/IERC1404.sol";
import {IST20} from "../interfaces/IST20.sol";
import {ComplianceRegistry} from "../compliance/ComplianceRegistry.sol";

/**
 * @title SecurityToken
 * @notice Base regulated ERC-20 security token implementing ERC-1404 and ST-20.
 *
 * Ported from Arca Labs' SecurityToken.sol with modernizations:
 *   - OZ v5 `_update()` hook (catches transfer, transferFrom, mint, burn)
 *   - AccessControl roles instead of Ownable
 *   - Pluggable ComplianceRegistry for modular compliance
 *   - ERC-1404 restriction codes with human-readable messages
 *   - Pausable with role-gated pause/unpause
 *
 * Roles:
 *   DEFAULT_ADMIN_ROLE — full admin, can grant/revoke all roles
 *   MINTER_ROLE        — can mint new tokens
 *   PAUSER_ROLE        — can pause/unpause transfers
 *
 * Restriction codes (from ComplianceRegistry):
 *   0 = SUCCESS
 *   1 = SENDER_NOT_WHITELISTED
 *   2 = RECEIVER_NOT_WHITELISTED
 *   3 = SENDER_BLACKLISTED
 *   4 = RECEIVER_BLACKLISTED
 *   5 = SENDER_LOCKED
 *   6 = JURISDICTION_BLOCKED
 *   7 = ACCREDITATION_REQUIRED
 */
contract SecurityToken is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, IERC1404, IST20 {
    // ──────────────────────────────────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    ComplianceRegistry public complianceRegistry;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event ComplianceRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error TransferRestricted(uint8 restrictionCode);

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @param name_     Token name
     * @param symbol_   Token symbol
     * @param admin     Address receiving DEFAULT_ADMIN_ROLE, MINTER_ROLE, PAUSER_ROLE
     * @param registry  ComplianceRegistry for KYC/AML checks
     */
    constructor(string memory name_, string memory symbol_, address admin, ComplianceRegistry registry)
        ERC20(name_, symbol_)
    {
        if (admin == address(0)) revert ZeroAddress();
        if (address(registry) == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        complianceRegistry = registry;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Update the compliance registry. Ported from Arca's `setRegistry`.
     */
    function setComplianceRegistry(ComplianceRegistry registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(registry) == address(0)) revert ZeroAddress();
        address old = address(complianceRegistry);
        complianceRegistry = registry;
        emit ComplianceRegistryUpdated(old, address(registry));
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // ERC-1404 (ported from Arca SecurityToken)
    // ──────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IERC1404
    function detectTransferRestriction(address from, address to, uint256 value)
        external
        view
        override
        returns (uint8 restrictionCode)
    {
        // Minting (from == 0) and burning (to == 0) bypass compliance
        if (from == address(0) || to == address(0)) return 0;
        (, restrictionCode) = complianceRegistry.canTransfer(from, to, value);
    }

    /// @inheritdoc IERC1404
    function messageForTransferRestriction(uint8 restrictionCode)
        external
        pure
        override
        returns (string memory message)
    {
        if (restrictionCode == 0) return "SUCCESS";
        if (restrictionCode == 1) return "SENDER_NOT_WHITELISTED";
        if (restrictionCode == 2) return "RECEIVER_NOT_WHITELISTED";
        if (restrictionCode == 3) return "SENDER_BLACKLISTED";
        if (restrictionCode == 4) return "RECEIVER_BLACKLISTED";
        if (restrictionCode == 5) return "SENDER_LOCKED";
        if (restrictionCode == 6) return "JURISDICTION_BLOCKED";
        if (restrictionCode == 7) return "ACCREDITATION_REQUIRED";
        return "UNKNOWN_RESTRICTION";
    }

    // ──────────────────────────────────────────────────────────────────────────
    // ST-20 (ported from Arca SecurityToken.verifyTransfer)
    // ──────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IST20
    function verifyTransfer(address from, address to, uint256 value, bytes calldata /* data */ )
        external
        view
        override
        returns (bool allowed)
    {
        if (from == address(0) || to == address(0)) return true;
        (allowed,) = complianceRegistry.canTransfer(from, to, value);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal — OZ v5 _update hook
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @dev Overrides ERC20._update to enforce compliance on every token movement.
     *      Minting (from == 0) and burning (to == 0) bypass compliance checks.
     */
    function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Pausable) {
        // Minting and burning bypass compliance
        if (from != address(0) && to != address(0)) {
            (bool allowed, uint8 code) = complianceRegistry.canTransfer(from, to, value);
            if (!allowed) revert TransferRestricted(code);
        }
        super._update(from, to, value);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // ERC-165
    // ──────────────────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1404).interfaceId || interfaceId == type(IST20).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
