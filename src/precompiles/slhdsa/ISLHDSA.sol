// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SLH-DSA Signature Verification Precompile Interface
/// @notice FIPS 205 - Stateless Hash-Based Digital Signature Algorithm
/// @dev Precompile contract for verifying SLH-DSA (SPHINCS+) signatures
///      Address: 0x0200000000000000000000000000000000000007
interface ISLHDSA {
    /// @notice Verifies an SLH-DSA signature
    /// @param publicKey The SLH-DSA public key (32, 48, or 64 bytes depending on security level)
    /// @param message The message that was signed
    /// @param signature The SLH-DSA signature (varies by parameter set: 7856-49856 bytes)
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

    /// @notice Gas cost for SLH-DSA verification
    /// @dev Based on ~300μs-600μs verify time
    uint256 internal constant VERIFY_GAS = 15000;

    /// @notice Verifies an SLH-DSA signature with automatic revert on failure
    /// @param publicKey The SLH-DSA public key
    /// @param message The message that was signed
    /// @param signature The SLH-DSA signature
    function verifyOrRevert(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view {
        require(
            ISLHDSA(SLHDSA_PRECOMPILE).verify(publicKey, message, signature),
            "SLHDSALib: signature verification failed"
        );
    }

    /// @notice Estimates gas for SLH-DSA verification
    /// @param messageLength Length of the message to verify
    /// @return estimatedGas The estimated gas cost
    function estimateGas(uint256 messageLength) internal pure returns (uint256 estimatedGas) {
        // Base cost + per-byte cost
        return VERIFY_GAS + (messageLength * 10);
    }

    /// @notice Validates public key size
    /// @param publicKey The public key to validate
    /// @return True if the size is valid
    function isValidPublicKeySize(bytes memory publicKey) internal pure returns (bool) {
        uint256 len = publicKey.length;
        return len == SHA2_128_PUBKEY_SIZE || 
               len == SHA2_192_PUBKEY_SIZE || 
               len == SHA2_256_PUBKEY_SIZE;
    }

    /// @notice Validates signature size
    /// @param signature The signature to validate
    /// @return True if the size is valid for any parameter set
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
    using SLHDSALib for bytes;

    /// @notice Event emitted when an SLH-DSA signature is verified
    event SLHDSASignatureVerified(
        bytes32 indexed messageHash,
        bytes publicKey,
        bool valid
    );

    /// @notice Verifies an SLH-DSA signature
    /// @param publicKey The SLH-DSA public key
    /// @param message The message that was signed
    /// @param signature The SLH-DSA signature
    /// @return valid True if the signature is valid
    function verifySLHDSASignature(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        require(SLHDSALib.isValidPublicKeySize(publicKey), "SLHDSAVerifier: invalid public key size");
        require(SLHDSALib.isValidSignatureSize(signature), "SLHDSAVerifier: invalid signature size");
        
        return ISLHDSA(SLHDSALib.SLHDSA_PRECOMPILE).verify(publicKey, message, signature);
    }

    /// @notice Verifies an SLH-DSA signature and emits an event
    /// @param publicKey The SLH-DSA public key
    /// @param message The message that was signed
    /// @param signature The SLH-DSA signature
    /// @return valid True if the signature is valid
    function verifySLHDSASignatureWithEvent(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal returns (bool valid) {
        valid = verifySLHDSASignature(publicKey, message, signature);
        emit SLHDSASignatureVerified(keccak256(message), publicKey, valid);
        return valid;
    }
}
