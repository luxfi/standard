// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title ILightAccountValidator
 * @notice Validates Light Account operations for ERC-4337 paymasters
 * @dev This interface provides validation capabilities for Light Accounts, ensuring
 * that UserOperations come from legitimate Light Accounts created by the authorized
 * factory. It extracts and validates the actual transaction data from UserOperations.
 *
 * Key features:
 * - Verifies Light Accounts are created by the authorized factory
 * - Extracts transaction details from UserOperation calldata
 * - Supports multiple Light Account indices per owner
 * - Validates proper encoding of execute() calls
 *
 * Security:
 * - Prevents malicious contracts from impersonating Light Accounts
 * - Ensures UserOperations follow expected Light Account execute() format
 * - Validates Light Account ownership through factory verification
 *
 * Integration:
 * - Used by paymasters (like PaymasterV1) to validate UserOperations
 * - Works with Light Account Factory for address derivation
 * - Supports ERC-4337 UserOperation format
 */
interface ILightAccountValidator {
    // --- Errors ---

    /** @notice Thrown when the sender is not a valid Light Account created by the factory */
    error InvalidLightAccount();

    /** @notice Thrown when UserOperation calldata is too short to contain a valid selector */
    error InvalidUserOpCallDataLength();

    /** @notice Thrown when the outer call is not to Light Account's execute() function */
    error InvalidCallData();

    /** @notice Thrown when the inner calldata is too short to extract a function selector */
    error InvalidInnerCallDataLength();

    // --- View Functions ---

    /**
     * @notice Returns the Light Account Factory address used for validation
     * @dev This factory is used to verify that Light Accounts are legitimate
     * @return lightAccountFactory The authorized Light Account Factory address
     */
    function lightAccountFactory()
        external
        view
        returns (address lightAccountFactory);

    /**
     * @notice Resolves the owner of a potential Light Account or returns the address itself
     * @dev If the address is a valid Light Account created by the factory, returns its owner.
     * Otherwise, returns the input address (useful for handling both EOAs and Light Accounts).
     * @param potentialLightAccount_ The address to check
     * @param lightAccountIndex_ The index used when creating the Light Account
     * @return potentialLightAccountResolvedOwner The Light Account owner or the input address
     */
    function potentialLightAccountResolvedOwner(
        address potentialLightAccount_,
        uint256 lightAccountIndex_
    ) external view returns (address potentialLightAccountResolvedOwner);
}
