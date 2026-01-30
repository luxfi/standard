// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IGuard} from "./IGuard.sol";

/**
 * @title ISanction
 * @notice Interface for sanction guard that blocks transactions when vetoed
 * @dev Attached as a guard to Council (not directly to Safe)
 *
 * Security model:
 * - Only reads veto status from Veto contract
 * - Blocks ALL transactions when vetoed (no exceptions)
 * - Validates timelocked transactions against lastVetoTime
 */
interface ISanction is IGuard {
    // ======================================================================
    // ERRORS
    // ======================================================================

    error DAOVetoed();
    error TransactionTimelockBeforeVeto();

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    /// @notice Get the veto voting contract address
    function veto() external view returns (address);
}
