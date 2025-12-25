// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/// @title SLH-DSA Signature Verification Precompile Interface
/// @notice FIPS 205 - Stateless Hash-Based Digital Signature Algorithm (SPHINCS+)
/// @dev Precompile contract for verifying SLH-DSA signatures
///      Address: 0x0200000000000000000000000000000000000007
///
/// SLH-DSA provides post-quantum security using hash-based cryptography.
/// Unlike ML-DSA, it relies solely on the security of hash functions,
/// making it a conservative choice for maximum future-proofing.
///
/// Parameter Sets:
/// - SHA2-128s: 32-byte pubkey, 7,856-byte sig (small)
/// - SHA2-128f: 32-byte pubkey, 17,088-byte sig (fast)
/// - SHA2-192s: 48-byte pubkey, 16,224-byte sig
/// - SHA2-192f: 48-byte pubkey, 35,664-byte sig
/// - SHA2-256s: 64-byte pubkey, 29,792-byte sig
/// - SHA2-256f: 64-byte pubkey, 49,856-byte sig
interface ISLHDSA {
    /// @notice Verifies an SLH-DSA signature
    /// @param publicKey The SLH-DSA public key (32, 48, or 64 bytes depending on security level)
    /// @param message The message that was signed
    /// @param signature The SLH-DSA signature (varies by parameter set: 7,856-49,856 bytes)
    /// @return valid True if the signature is valid, false otherwise
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title SLH-DSA Helper Library
/// @notice Utility functions for working with SLH-DSA precompile
library SLHDSALib {
    /// @notice SLH-DSA precompile address
    address internal constant SLHDSA_PRECOMPILE = 0x0200000000000000000000000000000000000007;

    /// @notice Public key sizes for different security levels
    uint256 internal constant SHA2_128_PUBKEY_SIZE = 32;  // 128-bit security
    uint256 internal constant SHA2_192_PUBKEY_SIZE = 48;  // 192-bit security
    uint256 internal constant SHA2_256_PUBKEY_SIZE = 64;  // 256-bit security

    /// @notice Signature sizes for different parameter sets
    uint256 internal constant SHA2_128s_SIG_SIZE = 7856;   // Small signature
    uint256 internal constant SHA2_128f_SIG_SIZE = 17088;  // Fast signing
    uint256 internal constant SHA2_192s_SIG_SIZE = 16224;
    uint256 internal constant SHA2_192f_SIG_SIZE = 35664;
    uint256 internal constant SHA2_256s_SIG_SIZE = 29792;
    uint256 internal constant SHA2_256f_SIG_SIZE = 49856;

    /// @notice Gas cost for SLH-DSA verification (~300-600μs)
    uint256 internal constant VERIFY_GAS = 15000;

    error InvalidPublicKeySize();
    error InvalidSignatureSize();
    error SignatureVerificationFailed();

    /// @notice Verifies an SLH-DSA signature with automatic revert on failure
    function verifyOrRevert(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view {
        if (!isValidPublicKeySize(publicKey)) revert InvalidPublicKeySize();
        if (!isValidSignatureSize(signature)) revert InvalidSignatureSize();
        
        bool valid = ISLHDSA(SLHDSA_PRECOMPILE).verify(publicKey, message, signature);
        if (!valid) revert SignatureVerificationFailed();
    }

    /// @notice Estimates gas for SLH-DSA verification
    function estimateGas(uint256 messageLength) internal pure returns (uint256) {
        return VERIFY_GAS + (messageLength * 10);
    }

    /// @notice Validates public key size
    function isValidPublicKeySize(bytes memory publicKey) internal pure returns (bool) {
        uint256 len = publicKey.length;
        return len == SHA2_128_PUBKEY_SIZE ||
               len == SHA2_192_PUBKEY_SIZE ||
               len == SHA2_256_PUBKEY_SIZE;
    }

    /// @notice Validates signature size
    function isValidSignatureSize(bytes memory signature) internal pure returns (bool) {
        uint256 len = signature.length;
        return len == SHA2_128s_SIG_SIZE ||
               len == SHA2_128f_SIG_SIZE ||
               len == SHA2_192s_SIG_SIZE ||
               len == SHA2_192f_SIG_SIZE ||
               len == SHA2_256s_SIG_SIZE ||
               len == SHA2_256f_SIG_SIZE;
    }
}

/// @title SLH-DSA Verifier Contract
/// @notice Abstract contract for contracts that need to verify SLH-DSA signatures
abstract contract SLHDSAVerifier {
    event SLHDSASignatureVerified(
        bytes32 indexed messageHash,
        bytes publicKey,
        bool valid
    );

    function verifySLHDSASignature(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        if (!SLHDSALib.isValidPublicKeySize(publicKey)) return false;
        if (!SLHDSALib.isValidSignatureSize(signature)) return false;
        return ISLHDSA(SLHDSALib.SLHDSA_PRECOMPILE).verify(publicKey, message, signature);
    }

    function verifySLHDSASignatureWithEvent(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal returns (bool valid) {
        valid = verifySLHDSASignature(publicKey, message, signature);
        emit SLHDSASignatureVerified(keccak256(message), publicKey, valid);
    }
}
