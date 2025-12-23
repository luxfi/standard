// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IPaymasterV1
 * @notice ERC-4337 paymaster for sponsoring gasless transactions in the DAO Protocol
 * @dev This paymaster enables gasless voting and other operations by sponsoring transaction fees
 * for Light Account users. It integrates with function validators to ensure only authorized
 * operations are sponsored.
 *
 * Key features:
 * - Sponsors gas fees for Light Account operations
 * - Per-function validation through external validator contracts
 * - Configurable validation rules for different target contracts and functions
 * - Owner-controlled validator management
 *
 * Workflow:
 * 1. Owner sets validators for specific contract functions
 * 2. Light Account users submit UserOperations through EntryPoint
 * 3. Paymaster validates the operation using the configured validator
 * 4. If valid, paymaster sponsors the gas fees
 *
 * Integration:
 * - Works with ERC-4337 EntryPoint and Light Accounts
 * - Validators implement IFunctionValidator for custom validation logic
 * - Commonly used for gasless voting in StrategyV1 contracts
 */
interface IPaymasterV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to validate an operation without a configured validator */
    error NoValidatorSet(address target, bytes4 selector);

    /** @notice Thrown when the validator rejects the operation */
    error ValidationFailed(address target, bytes4 selector);

    /** @notice Thrown when setting an invalid validator (zero address or wrong interface) */
    error InvalidValidator();

    // --- Events ---

    /**
     * @notice Emitted when a validator is set for a specific function
     * @param target The contract address whose function is being configured
     * @param selector The function selector (4-byte signature)
     * @param validator The address of the validator contract
     */
    event FunctionValidatorSet(
        address target,
        bytes4 selector,
        address validator
    );

    /**
     * @notice Emitted when a validator is removed for a specific function
     * @param target The contract address whose function configuration is being removed
     * @param selector The function selector that no longer has a validator
     */
    event FunctionValidatorRemoved(address target, bytes4 selector);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the paymaster with required dependencies
     * @dev Can only be called once during deployment. Sets up the paymaster for ERC-4337 operations.
     * @param owner_ The address that will have owner privileges (validator management)
     * @param entryPoint_ The ERC-4337 EntryPoint contract address
     * @param lightAccountFactory_ The factory contract for creating Light Accounts
     */
    function initialize(
        address owner_,
        address entryPoint_,
        address lightAccountFactory_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns the validator configured for a specific function
     * @param contractAddress_ The target contract address
     * @param selector_ The function selector to query
     * @return functionValidator The validator address (zero if none set)
     */
    function getFunctionValidator(
        address contractAddress_,
        bytes4 selector_
    ) external view returns (address functionValidator);

    // --- State-Changing Functions ---

    /**
     * @notice Sets a validator for a specific function on a target contract
     * @dev Only callable by owner. Validator must implement IFunctionValidator interface.
     * This configures which operations the paymaster will sponsor gas for.
     * @param contractAddress_ The target contract address
     * @param selector_ The function selector to validate
     * @param validator_ The validator contract that will validate operations
     * @custom:access Restricted to owner
     * @custom:throws InvalidValidator if validator is zero address or doesn't implement IFunctionValidator
     * @custom:emits FunctionValidatorSet
     */
    function setFunctionValidator(
        address contractAddress_,
        bytes4 selector_,
        address validator_
    ) external;

    /**
     * @notice Removes the validator for a specific function
     * @dev Only callable by owner. After removal, the paymaster will not sponsor
     * operations for this function.
     * @param contractAddress_ The target contract address
     * @param selector_ The function selector to remove validation for
     * @custom:access Restricted to owner
     * @custom:emits FunctionValidatorRemoved
     */
    function removeFunctionValidator(
        address contractAddress_,
        bytes4 selector_
    ) external;
}
