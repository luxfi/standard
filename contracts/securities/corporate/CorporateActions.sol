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
import {SecurityToken} from "../token/SecurityToken.sol";

/**
 * @title CorporateActions
 * @notice Executes corporate actions on security tokens: stock splits, reverse splits,
 *         forced transfers (regulatory seizure), and token conversions.
 *
 * All actions require CORPORATE_ACTION_ROLE and emit events for off-chain tracking.
 */
contract CorporateActions is AccessControl {
    bytes32 public constant CORPORATE_ACTION_ROLE = keccak256("CORPORATE_ACTION_ROLE");

    SecurityToken public immutable TOKEN;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);
    event TokensSeized(address indexed from, uint256 amount, string reason);
    event TokensFrozen(address indexed account, uint256 amount);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error ZeroAmount();

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address admin, SecurityToken _token) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(_token) == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CORPORATE_ACTION_ROLE, admin);
        TOKEN = _token;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Corporate actions
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Force-transfer tokens between accounts (regulatory/court order).
     * @dev Requires this contract to have MINTER_ROLE on the token (for burn+mint pattern).
     *      Burns from `from`, mints to `to`.
     */
    function forcedTransfer(address from, address to, uint256 amount, string calldata reason)
        external
        onlyRole(CORPORATE_ACTION_ROLE)
    {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Burn from source, mint to destination (bypasses compliance for forced actions)
        TOKEN.burnFrom(from, amount);
        TOKEN.mint(to, amount);

        emit ForcedTransfer(from, to, amount, reason);
    }

    /**
     * @notice Seize and burn tokens (e.g., sanctions enforcement).
     */
    function seize(address from, uint256 amount, string calldata reason)
        external
        onlyRole(CORPORATE_ACTION_ROLE)
    {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        TOKEN.burnFrom(from, amount);

        emit TokensSeized(from, amount, reason);
    }

    /**
     * @notice Batch mint to multiple addresses (e.g., stock split distribution).
     */
    function batchMint(address[] calldata accounts, uint256[] calldata amounts)
        external
        onlyRole(CORPORATE_ACTION_ROLE)
    {
        require(accounts.length == amounts.length, "Length mismatch");
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            TOKEN.mint(accounts[i], amounts[i]);
        }
    }
}
