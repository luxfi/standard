// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {Transaction} from "../Module.sol";

/**
 * @title IModuleFractalV1
 * @notice Execution module enabling parent-child DAO relationships
 * @dev This module is a critical component of hierarchical DAO structures, allowing
 * a parent DAO to execute transactions directly on a child DAO's Safe. It acts as
 * a Zodiac module that bypasses the child's normal governance processes, enabling
 * emergency interventions and administrative control.
 *
 * Key features:
 * - Direct transaction execution by the parent DAO (owner)
 * - No voting or proposal mechanisms required on the child DAO
 * - Works in conjunction with freeze mechanisms for security
 * - Enables hierarchical DAO governance structures
 *
 * Parent-Child DAO Architecture:
 * - Installed on the child DAO's Safe as a module
 * - Owned by the parent DAO
 * - Often paired with FreezeGuard/FreezeVoting for complete control
 * - Allows parent to intervene when child DAO is frozen
 *
 * Use cases:
 * - Emergency interventions when child DAO is compromised
 * - Administrative actions from parent to child
 * - Executing corrective measures after freezing a child DAO
 * - Managing sub-DAOs in a hierarchical structure
 *
 * Integration requirements:
 * - Must be enabled as a module on the child DAO's Safe
 * - Owner must be the parent DAO's Safe address
 * - Typically deployed alongside freeze mechanisms for full control
 */
interface IModuleFractalV1 {
    // --- Errors ---

    /** @notice Thrown when a transaction execution through the Safe fails */
    error TxFailed();

    // --- Initializer Functions ---

    /**
     * @notice Initializes the Fractal module for parent-child DAO control
     * @dev Can only be called once during deployment. This module is installed on the
     * child DAO's Safe, with the parent DAO as the owner. The avatar and target
     * typically point to the child DAO's Safe address.
     * @param owner_ The parent DAO's Safe address that will control this module
     * @param avatar_ The child DAO's Safe address that will execute transactions
     * @param target_ The child DAO's Safe address (usually same as avatar)
     */
    function initialize(
        address owner_,
        address avatar_,
        address target_
    ) external;

    // --- State-Changing Functions ---

    /**
     * @notice Executes a transaction on the child DAO's Safe
     * @dev Only callable by the parent DAO (owner). This function allows the parent DAO
     * to execute any transaction on the child DAO's Safe, bypassing the child's governance.
     * This is particularly useful when the child DAO is frozen via FreezeGuard, preventing
     * the child from executing transactions while the parent intervenes.
     * @param transaction_ The transaction to execute on the child DAO (to, value, data, operation)
     * @custom:access Restricted to parent DAO (owner)
     * @custom:throws TxFailed if the transaction execution on the child DAO's Safe fails
     */
    function execTx(Transaction calldata transaction_) external;
}
