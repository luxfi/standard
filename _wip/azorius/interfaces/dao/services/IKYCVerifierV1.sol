// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IKYCVerifierV1
 * @notice Service interface for Know Your Customer (KYC) verification
 * @dev This interface provides a standard way to verify if an address has completed
 * KYC requirements. It's designed as a service contract that can be deployed once
 * per chain and referenced by multiple contracts that need KYC verification.
 *
 * Key features:
 * - verify function that reverts if the signature is invalid or expired
 * - checkVerify view function that returns a boolean indicating if a signature is valid
 *
 * Usage:
 * - CountersignV1 and PublicSaleV1 use this to verify signers before accepting signatures
 *
 * Security:
 * - Verification logic is critical for compliance
 */
interface IKYCVerifierV1 {
    // --- Errors ---

    /** @notice Thrown when the signature has expired */
    error SignatureExpired();

    /** @notice Thrown when the signature is invalid */
    error InvalidSignature();

    // --- Events ---

    /**
     * @notice Emitted when a signature is verified
     * @param operator The address of the operator that is verifying KYC status
     * @param account The address to verify KYC status for
     * @param signatureExpiration The expiration timestamp of the signature
     * @param nonce The nonce used for the signature
     */
    event SignatureVerified(
        address indexed operator,
        address indexed account,
        uint48 signatureExpiration,
        uint256 nonce
    );

    /**
     * @notice Emitted when the verifier address is updated
     * @param verifier The address of the verifier
     */
    event VerifierUpdated(address indexed verifier);

    // --- View Functions ---

    /**
     * @notice Returns the address of the verifier
     * @dev The verifier is the address that is authorized to sign KYC attestations
     * @return verifierAddress The address of the verifier
     */
    function verifier() external view returns (address verifierAddress);

    /**
     * @notice Returns the nonce for an account
     * @param account_ The address to get the nonce for
     * @return nonce The nonce for the account
     */
    function nonce(address account_) external view returns (uint256 nonce);

    /**
     * @notice Checks if a signature is valid
     * @param operator_ The address of the operator that is verifying KYC status
     * @param account_ The address to verify KYC status for
     * @param signatureExpiration_ The expiration timestamp of the signature
     * @param signature_ The verifier signature attesting to KYC status
     * @return isValid Whether the signature is valid
     */
    function checkVerify(
        address operator_,
        address account_,
        uint48 signatureExpiration_,
        bytes calldata signature_
    ) external view returns (bool);

    // --- State-Changing Functions ---

    /**
     * @notice Verifies if an address is KYC verified
     * @dev Reverts if the signature is invalid or expired.
     * If signature is valid, the account's nonce is incremented.
     * @param account_ The address to verify KYC status for
     * @param signatureExpiration_ The expiration timestamp of the signature
     * @param signature_ The verifier signature attesting to KYC status
     */
    function verify(
        address account_,
        uint48 signatureExpiration_,
        bytes calldata signature_
    ) external;

    /**
     * @notice Updates the verifier address
     * @param verifier_ The address of the new verifier
     */
    function updateVerifier(address verifier_) external;
}
