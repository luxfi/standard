// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFROST
 * @dev Interface for FROST threshold signature verification precompile
 *
 * FROST (Flexible Round-Optimized Schnorr Threshold) is a threshold signature
 * scheme based on Schnorr signatures. It enables t-of-n signing where any t
 * parties can collaboratively produce a signature that appears to be from a
 * single signer.
 *
 * Features:
 * - Efficient Schnorr-based threshold signatures
 * - Compatible with Ed25519 and secp256k1 Schnorr
 * - Used for Bitcoin Taproot multisig
 * - Lower gas cost than ECDSA threshold (CGGMP21)
 *
 * Address: 0x020000000000000000000000000000000000000C
 */
interface IFROST {
    /**
     * @notice Verify a FROST threshold signature
     * @param threshold The minimum number of signers required (t)
     * @param totalSigners The total number of parties (n)
     * @param publicKey The aggregated public key (32 bytes)
     * @param messageHash The hash of the message (32 bytes)
     * @param signature The Schnorr signature (64 bytes: R || s)
     * @return valid True if the signature is valid
     */
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title FROSTLib
 * @dev Library for FROST threshold signature operations
 */
library FROSTLib {
    /// @dev Address of the FROST precompile
    address constant FROST_PRECOMPILE = 0x020000000000000000000000000000000000000c;

    /// @dev Gas cost constants
    uint256 constant BASE_GAS = 50_000;
    uint256 constant PER_SIGNER_GAS = 5_000;

    error InvalidThreshold();
    error InvalidSignature();
    error SignatureVerificationFailed();

    /**
     * @notice Verify FROST signature and revert on failure
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @param publicKey Aggregated public key
     * @param messageHash Message hash
     * @param signature Schnorr signature
     */
    function verifyOrRevert(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        if (threshold == 0 || threshold > totalSigners) {
            revert InvalidThreshold();
        }
        if (signature.length != 64) {
            revert InvalidSignature();
        }

        bytes memory input = abi.encodePacked(
            threshold,
            totalSigners,
            publicKey,
            messageHash,
            signature
        );

        (bool success, bytes memory result) = FROST_PRECOMPILE.staticcall(input);
        require(success, "FROST precompile call failed");

        bool valid = abi.decode(result, (bool));
        if (!valid) {
            revert SignatureVerificationFailed();
        }
    }

    /**
     * @notice Estimate gas for FROST verification
     * @param totalSigners Total number of parties
     * @return gas Estimated gas cost
     */
    function estimateGas(uint32 totalSigners) internal pure returns (uint256 gas) {
        return BASE_GAS + (uint256(totalSigners) * PER_SIGNER_GAS);
    }

    /**
     * @notice Check if threshold parameters are valid
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @return valid True if parameters are valid
     */
    function isValidThreshold(uint32 threshold, uint32 totalSigners) internal pure returns (bool valid) {
        return threshold > 0 && threshold <= totalSigners;
    }
}

/**
 * @title FROSTVerifier
 * @dev Abstract contract for FROST signature verification
 */
abstract contract FROSTVerifier {
    using FROSTLib for *;

    event FROSTSignatureVerified(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 indexed publicKey,
        bytes32 indexed messageHash
    );

    /**
     * @notice Verify FROST threshold signature
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @param publicKey Aggregated public key
     * @param messageHash Message hash
     * @param signature Schnorr signature
     */
    function verifyFROSTSignature(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view {
        FROSTLib.verifyOrRevert(
            threshold,
            totalSigners,
            publicKey,
            messageHash,
            signature
        );
    }

    /**
     * @notice Verify FROST signature with event emission
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @param publicKey Aggregated public key
     * @param messageHash Message hash
     * @param signature Schnorr signature
     */
    function verifyFROSTSignatureWithEvent(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal {
        verifyFROSTSignature(threshold, totalSigners, publicKey, messageHash, signature);
        emit FROSTSignatureVerified(threshold, totalSigners, publicKey, messageHash);
    }
}

/**
 * @title ExampleFROSTContract
 * @dev Example contract using FROST threshold signatures
 */
contract ExampleFROSTContract is FROSTVerifier {
    struct ThresholdConfig {
        uint32 threshold;
        uint32 totalSigners;
        bytes32 publicKey;
    }

    mapping(bytes32 => ThresholdConfig) public configs;

    event ConfigRegistered(bytes32 indexed configId, uint32 threshold, uint32 totalSigners);
    event MessageProcessed(bytes32 indexed configId, bytes32 messageHash);

    /**
     * @notice Register a threshold configuration
     * @param configId Unique identifier for the configuration
     * @param threshold Minimum signers required
     * @param totalSigners Total number of parties
     * @param publicKey Aggregated public key
     */
    function registerConfig(
        bytes32 configId,
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey
    ) external {
        require(FROSTLib.isValidThreshold(threshold, totalSigners), "Invalid threshold");

        configs[configId] = ThresholdConfig({
            threshold: threshold,
            totalSigners: totalSigners,
            publicKey: publicKey
        });

        emit ConfigRegistered(configId, threshold, totalSigners);
    }

    /**
     * @notice Process a signed message
     * @param configId Configuration to use
     * @param messageHash Message hash
     * @param signature FROST threshold signature
     */
    function processSignedMessage(
        bytes32 configId,
        bytes32 messageHash,
        bytes calldata signature
    ) external {
        ThresholdConfig memory config = configs[configId];
        require(config.threshold > 0, "Config not found");

        verifyFROSTSignatureWithEvent(
            config.threshold,
            config.totalSigners,
            config.publicKey,
            messageHash,
            signature
        );

        emit MessageProcessed(configId, messageHash);
    }
}
