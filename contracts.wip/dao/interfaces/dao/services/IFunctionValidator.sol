// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IFunctionValidator
 * @notice Service interface for validating function calls in the context of ERC-4337 operations
 * @dev This interface defines a standard for validators that determine whether a paymaster
 * should sponsor a specific operation. Validators implement custom logic to check if
 * a Light Account owner is authorized to perform a specific function call.
 *
 * Key features:
 * - Stateless validation of operations
 * - Function-specific authorization logic
 * - Integration with paymasters for gas sponsorship decisions
 * - Support for complex validation rules
 *
 * Usage:
 * - Paymasters (like PaymasterV1) call validators to check operations
 * - Each target contract/function pair can have its own validator
 * - Validators can check voting power, roles, balances, or any other criteria
 *
 * Example implementations:
 * - StrategyV1ValidatorV1: Validates voting operations in governance strategies
 * - Custom validators for specific business logic
 *
 * Security:
 * - Validators should be carefully audited as they control gas sponsorship
 * - Must handle edge cases and prevent exploitation
 * - Should validate all relevant parameters
 */
interface IFunctionValidator {
    // --- View Functions ---

    /**
     * @notice Validates whether an operation should be sponsored by the paymaster
     * @dev Called by paymasters to determine if they should pay for the gas of an operation.
     * Implementations should validate all relevant aspects of the operation including
     * the caller's authorization, function parameters, and any protocol-specific rules.
     * @param userOpSender_ The Light Account address that submitted the UserOperation
     * @param lightAccountOwner_ The owner of the Light Account (resolved from factory)
     * @param target_ The contract address being called
     * @param callData_ The complete calldata of the function being called
     * @return isValid True if the operation should be sponsored, false otherwise
     */
    function validateOperation(
        address userOpSender_,
        address lightAccountOwner_,
        address target_,
        bytes calldata callData_
    ) external view returns (bool isValid);
}
