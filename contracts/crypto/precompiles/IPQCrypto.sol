// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IPQCrypto
 * @dev Interface for the Post-Quantum Cryptography precompile
 *
 * This precompile provides access to NIST-standardized post-quantum cryptographic
 * primitives directly from smart contracts. It supports ML-DSA, ML-KEM, and SLH-DSA.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000008
 *
 * Supported Algorithms:
 *
 * 1. ML-DSA (FIPS 204) - Digital Signatures
 *    - ML-DSA-44: Level 2 security (~128-bit)
 *    - ML-DSA-65: Level 3 security (~192-bit) [Recommended]
 *    - ML-DSA-87: Level 5 security (~256-bit)
 *
 * 2. ML-KEM (FIPS 203) - Key Encapsulation
 *    - ML-KEM-512: Level 1 security
 *    - ML-KEM-768: Level 3 security [Recommended]
 *    - ML-KEM-1024: Level 5 security
 *
 * 3. SLH-DSA (FIPS 205) - Stateless Hash-Based Signatures
 *    - Various parameter sets with different speed/size tradeoffs
 *
 * Gas Costs:
 * - mldsaVerify: 10,000 gas
 * - mlkemEncapsulate: 8,000 gas
 * - mlkemDecapsulate: 8,000 gas
 * - slhdsaVerify: 15,000 gas
 *
 * Note: For cleaner single-algorithm APIs, use IMLDSA.sol or ISLHDSA.sol directly.
 */
interface IPQCrypto {
    /// @notice ML-DSA security modes
    enum MLDSAMode {
        MLDSA44, // Level 2 security
        MLDSA65, // Level 3 security (recommended)
        MLDSA87  // Level 5 security
    }

    /// @notice ML-KEM security modes
    enum MLKEMMode {
        MLKEM512,  // Level 1 security
        MLKEM768,  // Level 3 security (recommended)
        MLKEM1024  // Level 5 security
    }

    /// @notice SLH-DSA parameter sets
    enum SLHDSAMode {
        SHA2_128s,  // Small signatures
        SHA2_128f,  // Fast signing
        SHA2_192s,
        SHA2_192f,
        SHA2_256s,
        SHA2_256f,
        SHAKE_128s,
        SHAKE_128f,
        SHAKE_192s,
        SHAKE_192f,
        SHAKE_256s,
        SHAKE_256f
    }

    /// @notice Verify an ML-DSA signature
    function mldsaVerify(
        uint8 mode,
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);

    /// @notice Perform ML-KEM encapsulation
    function mlkemEncapsulate(uint8 mode, bytes calldata publicKey)
        external
        view
        returns (bytes memory ciphertext, bytes memory sharedSecret);

    /// @notice Perform ML-KEM decapsulation
    function mlkemDecapsulate(
        uint8 mode,
        bytes calldata privateKey,
        bytes calldata ciphertext
    ) external view returns (bytes memory sharedSecret);

    /// @notice Verify an SLH-DSA signature
    function slhdsaVerify(
        uint8 mode,
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/**
 * @title PQCryptoLib
 * @dev Library for interacting with the PQ Crypto precompile
 */
library PQCryptoLib {
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000008;

    /// @dev Mode constants
    uint8 constant MLDSA_44 = 0;
    uint8 constant MLDSA_65 = 1;
    uint8 constant MLDSA_87 = 2;
    uint8 constant MLKEM_512 = 0;
    uint8 constant MLKEM_768 = 1;
    uint8 constant MLKEM_1024 = 2;

    /// @dev Gas costs
    uint256 constant MLDSA_VERIFY_GAS = 10000;
    uint256 constant MLKEM_ENCAPSULATE_GAS = 8000;
    uint256 constant MLKEM_DECAPSULATE_GAS = 8000;
    uint256 constant SLHDSA_VERIFY_GAS = 15000;

    error PQCryptoCallFailed();
    error InvalidSignature();

    /// @notice Verify an ML-DSA-65 signature (recommended security level)
    function verifyMLDSA65(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        return IPQCrypto(PRECOMPILE_ADDRESS).mldsaVerify(
            MLDSA_65,
            publicKey,
            message,
            signature
        );
    }

    /// @notice Verify an ML-DSA signature
    function verifyMLDSA(
        uint8 mode,
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        return IPQCrypto(PRECOMPILE_ADDRESS).mldsaVerify(
            mode,
            publicKey,
            message,
            signature
        );
    }

    /// @notice ML-KEM encapsulation (ML-KEM-768 recommended)
    function encapsulateMLKEM768(bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes memory sharedSecret)
    {
        return IPQCrypto(PRECOMPILE_ADDRESS).mlkemEncapsulate(MLKEM_768, publicKey);
    }

    /// @notice ML-KEM decapsulation
    function decapsulateMLKEM768(
        bytes memory privateKey,
        bytes memory ciphertext
    ) internal view returns (bytes memory sharedSecret) {
        return IPQCrypto(PRECOMPILE_ADDRESS).mlkemDecapsulate(MLKEM_768, privateKey, ciphertext);
    }
}

/**
 * @title PQCryptoVerifier
 * @dev Abstract contract for post-quantum signature verification
 */
abstract contract PQCryptoVerifier {
    error PQSignatureVerificationFailed();

    function _verifyMLDSA65OrRevert(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view {
        if (!PQCryptoLib.verifyMLDSA65(publicKey, message, signature)) {
            revert PQSignatureVerificationFailed();
        }
    }
}
