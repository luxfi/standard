// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

import "../IAllowList.sol";

/**
 * @title ITxAllowList
 * @dev Interface for the Transaction Allow List precompile
 *
 * This precompile restricts which addresses can submit transactions on the network.
 * Only addresses with Enabled, Admin, or Manager roles can send transactions.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000002
 *
 * Use Cases:
 * - Permissioned chains where only approved addresses can transact
 * - Enterprise networks with controlled transaction access
 * - Testnets with restricted access
 *
 * Roles:
 * - None (0): Cannot submit transactions
 * - Enabled (1): Can submit transactions
 * - Admin (2): Can submit transactions and modify roles
 * - Manager (3): Can submit transactions and modify non-admin roles
 *
 * Gas Costs:
 * - readAllowList: 2,600 gas
 * - setAdmin/setEnabled/setManager/setNone: 20,000 gas
 *
 * Note: Unlike DeployerAllowList, this affects ALL transactions, not just contract deployment.
 */
interface ITxAllowList is IAllowList {
    // Inherits all functions from IAllowList:
    // - readAllowList(address addr) -> uint256
    // - setAdmin(address addr)
    // - setEnabled(address addr)
    // - setManager(address addr)
    // - setNone(address addr)
}

/**
 * @title TxAllowListLib
 * @dev Library for interacting with the Transaction Allow List precompile
 */
library TxAllowListLib {
    /// @dev The address of the Transaction Allow List precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000002;

    error NotTxEnabled();

    /**
     * @notice Check if an address can submit transactions
     * @param addr The address to check
     * @return True if the address can submit transactions
     */
    function canTransact(address addr) internal view returns (bool) {
        return AllowListLib.isEnabled(PRECOMPILE_ADDRESS, addr);
    }

    /**
     * @notice Require caller to be able to submit transactions
     */
    function requireCanTransact() internal view {
        if (!canTransact(msg.sender)) {
            revert NotTxEnabled();
        }
    }

    /**
     * @notice Get the role of an address
     * @param addr The address to check
     * @return role The role (0=None, 1=Enabled, 2=Admin, 3=Manager)
     */
    function getRole(address addr) internal view returns (uint256 role) {
        return ITxAllowList(PRECOMPILE_ADDRESS).readAllowList(addr);
    }

    /**
     * @notice Set an address as admin
     * @param addr The address to set as admin
     */
    function setAdmin(address addr) internal {
        ITxAllowList(PRECOMPILE_ADDRESS).setAdmin(addr);
    }

    /**
     * @notice Enable an address to submit transactions
     * @param addr The address to enable
     */
    function setEnabled(address addr) internal {
        ITxAllowList(PRECOMPILE_ADDRESS).setEnabled(addr);
    }

    /**
     * @notice Disable an address from submitting transactions
     * @param addr The address to disable
     */
    function setNone(address addr) internal {
        ITxAllowList(PRECOMPILE_ADDRESS).setNone(addr);
    }
}
