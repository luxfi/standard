// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import {SecurityToken} from "./SecurityToken.sol";
import {ComplianceRegistry} from "../compliance/ComplianceRegistry.sol";
import {TransferRestriction} from "../registry/TransferRestriction.sol";

/**
 * @title RestrictedToken
 * @notice ERC-1404 compliant token with an external TransferRestriction engine.
 *
 * Extends SecurityToken with a pluggable restriction engine that can enforce
 * custom per-token rules beyond the global ComplianceRegistry.
 */
contract RestrictedToken is SecurityToken {
    TransferRestriction public transferRestriction;

    event TransferRestrictionUpdated(address indexed oldEngine, address indexed newEngine);

    /**
     * @param name_       Token name
     * @param symbol_     Token symbol
     * @param admin       Admin address
     * @param registry    ComplianceRegistry
     * @param restriction TransferRestriction engine
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        ComplianceRegistry registry,
        TransferRestriction restriction
    ) SecurityToken(name_, symbol_, admin, registry) {
        if (address(restriction) == address(0)) revert ZeroAddress();
        transferRestriction = restriction;
    }

    function setTransferRestriction(TransferRestriction restriction) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(restriction) == address(0)) revert ZeroAddress();
        address old = address(transferRestriction);
        transferRestriction = restriction;
        emit TransferRestrictionUpdated(old, address(restriction));
    }

    /**
     * @dev Adds the TransferRestriction engine check on top of SecurityToken._update.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        // TransferRestriction check (skip minting/burning)
        if (from != address(0) && to != address(0)) {
            (bool allowed, uint8 code) = transferRestriction.checkRestriction(from, to, value);
            if (!allowed) revert TransferRestricted(code);
        }
        super._update(from, to, value);
    }
}
