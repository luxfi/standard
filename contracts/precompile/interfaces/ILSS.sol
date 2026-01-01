// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title ILSS
 * @dev Interface for the LSS (Linear Secret Sharing) threshold signature precompile
 *
 * LSS is Lux's optimized threshold ECDSA protocol with dynamic resharing capabilities.
 * It communicates with the T-Chain (thresholdvm) for distributed key management.
 *
 * Precompile Address: 0x020000000000000000000000000000000000000E
 *
 * Features:
 * - Dynamic resharing: Add/remove signers without changing public key
 * - Generation tracking: Support key rotation and rollback
 * - T-Chain integration: Full MPC-as-a-service support
 * - Standard ECDSA output: Compatible with ecrecover()
 *
 * Key Sizes:
 * - Public Key: 65 bytes (uncompressed secp256k1)
 * - Signature: 65 bytes (r || s || v)
 *
 * Gas Costs:
 * - Base verification: 75,000 gas
 * - Per signer: 10,000 gas
 * - Reshare verification: 100,000 gas (includes T-Chain state check)
 *
 * T-Chain Integration:
 * - Sessions coordinated by T-Chain thresholdvm
 * - Warp messages for cross-chain key requests
 * - Generation tracking for proactive security
 */
interface ILSS {
    /**
     * @dev Verifies an LSS threshold ECDSA signature
     *
     * @param threshold The minimum number of signers required (t)
     * @param totalSigners The total number of signers (n)
     * @param generation The key generation number (for resharing support)
     * @param publicKey The 65-byte uncompressed secp256k1 aggregated public key
     * @param messageHash The 32-byte message hash
     * @param signature The 65-byte ECDSA signature (r || s || v)
     * @return valid True if the signature is valid for this generation
     *
     * Example usage:
     * ```solidity
     * ILSS lss = ILSS(0x020000000000000000000000000000000000000E);
     * bool isValid = lss.verify(3, 5, 1, publicKey, messageHash, signature);
     * require(isValid, "Invalid LSS signature");
     * ```
     */
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        uint64 generation,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);

    /**
     * @dev Verifies a reshare proof from T-Chain
     *
     * @param oldGeneration The previous generation number
     * @param newGeneration The new generation number
     * @param publicKey The public key (must remain unchanged)
     * @param commitment The cryptographic commitment from reshare protocol
     * @param proof The reshare proof from T-Chain
     * @return valid True if the reshare is valid
     */
    function verifyReshare(
        uint64 oldGeneration,
        uint64 newGeneration,
        bytes calldata publicKey,
        bytes32 commitment,
        bytes calldata proof
    ) external view returns (bool valid);

    /**
     * @dev Gets the current generation for a public key from T-Chain
     *
     * @param publicKey The public key to query
     * @return generation The current generation number (0 if not found)
     */
    function getGeneration(bytes calldata publicKey) external view returns (uint64 generation);
}

/**
 * @title LSSLib
 * @dev Library for LSS operations with T-Chain integration
 */
library LSSLib {
    /// @dev Address of the LSS precompile
    address constant LSS_PRECOMPILE = 0x020000000000000000000000000000000000000E;

    /// @dev Public key size (uncompressed secp256k1)
    uint256 constant PUBLIC_KEY_SIZE = 65;

    /// @dev Signature size
    uint256 constant SIGNATURE_SIZE = 65;

    /// @dev Gas costs
    uint256 constant BASE_GAS = 75_000;
    uint256 constant PER_SIGNER_GAS = 10_000;
    uint256 constant RESHARE_GAS = 100_000;

    error InvalidThreshold();
    error InvalidPublicKey();
    error InvalidSignature();
    error InvalidGeneration();
    error SignatureVerificationFailed();
    error ReshareVerificationFailed();

    /**
     * @dev Verify LSS signature and revert on failure
     */
    function verifyOrRevert(
        uint32 threshold,
        uint32 totalSigners,
        uint64 generation,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        if (threshold == 0 || threshold > totalSigners) revert InvalidThreshold();
        if (publicKey.length != PUBLIC_KEY_SIZE) revert InvalidPublicKey();
        if (signature.length != SIGNATURE_SIZE) revert InvalidSignature();
        if (generation == 0) revert InvalidGeneration();

        bool valid = ILSS(LSS_PRECOMPILE).verify(
            threshold,
            totalSigners,
            generation,
            publicKey,
            messageHash,
            signature
        );

        if (!valid) revert SignatureVerificationFailed();
    }

    /**
     * @dev Estimate gas for LSS verification
     */
    function estimateGas(uint32 totalSigners) internal pure returns (uint256) {
        return BASE_GAS + (uint256(totalSigners) * PER_SIGNER_GAS);
    }

    /**
     * @dev Check if public key format is valid
     */
    function isValidPublicKey(bytes calldata publicKey) internal pure returns (bool) {
        return publicKey.length == PUBLIC_KEY_SIZE && publicKey[0] == 0x04;
    }
}

/**
 * @title LSSVerifier
 * @dev Abstract contract for LSS signature verification with T-Chain
 */
abstract contract LSSVerifier {
    event LSSSignatureVerified(
        uint32 threshold,
        uint32 totalSigners,
        uint64 generation,
        bytes32 indexed messageHash
    );

    event LSSReshareVerified(
        uint64 oldGeneration,
        uint64 newGeneration,
        bytes32 commitment
    );

    /**
     * @dev Verify LSS threshold signature
     */
    function verifyLSSSignature(
        uint32 threshold,
        uint32 totalSigners,
        uint64 generation,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        LSSLib.verifyOrRevert(threshold, totalSigners, generation, publicKey, messageHash, signature);
    }

    /**
     * @dev Verify LSS signature with event
     */
    function verifyLSSSignatureWithEvent(
        uint32 threshold,
        uint32 totalSigners,
        uint64 generation,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal {
        verifyLSSSignature(threshold, totalSigners, generation, publicKey, messageHash, signature);
        emit LSSSignatureVerified(threshold, totalSigners, generation, messageHash);
    }
}
