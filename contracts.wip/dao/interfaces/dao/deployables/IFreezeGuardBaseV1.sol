// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IGuard} from "../IGuard.sol";

/**
 * @title IFreezeGuardBaseV1
 * @notice Base interface for freeze guards that prevent transaction execution when a DAO is frozen
 * @dev Freeze guards are Zodiac Guards attached to a child DAO that check freeze status before
 * allowing any transaction execution. This is a critical component of the parent-child DAO
 * security model, preventing a potentially compromised child from executing transactions while
 * the parent DAO investigates or intervenes.
 *
 * Integration with Safe:
 * - Attached as a transaction guard on the child DAO
 * - Called before and after every transaction execution
 * - Blocks all transactions when the associated FreezeVoting contract reports frozen status
 *
 * Parent-child relationship:
 * - Enables parent DAOs to emergency-freeze child DAOs
 * - Works in conjunction with FreezeVoting contracts
 * - Allows parent intervention without giving permanent control
 */
interface IFreezeGuardBaseV1 is IGuard {
    // --- Errors ---

    /** @notice Thrown when attempting to execute a transaction while the DAO is frozen */
    error DAOFrozen();

    // --- View Functions ---

    /**
     * @notice Returns the freezable contract that determines freeze status
     * @dev This contract is queried to check if the DAO is currently frozen
     * @return freezable The address of the contract implementing IFreezable
     */
    function freezable() external view returns (address freezable);
}
