// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

/**
 * @title IERC1404 — Simple Restricted Token Standard
 * @notice Extends ERC-20 with transfer restriction detection and human-readable messages.
 * @dev See https://erc1404.org for the full specification.
 *
 * Restriction codes:
 *   0 = SUCCESS (no restriction)
 *   1+ = implementation-defined restriction codes
 */
interface IERC1404 {
    /**
     * @notice Detect whether a transfer would be restricted.
     * @param from   Sending address
     * @param to     Receiving address
     * @param value  Amount of tokens being transferred
     * @return restrictionCode 0 if allowed, otherwise a non-zero restriction code
     */
    function detectTransferRestriction(address from, address to, uint256 value)
        external
        view
        returns (uint8 restrictionCode);

    /**
     * @notice Return a human-readable message for a given restriction code.
     * @param restrictionCode The code returned by `detectTransferRestriction`
     * @return message Human-readable string explaining the restriction
     */
    function messageForTransferRestriction(uint8 restrictionCode)
        external
        view
        returns (string memory message);
}
