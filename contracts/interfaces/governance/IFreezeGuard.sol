// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IGuard} from "./IGuard.sol";

/**
 * @title IFreezeGuard
 * @notice Interface for freeze guard that blocks transactions when frozen
 * @dev Attached as a guard to Governor (not directly to Safe)
 *
 * Security model:
 * - Only reads freeze status from FreezeVoting contract
 * - Blocks ALL transactions when frozen (no exceptions)
 * - Validates timelocked transactions against lastFreezeTime
 */
interface IFreezeGuard is IGuard {
    // ======================================================================
    // ERRORS
    // ======================================================================

    error DAOFrozen();
    error TransactionTimelockBeforeFreeze();

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    /// @notice Get the freeze voting contract address
    function freezeVoting() external view returns (address);
}
