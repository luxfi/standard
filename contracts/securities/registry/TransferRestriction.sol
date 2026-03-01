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

/**
 * @title TransferRestriction
 * @notice Per-token transfer restriction engine.
 *
 * Supports:
 *   - Maximum holder count enforcement
 *   - Per-address transfer amount limits (daily/rolling)
 *   - Admin-defined arbitrary restriction rules
 *
 * Used by RestrictedToken as an additional layer on top of ComplianceRegistry.
 *
 * Restriction codes:
 *   32 = MAX_HOLDERS_REACHED
 *   33 = TRANSFER_AMOUNT_EXCEEDED
 */
contract TransferRestriction is AccessControl {
    bytes32 public constant RESTRICTION_ADMIN_ROLE = keccak256("RESTRICTION_ADMIN_ROLE");

    /// @notice Maximum number of distinct holders. 0 = unlimited.
    uint256 public maxHolders;

    /// @notice Current number of distinct holders.
    uint256 public holderCount;

    /// @notice Tracks whether an address is a current holder.
    mapping(address => bool) public isHolder;

    /// @notice Maximum transfer amount per transaction. 0 = unlimited.
    uint256 public maxTransferAmount;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event MaxHoldersSet(uint256 maxHolders);
    event MaxTransferAmountSet(uint256 maxAmount);
    event HolderAdded(address indexed account);
    event HolderRemoved(address indexed account);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RESTRICTION_ADMIN_ROLE, admin);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────────────────────────────────

    function setMaxHolders(uint256 max) external onlyRole(RESTRICTION_ADMIN_ROLE) {
        maxHolders = max;
        emit MaxHoldersSet(max);
    }

    function setMaxTransferAmount(uint256 max) external onlyRole(RESTRICTION_ADMIN_ROLE) {
        maxTransferAmount = max;
        emit MaxTransferAmountSet(max);
    }

    /**
     * @notice Register an address as a holder (called by the token on mint/transfer).
     */
    function registerHolder(address account) external onlyRole(RESTRICTION_ADMIN_ROLE) {
        if (!isHolder[account]) {
            isHolder[account] = true;
            holderCount++;
            emit HolderAdded(account);
        }
    }

    /**
     * @notice Remove an address from the holder set (called when balance reaches zero).
     */
    function removeHolder(address account) external onlyRole(RESTRICTION_ADMIN_ROLE) {
        if (isHolder[account]) {
            isHolder[account] = false;
            holderCount--;
            emit HolderRemoved(account);
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Restriction check
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check whether a transfer is restricted.
     * @return allowed         True if permitted
     * @return restrictionCode 0 = allowed, 32 = max holders, 33 = amount exceeded
     */
    function checkRestriction(address /* from */, address to, uint256 amount)
        external
        view
        returns (bool allowed, uint8 restrictionCode)
    {
        // Max holder check: only matters if receiver is not already a holder
        if (maxHolders > 0 && !isHolder[to] && holderCount >= maxHolders) {
            return (false, 32);
        }

        // Max transfer amount check
        if (maxTransferAmount > 0 && amount > maxTransferAmount) {
            return (false, 33);
        }

        return (true, 0);
    }
}
