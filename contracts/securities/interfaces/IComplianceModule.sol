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
 * @title IComplianceModule — Pluggable compliance interface
 * @notice Each compliance module checks a single rule (whitelist, lockup, jurisdiction, etc.).
 *         The ComplianceRegistry iterates over registered modules to produce a combined result.
 */
interface IComplianceModule {
    /**
     * @notice Check whether a transfer is allowed under this module's rules.
     * @param from   Sender address
     * @param to     Receiver address
     * @param amount Token amount
     * @return allowed        True if this module permits the transfer
     * @return restrictionCode Non-zero code explaining the restriction (0 = allowed)
     */
    function checkTransfer(address from, address to, uint256 amount)
        external
        view
        returns (bool allowed, uint8 restrictionCode);

    /**
     * @notice Human-readable name of this compliance module.
     */
    function moduleName() external view returns (string memory);
}
