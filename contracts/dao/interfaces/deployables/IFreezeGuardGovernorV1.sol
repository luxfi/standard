// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IFreezeGuardBaseV1} from "./IFreezeGuardBaseV1.sol";

/**
 * @title IFreezeGuardGovernorV1
 * @notice Freeze guard implementation for Governor-based child DAOs
 * @dev This guard variant is designed for child DAOs that use Governor governance.
 * It implements the standard guard interface to block transactions when frozen,
 * specifically protecting the Governor module's transaction execution.
 *
 * Deployment context:
 * - Deployed as part of a child DAO's infrastructure
 * - Attached as a guard to the child DAO's Governor module (not the Safe directly)
 * - References a FreezeVoting contract owned by the parent DAO
 *
 * Security model:
 * - Only checks freeze status, doesn't manage the freeze voting itself
 * - Freeze voting logic is handled by the separate FreezeVoting contract
 * - Owner can update the freeze voting contract reference if needed
 */
interface IFreezeGuardGovernorV1 is IFreezeGuardBaseV1 {
    // --- Initializer Functions ---

    /**
     * @notice Initializes the freeze guard with owner and freeze voting contract
     * @param owner_ The address that can update the freeze voting contract reference
     * @param freezeVoting_ The FreezeVoting contract that determines freeze status
     */
    function initialize(address owner_, address freezeVoting_) external;
}
