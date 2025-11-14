// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IMLDSA
 * @dev Interface for the ML-DSA (FIPS 204) post-quantum signature verification precompile
 * 
 * ML-DSA (Module-Lattice-Based Digital Signature Algorithm) is a quantum-resistant
 * signature scheme based on the Dilithium algorithm and standardized in FIPS 204.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000006
 *
 * This precompile implements ML-DSA-65 (Security Level 3) signature verification.
 *
 * Key Sizes (ML-DSA-65):
 * - Public Key: 1952 bytes
 * - Signature: 3309 bytes
 * - Security Level: NIST Level 3 (equivalent to AES-192)
 *
 * Gas Costs:
 * - Base cost: 100,000 gas
 * - Per-byte cost: 10 gas per message byte
 *
 * Performance:
 * - Verification time: ~108μs on Apple M1
 * - Small message (18 bytes): ~170μs
 * - Large message (10KB): ~218μs
 */
interface IMLDSA {
    /**
     * @dev Verifies an ML-DSA-65 signature
     *
     * @param publicKey The 1952-byte ML-DSA-65 public key
     * @param message The message that was signed (variable length)
     * @param signature The 3309-byte ML-DSA-65 signature
     * @return valid True if the signature is valid, false otherwise
     *
     * Example usage:
     * ```solidity
     * IMLDSA mldsa = IMLDSA(0x0200000000000000000000000000000000000006);
     * bool isValid = mldsa.verify(publicKey, message, signature);
     * require(isValid, "Invalid ML-DSA signature");
     * ```
     *
     * Security Notes:
     * - ML-DSA is quantum-resistant and secure against Shor's algorithm
     * - Use ML-DSA-65 for general-purpose applications (recommended)
     * - For higher security requirements, consider upgrading to ML-DSA-87
     * - For lower latency requirements, consider ML-DSA-44
     *
     * Gas Estimation:
     * - Minimum (empty message): 100,000 gas
     * - Small message (100 bytes): 101,000 gas
     * - Medium message (1KB): 110,240 gas
     * - Large message (10KB): 202,400 gas
     */
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title MLDSALib
 * @dev Library for interacting with the ML-DSA precompile
 *
 * This library provides convenient methods for ML-DSA signature verification
 * with proper error handling and gas estimation.
 */
library MLDSALib {
    /// @dev The address of the ML-DSA precompile
    address constant MLDSA_PRECOMPILE = 0x0200000000000000000000000000000000000006;

    /// @dev ML-DSA-65 public key size
    uint256 constant PUBLIC_KEY_SIZE = 1952;

    /// @dev ML-DSA-65 signature size
    uint256 constant SIGNATURE_SIZE = 3309;

    /// @dev Base gas cost for verification
    uint256 constant BASE_GAS = 100000;

    /// @dev Per-byte gas cost for message
    uint256 constant PER_BYTE_GAS = 10;

    /// @dev Error thrown when public key size is invalid
    error InvalidPublicKeySize(uint256 expected, uint256 actual);

    /// @dev Error thrown when signature size is invalid
    error InvalidSignatureSize(uint256 expected, uint256 actual);

    /// @dev Error thrown when signature verification fails
    error SignatureVerificationFailed();

    /**
     * @dev Verifies an ML-DSA-65 signature and reverts if invalid
     *
     * @param publicKey The 1952-byte ML-DSA-65 public key
     * @param message The message that was signed
     * @param signature The 3309-byte ML-DSA-65 signature
     *
     * Reverts with specific error if:
     * - Public key size is not 1952 bytes
     * - Signature size is not 3309 bytes
     * - Signature verification fails
     */
    function verifyOrRevert(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) internal view {
        if (publicKey.length != PUBLIC_KEY_SIZE) {
            revert InvalidPublicKeySize(PUBLIC_KEY_SIZE, publicKey.length);
        }

        if (signature.length != SIGNATURE_SIZE) {
            revert InvalidSignatureSize(SIGNATURE_SIZE, signature.length);
        }

        bool valid = IMLDSA(MLDSA_PRECOMPILE).verify(publicKey, message, signature);
        if (!valid) {
            revert SignatureVerificationFailed();
        }
    }

    /**
     * @dev Estimates gas required for signature verification
     *
     * @param messageLength Length of the message in bytes
     * @return gasEstimate Estimated gas required
     */
    function estimateGas(uint256 messageLength) internal pure returns (uint256 gasEstimate) {
        return BASE_GAS + (messageLength * PER_BYTE_GAS);
    }

    /**
     * @dev Checks if a public key has valid size
     *
     * @param publicKey The public key to check
     * @return bool True if size is valid (1952 bytes)
     */
    function isValidPublicKeySize(bytes calldata publicKey) internal pure returns (bool) {
        return publicKey.length == PUBLIC_KEY_SIZE;
    }

    /**
     * @dev Checks if a signature has valid size
     *
     * @param signature The signature to check
     * @return bool True if size is valid (3309 bytes)
     */
    function isValidSignatureSize(bytes calldata signature) internal pure returns (bool) {
        return signature.length == SIGNATURE_SIZE;
    }
}

/**
 * @title MLDSAVerifier
 * @dev Abstract contract for contracts that need ML-DSA signature verification
 *
 * Example usage:
 * ```solidity
 * contract MyContract is MLDSAVerifier {
 *     function processSignedData(
 *         bytes calldata publicKey,
 *         bytes calldata data,
 *         bytes calldata signature
 *     ) external {
 *         verifyMLDSASignature(publicKey, data, signature);
 *         // Process data knowing signature is valid
 *     }
 * }
 * ```
 */
abstract contract MLDSAVerifier {
    using MLDSALib for bytes;

    /// @dev Event emitted when a signature is verified
    event SignatureVerified(bytes32 indexed messageHash, address indexed signer);

    /**
     * @dev Verifies an ML-DSA signature and reverts if invalid
     *
     * @param publicKey The ML-DSA-65 public key
     * @param message The message that was signed
     * @param signature The ML-DSA-65 signature
     */
    function verifyMLDSASignature(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) internal view {
        MLDSALib.verifyOrRevert(publicKey, message, signature);
    }

    /**
     * @dev Verifies an ML-DSA signature with event emission
     *
     * @param publicKey The ML-DSA-65 public key
     * @param message The message that was signed
     * @param signature The ML-DSA-65 signature
     * @param signer Address to associate with this verification (for event)
     */
    function verifyMLDSASignatureWithEvent(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature,
        address signer
    ) internal {
        MLDSALib.verifyOrRevert(publicKey, message, signature);
        emit SignatureVerified(keccak256(message), signer);
    }
}
