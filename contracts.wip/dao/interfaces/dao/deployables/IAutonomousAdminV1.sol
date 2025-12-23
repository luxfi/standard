// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IHats} from "../../hats/IHats.sol";

/**
 * @title IAutonomousAdminV1
 * @notice Autonomous administration for Hats Protocol roles with term transitions
 * @dev This contract automates the transition between terms for Hats that use
 * the HatsElectionsEligibility module. It acts as an admin that can be called
 * by anyone to trigger term transitions, removing the need for manual intervention.
 *
 * Key features:
 * - Permissionless term transitions
 * - Automatic hat burning for ineligible wearers
 * - Automatic hat minting to new nominees
 * - Works with HatsElectionsEligibility module
 *
 * Workflow:
 * 1. Anyone calls triggerStartNextTerm when a term expires
 * 2. Contract calls startNextTerm on the elections module
 * 3. Checks current wearer's eligibility and burns if needed
 * 4. Mints hat to the nominated wearer if different
 *
 * Use cases:
 * - Automated role transitions for elected positions
 * - Removing dependency on specific admins
 * - Ensuring timely term transitions
 * - DAOralized role management
 */
interface IAutonomousAdminV1 {
    // --- Errors ---

    /** @notice Thrown when caller is not the current wearer of the hat */
    error NotCurrentWearer();

    // --- Structs ---

    /**
     * @notice Arguments for triggering the start of a new term
     * @param currentWearer Current wearer of the hat (for verification)
     * @param hatsProtocol The Hats Protocol contract
     * @param hatId The ID of the hat to transition
     * @param nominatedWearer The address nominated for the new term
     */
    struct TriggerStartArgs {
        address currentWearer;
        IHats hatsProtocol;
        uint256 hatId;
        address nominatedWearer;
    }

    // --- Constructor & Initializers ---

    /**
     * @notice Initializes the autonomous admin contract
     * @dev Can only be called once during deployment. This is a minimal
     * initialization as the contract is stateless and permissionless.
     */
    function initialize() external;

    // --- State-Changing Functions ---

    /**
     * @notice Triggers the transition to a new term for a hat
     * @dev Can be called by anyone. This permissionless design ensures term
     * transitions happen on time without relying on specific actors.
     * The function:
     * 1. Calls startNextTerm on the hat's election eligibility module
     * 2. Checks and potentially burns the current wearer's hat
     * 3. Mints the hat to the nominated wearer if different
     *
     * @param args_ The arguments containing hat and wearer information
     * @custom:security Validates through the elections module, not access control
     */
    function triggerStartNextTerm(TriggerStartArgs calldata args_) external;
}
