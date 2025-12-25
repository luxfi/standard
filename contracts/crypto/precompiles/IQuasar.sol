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
 * Precompile Addresses (0x03 prefix for consensus):
 * - Verkle Verify:     0x0300000000000000000000000000000000000020
 * - BLS Verify:        0x0300000000000000000000000000000000000021
 * - BLS Aggregate:     0x0300000000000000000000000000000000000022
 * - Ringtail Verify:   0x0300000000000000000000000000000000000023
 * - Hybrid Verify:     0x0300000000000000000000000000000000000024
 * - Compressed Verify: 0x0300000000000000000000000000000000000025
 */

/// @title IVerkleVerify - Verkle witness verification with PQ finality
/// @dev Address: 0x0300000000000000000000000000000000000020, Gas: 3,000
interface IVerkleVerify {
    function verify(
        bytes32 commitment,
        bytes32 proof,
        bool thresholdMet
    ) external view returns (bool valid);
}

/// @title IBLSVerify - BLS signature verification
/// @dev Address: 0x0300000000000000000000000000000000000021, Gas: 5,000
interface IBLSVerify {
    function verify(
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title IBLSAggregate - BLS signature aggregation
/// @dev Address: 0x0300000000000000000000000000000000000022, Gas: 2,000/sig
interface IBLSAggregate {
    function aggregate(bytes[] calldata signatures)
        external
        view
        returns (bytes memory aggregatedSignature);
}

/// @title IRingtailVerify - Ringtail (ML-DSA) signature verification for consensus
/// @dev Address: 0x0300000000000000000000000000000000000023, Gas: 8,000
interface IRingtailVerify {
    function verify(
        uint8 mode,
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title IHybridVerify - Hybrid BLS+Ringtail signature verification
/// @dev Address: 0x0300000000000000000000000000000000000024, Gas: 10,000
interface IHybridVerify {
    function verify(
        bytes calldata blsSignature,
        bytes calldata ringtailSignature,
        bytes32 messageHash,
        bytes calldata blsPublicKey,
        bytes calldata ringtailPublicKey
    ) external view returns (bool valid);
}

/// @title ICompressedVerify - Ultra-compressed witness verification
/// @dev Address: 0x0300000000000000000000000000000000000025, Gas: 1,000
interface ICompressedVerify {
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
    address constant VERKLE_VERIFY = 0x0300000000000000000000000000000000000020;
    address constant BLS_VERIFY = 0x0300000000000000000000000000000000000021;
    address constant BLS_AGGREGATE = 0x0300000000000000000000000000000000000022;
    address constant RINGTAIL_VERIFY = 0x0300000000000000000000000000000000000023;
    address constant HYBRID_VERIFY = 0x0300000000000000000000000000000000000024;
    address constant COMPRESSED_VERIFY = 0x0300000000000000000000000000000000000025;

    uint256 constant VERKLE_GAS = 3000;
    uint256 constant BLS_VERIFY_GAS = 5000;
    uint256 constant BLS_AGGREGATE_GAS_PER_SIG = 2000;
    uint256 constant RINGTAIL_GAS = 8000;
    uint256 constant HYBRID_GAS = 10000;
    uint256 constant COMPRESSED_GAS = 1000;

    uint256 constant BLS_PUBKEY_SIZE = 48;
    uint256 constant BLS_SIGNATURE_SIZE = 96;
    uint256 constant VALIDATOR_THRESHOLD = 22; // 2/3 of 32 validators

    error BLSVerificationFailed();
    error RingtailVerificationFailed();
    error HybridVerificationFailed();
    error InvalidBLSPublicKeySize();
    error InvalidBLSSignatureSize();

    function verifyBLS(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view returns (bool valid) {
        if (publicKey.length != BLS_PUBKEY_SIZE) revert InvalidBLSPublicKeySize();
        if (signature.length != BLS_SIGNATURE_SIZE) revert InvalidBLSSignatureSize();
        return IBLSVerify(BLS_VERIFY).verify(publicKey, messageHash, signature);
    }

    function verifyBLSOrRevert(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        if (!verifyBLS(publicKey, messageHash, signature)) {
            revert BLSVerificationFailed();
        }
    }

    function aggregateBLS(bytes[] memory signatures)
        internal
        view
        returns (bytes memory aggregated)
    {
        return IBLSAggregate(BLS_AGGREGATE).aggregate(signatures);
    }

    function countValidators(uint32 validatorBits) internal pure returns (uint256 count) {
        while (validatorBits > 0) {
            count += validatorBits & 1;
            validatorBits >>= 1;
        }
    }

    function isThresholdMet(uint32 validatorBits) internal pure returns (bool) {
        return countValidators(validatorBits) >= VALIDATOR_THRESHOLD;
    }
}

/**
 * @title QuasarVerifier
 * @dev Abstract contract for Quasar consensus verification
 */
abstract contract QuasarVerifier {
    function _verifyBLS(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        QuasarLib.verifyBLSOrRevert(publicKey, messageHash, signature);
    }

    function _aggregateBLS(bytes[] memory signatures)
        internal
        view
        returns (bytes memory aggregated)
    {
        return QuasarLib.aggregateBLS(signatures);
    }

    function _isThresholdMet(uint32 validatorBits) internal pure returns (bool) {
        return QuasarLib.isThresholdMet(validatorBits);
    }
}
