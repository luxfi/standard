// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IQuasar
 * @dev Interfaces for Quasar consensus precompiles
 *
 * Quasar is Lux's hyper-efficient consensus verification system optimized for
 * on-chain verification of consensus proofs. It provides ultra-low gas costs
 * by leveraging post-quantum finality assumptions.
 *
 * Precompile Addresses:
 * - Verkle Verify:     0x0300000000000000000000000000000000000020
 * - BLS Verify:        0x0300000000000000000000000000000000000021
 * - BLS Aggregate:     0x0300000000000000000000000000000000000022
 * - Ringtail Verify:   0x0300000000000000000000000000000000000023
 * - Hybrid Verify:     0x0300000000000000000000000000000000000024
 * - Compressed Verify: 0x0300000000000000000000000000000000000025
 *
 * Features:
 * - Verkle witness verification with PQ finality assumption
 * - BLS signature verification and aggregation
 * - Ringtail (ML-DSA) post-quantum signature verification
 * - Hybrid BLS+Ringtail signature verification
 * - Ultra-compressed witness verification
 */

/**
 * @title IVerkleVerify
 * @dev Interface for Verkle witness verification with PQ finality assumption
 *
 * Address: 0x0300000000000000000000000000000000000020
 * Gas Cost: 3,000 gas (ultra-low due to PQ finality assumption)
 */
interface IVerkleVerify {
    /**
     * @notice Verify a Verkle witness
     * @param commitment The 32-byte Verkle commitment
     * @param proof The 32-byte Verkle proof
     * @param thresholdMet Whether the PQ threshold was met
     * @return valid True if the witness is valid
     */
    function verify(
        bytes32 commitment,
        bytes32 proof,
        bool thresholdMet
    ) external view returns (bool valid);
}

/**
 * @title IBLSVerify
 * @dev Interface for BLS signature verification
 *
 * Address: 0x0300000000000000000000000000000000000021
 * Gas Cost: 5,000 gas
 */
interface IBLSVerify {
    /**
     * @notice Verify a BLS signature
     * @param publicKey The 48-byte compressed BLS public key
     * @param messageHash The 32-byte message hash
     * @param signature The 96-byte BLS signature
     * @return valid True if the signature is valid
     */
    function verify(
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title IBLSAggregate
 * @dev Interface for BLS signature aggregation
 *
 * Address: 0x0300000000000000000000000000000000000022
 * Gas Cost: 2,000 gas per signature
 */
interface IBLSAggregate {
    /**
     * @notice Aggregate multiple BLS signatures
     * @param signatures Array of 96-byte BLS signatures
     * @return aggregatedSignature The aggregated 96-byte signature
     */
    function aggregate(bytes[] calldata signatures)
        external
        view
        returns (bytes memory aggregatedSignature);
}

/**
 * @title IRingtailVerify
 * @dev Interface for Ringtail (ML-DSA) signature verification
 *
 * Address: 0x0300000000000000000000000000000000000023
 * Gas Cost: 8,000 gas
 *
 * Ringtail is Lux's codename for ML-DSA post-quantum signatures.
 */
interface IRingtailVerify {
    /**
     * @notice Verify a Ringtail (ML-DSA) signature
     * @param mode The ML-DSA mode (0=MLDSA44, 1=MLDSA65, 2=MLDSA87)
     * @param publicKey The public key
     * @param message The message that was signed
     * @param signature The signature
     * @return valid True if the signature is valid
     */
    function verify(
        uint8 mode,
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title IHybridVerify
 * @dev Interface for hybrid BLS+Ringtail signature verification
 *
 * Address: 0x0300000000000000000000000000000000000024
 * Gas Cost: 10,000 gas
 *
 * Hybrid signatures provide both classical and post-quantum security.
 */
interface IHybridVerify {
    /**
     * @notice Verify a hybrid BLS+Ringtail signature
     * @param blsSignature The 96-byte BLS signature
     * @param ringtailSignature The Ringtail (ML-DSA) signature
     * @param messageHash The 32-byte message hash
     * @param blsPublicKey The 48-byte BLS public key
     * @param ringtailPublicKey The Ringtail public key
     * @return valid True if both signatures are valid
     */
    function verify(
        bytes calldata blsSignature,
        bytes calldata ringtailSignature,
        bytes32 messageHash,
        bytes calldata blsPublicKey,
        bytes calldata ringtailPublicKey
    ) external view returns (bool valid);
}

/**
 * @title ICompressedVerify
 * @dev Interface for ultra-compressed witness verification
 *
 * Address: 0x0300000000000000000000000000000000000025
 * Gas Cost: 1,000 gas (ultra-low)
 *
 * Used for verifying compressed consensus witnesses with validator bitfields.
 */
interface ICompressedVerify {
    /**
     * @notice Verify a compressed witness
     * @param commitment The 16-byte compressed commitment
     * @param proof The 16-byte compressed proof
     * @param metadata The 8-byte metadata
     * @param validatorBits The 4-byte validator bitfield
     * @return valid True if the witness is valid (2/3 threshold met)
     */
    function verify(
        bytes16 commitment,
        bytes16 proof,
        bytes8 metadata,
        uint32 validatorBits
    ) external view returns (bool valid);
}

/**
 * @title QuasarLib
 * @dev Library for interacting with Quasar consensus precompiles
 */
library QuasarLib {
    /// @dev Precompile addresses
    address constant VERKLE_VERIFY = 0x0300000000000000000000000000000000000020;
    address constant BLS_VERIFY = 0x0300000000000000000000000000000000000021;
    address constant BLS_AGGREGATE = 0x0300000000000000000000000000000000000022;
    address constant RINGTAIL_VERIFY = 0x0300000000000000000000000000000000000023;
    address constant HYBRID_VERIFY = 0x0300000000000000000000000000000000000024;
    address constant COMPRESSED_VERIFY = 0x0300000000000000000000000000000000000025;

    /// @dev Gas costs
    uint256 constant VERKLE_GAS = 3000;
    uint256 constant BLS_VERIFY_GAS = 5000;
    uint256 constant BLS_AGGREGATE_GAS_PER_SIG = 2000;
    uint256 constant RINGTAIL_GAS = 8000;
    uint256 constant HYBRID_GAS = 10000;
    uint256 constant COMPRESSED_GAS = 1000;

    /// @dev BLS key and signature sizes
    uint256 constant BLS_PUBKEY_SIZE = 48;
    uint256 constant BLS_SIGNATURE_SIZE = 96;

    /// @dev Threshold for compressed verification (2/3 of 32 validators)
    uint256 constant VALIDATOR_THRESHOLD = 22;

    error BLSVerificationFailed();
    error RingtailVerificationFailed();
    error HybridVerificationFailed();
    error VerkleVerificationFailed();
    error CompressedVerificationFailed();
    error InvalidBLSPublicKeySize();
    error InvalidBLSSignatureSize();

    /**
     * @notice Verify a BLS signature
     * @param publicKey The BLS public key
     * @param messageHash The message hash
     * @param signature The BLS signature
     * @return valid True if valid
     */
    function verifyBLS(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view returns (bool valid) {
        if (publicKey.length != BLS_PUBKEY_SIZE) revert InvalidBLSPublicKeySize();
        if (signature.length != BLS_SIGNATURE_SIZE) revert InvalidBLSSignatureSize();

        bytes memory input = abi.encodePacked(publicKey, messageHash, signature);
        (bool success, bytes memory result) = BLS_VERIFY.staticcall(input);
        if (!success || result.length == 0) return false;
        return result[0] == 0x01;
    }

    /**
     * @notice Verify a BLS signature and revert if invalid
     * @param publicKey The BLS public key
     * @param messageHash The message hash
     * @param signature The BLS signature
     */
    function verifyBLSOrRevert(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        if (!verifyBLS(publicKey, messageHash, signature)) {
            revert BLSVerificationFailed();
        }
    }

    /**
     * @notice Aggregate BLS signatures
     * @param signatures Array of BLS signatures
     * @return aggregated The aggregated signature
     */
    function aggregateBLS(bytes[] memory signatures)
        internal
        view
        returns (bytes memory aggregated)
    {
        // Concatenate all signatures
        bytes memory input;
        for (uint256 i = 0; i < signatures.length; i++) {
            input = abi.encodePacked(input, signatures[i]);
        }

        (bool success, bytes memory result) = BLS_AGGREGATE.staticcall(input);
        require(success, "BLS aggregation failed");
        return result;
    }

    /**
     * @notice Count set bits in a validator bitfield
     * @param validatorBits The validator bitfield
     * @return count The number of set bits
     */
    function countValidators(uint32 validatorBits) internal pure returns (uint256 count) {
        while (validatorBits > 0) {
            count += validatorBits & 1;
            validatorBits >>= 1;
        }
    }

    /**
     * @notice Check if validator threshold is met
     * @param validatorBits The validator bitfield
     * @return True if threshold (22/32) is met
     */
    function isThresholdMet(uint32 validatorBits) internal pure returns (bool) {
        return countValidators(validatorBits) >= VALIDATOR_THRESHOLD;
    }

    /**
     * @notice Estimate gas for BLS aggregation
     * @param numSignatures Number of signatures to aggregate
     * @return gas Estimated gas cost
     */
    function estimateAggregateGas(uint256 numSignatures) internal pure returns (uint256 gas) {
        return BLS_AGGREGATE_GAS_PER_SIG * numSignatures;
    }
}

/**
 * @title QuasarVerifier
 * @dev Abstract contract for Quasar consensus verification
 */
abstract contract QuasarVerifier {
    using QuasarLib for *;

    /**
     * @notice Verify a BLS signature
     * @param publicKey The BLS public key
     * @param messageHash The message hash
     * @param signature The BLS signature
     */
    function _verifyBLS(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        QuasarLib.verifyBLSOrRevert(publicKey, messageHash, signature);
    }

    /**
     * @notice Aggregate BLS signatures
     * @param signatures Array of BLS signatures
     * @return aggregated The aggregated signature
     */
    function _aggregateBLS(bytes[] memory signatures)
        internal
        view
        returns (bytes memory aggregated)
    {
        return QuasarLib.aggregateBLS(signatures);
    }

    /**
     * @notice Check if validator threshold is met
     * @param validatorBits The validator bitfield
     * @return True if threshold is met
     */
    function _isThresholdMet(uint32 validatorBits) internal pure returns (bool) {
        return QuasarLib.isThresholdMet(validatorBits);
    }
}
