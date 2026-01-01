// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IBLS
 * @dev Interface for BLS signature verification precompile
 *
 * BLS (Boneh-Lynn-Shacham) signatures provide efficient aggregation and
 * are used by Warp messaging and Quasar consensus for validator signatures.
 *
 * Precompile Address: 0x0300000000000000000000000000000000000021
 *
 * Features:
 * - Efficient signature aggregation
 * - Constant verification time regardless of signer count
 * - Used by Warp for cross-chain messaging
 * - Used by Quasar for consensus finality
 *
 * Key Sizes:
 * - Public Key: 48 bytes (compressed G1 point on BLS12-381)
 * - Signature: 96 bytes (G2 point on BLS12-381)
 *
 * Gas Costs:
 * - Verify: 5,000 gas
 * - Aggregate: 2,000 gas per signature
 */
interface IBLS {
    /**
     * @dev Verifies a BLS signature
     *
     * @param publicKey The 48-byte compressed BLS public key
     * @param messageHash The 32-byte message hash
     * @param signature The 96-byte BLS signature
     * @return valid True if signature is valid
     */
    function verify(
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title IBLSAggregate
 * @dev Interface for BLS signature aggregation precompile
 *
 * Precompile Address: 0x0300000000000000000000000000000000000022
 */
interface IBLSAggregate {
    /**
     * @dev Aggregates multiple BLS signatures into one
     *
     * @param signatures Array of 96-byte BLS signatures
     * @return aggregatedSignature Single 96-byte aggregated signature
     */
    function aggregate(bytes[] calldata signatures)
        external
        view
        returns (bytes memory aggregatedSignature);
}

/**
 * @title BLSLib
 * @dev Library for BLS signature operations
 */
library BLSLib {
    address constant BLS_VERIFY = 0x0300000000000000000000000000000000000021;
    address constant BLS_AGGREGATE = 0x0300000000000000000000000000000000000022;

    uint256 constant PUBLIC_KEY_SIZE = 48;
    uint256 constant SIGNATURE_SIZE = 96;
    uint256 constant VERIFY_GAS = 5000;
    uint256 constant AGGREGATE_GAS_PER_SIG = 2000;

    error InvalidBLSPublicKey();
    error InvalidBLSSignature();
    error BLSVerificationFailed();

    /**
     * @dev Verify BLS signature
     */
    function verify(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view returns (bool valid) {
        if (publicKey.length != PUBLIC_KEY_SIZE) revert InvalidBLSPublicKey();
        if (signature.length != SIGNATURE_SIZE) revert InvalidBLSSignature();
        return IBLS(BLS_VERIFY).verify(publicKey, messageHash, signature);
    }

    /**
     * @dev Verify BLS signature or revert
     */
    function verifyOrRevert(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        if (!verify(publicKey, messageHash, signature)) {
            revert BLSVerificationFailed();
        }
    }

    /**
     * @dev Aggregate multiple BLS signatures
     */
    function aggregate(bytes[] memory signatures)
        internal
        view
        returns (bytes memory aggregated)
    {
        return IBLSAggregate(BLS_AGGREGATE).aggregate(signatures);
    }

    /**
     * @dev Check if public key format is valid
     */
    function isValidPublicKey(bytes memory publicKey) internal pure returns (bool) {
        return publicKey.length == PUBLIC_KEY_SIZE;
    }

    /**
     * @dev Check if signature format is valid
     */
    function isValidSignature(bytes memory signature) internal pure returns (bool) {
        return signature.length == SIGNATURE_SIZE;
    }

    /**
     * @dev Estimate gas for verification
     */
    function estimateVerifyGas() internal pure returns (uint256) {
        return VERIFY_GAS;
    }

    /**
     * @dev Estimate gas for aggregation
     */
    function estimateAggregateGas(uint256 sigCount) internal pure returns (uint256) {
        return sigCount * AGGREGATE_GAS_PER_SIG;
    }
}

/**
 * @title BLSVerifier
 * @dev Abstract contract for BLS signature verification
 */
abstract contract BLSVerifier {
    event BLSSignatureVerified(bytes32 indexed messageHash, bytes publicKey);

    /**
     * @dev Verify BLS signature
     */
    function _verifyBLS(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        BLSLib.verifyOrRevert(publicKey, messageHash, signature);
    }

    /**
     * @dev Verify BLS signature with event
     */
    function _verifyBLSWithEvent(
        bytes memory publicKey,
        bytes32 messageHash,
        bytes memory signature
    ) internal {
        _verifyBLS(publicKey, messageHash, signature);
        emit BLSSignatureVerified(messageHash, publicKey);
    }

    /**
     * @dev Aggregate BLS signatures
     */
    function _aggregateBLS(bytes[] memory signatures)
        internal
        view
        returns (bytes memory)
    {
        return BLSLib.aggregate(signatures);
    }
}
