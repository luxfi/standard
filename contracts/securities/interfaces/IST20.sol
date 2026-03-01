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
 * @title IST20 — Security Token Standard (ST-20)
 * @notice Defines the `verifyTransfer` hook used by security token implementations
 *         to enforce compliance rules before any token movement.
 */
interface IST20 {
    /**
     * @notice Validate a transfer against compliance rules.
     * @param from   Sender address
     * @param to     Receiver address
     * @param value  Amount of tokens
     * @param data   Arbitrary data (e.g., compliance attestation or trade reference)
     * @return allowed True if the transfer should be permitted
     */
    function verifyTransfer(address from, address to, uint256 value, bytes calldata data)
        external
        view
        returns (bool allowed);
}
