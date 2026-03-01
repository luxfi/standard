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
 * @title LockupModule
 * @notice Enforces Rule 144 holding period restrictions.
 *         Tokens held by an address cannot be transferred until its lockup expiry has passed.
 *
 * Restriction codes:
 *   18 = SENDER_LOCKUP_ACTIVE
 */
contract LockupModule is IComplianceModule, AccessControl {
    bytes32 public constant LOCKUP_ADMIN_ROLE = keccak256("LOCKUP_ADMIN_ROLE");

    /// @notice Unix timestamp after which the address may transfer. 0 = no lockup.
    mapping(address => uint256) public lockupExpiry;

    event LockupSet(address indexed account, uint256 expiry);

    error ZeroAddress();

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LOCKUP_ADMIN_ROLE, admin);
    }

    function setLockup(address account, uint256 expiry) external onlyRole(LOCKUP_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        lockupExpiry[account] = expiry;
        emit LockupSet(account, expiry);
    }

    function setLockupBatch(address[] calldata accounts, uint256 expiry) external onlyRole(LOCKUP_ADMIN_ROLE) {
        for (uint256 i; i < accounts.length; ++i) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            lockupExpiry[accounts[i]] = expiry;
            emit LockupSet(accounts[i], expiry);
        }
    }

    function isLocked(address account) public view returns (bool) {
        return lockupExpiry[account] > block.timestamp;
    }

    // ── IComplianceModule ────────────────────────────────────────────────────

    function checkTransfer(address from, address /* to */, uint256 /* amount */ )
        external
        view
        override
        returns (bool allowed, uint8 restrictionCode)
    {
        if (isLocked(from)) return (false, 18);
        return (true, 0);
    }

    function moduleName() external pure override returns (string memory) {
        return "LockupModule";
    }
}
