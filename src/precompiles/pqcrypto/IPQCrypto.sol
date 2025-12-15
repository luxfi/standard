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
 * Note: This precompile uses raw byte encoding for efficiency.
 * Consider using the dedicated IMLDSA and ISLHDSA interfaces for cleaner APIs.
 */
interface IPQCrypto {
    /**
     * @notice ML-DSA security modes
     */
    enum MLDSAMode {
        MLDSA44, // Level 2 security
        MLDSA65, // Level 3 security (recommended)
        MLDSA87  // Level 5 security
    }

    /**
     * @notice ML-KEM security modes
     */
    enum MLKEMMode {
        MLKEM512,  // Level 1 security
        MLKEM768,  // Level 3 security (recommended)
        MLKEM1024  // Level 5 security
    }

    /**
     * @notice SLH-DSA parameter sets
     */
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

    /**
     * @notice Verify an ML-DSA signature
     * @param mode The ML-DSA mode (44, 65, or 87)
     * @param publicKey The public key
     * @param message The message that was signed
     * @param signature The signature to verify
     * @return valid True if the signature is valid
     */
    function mldsaVerify(
        uint8 mode,
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);

    /**
     * @notice Perform ML-KEM encapsulation
     * @param mode The ML-KEM mode (512, 768, or 1024)
     * @param publicKey The recipient's public key
     * @return ciphertext The encapsulated ciphertext
     * @return sharedSecret The shared secret
     */
    function mlkemEncapsulate(uint8 mode, bytes calldata publicKey)
        external
        view
        returns (bytes memory ciphertext, bytes memory sharedSecret);

    /**
     * @notice Perform ML-KEM decapsulation
     * @param mode The ML-KEM mode (512, 768, or 1024)
     * @param privateKey The private key
     * @param ciphertext The ciphertext to decapsulate
     * @return sharedSecret The shared secret
     */
    function mlkemDecapsulate(
        uint8 mode,
        bytes calldata privateKey,
        bytes calldata ciphertext
    ) external view returns (bytes memory sharedSecret);

    /**
     * @notice Verify an SLH-DSA signature
     * @param mode The SLH-DSA mode
     * @param publicKey The public key
     * @param message The message that was signed
     * @param signature The signature to verify
     * @return valid True if the signature is valid
     */
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
 *
 * Note: This uses raw staticcall for efficiency since the precompile
 * uses a custom binary encoding rather than ABI encoding.
 */
library PQCryptoLib {
    /// @dev The address of the PQ Crypto precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000008;

    /// @dev Function selector prefixes (4 bytes)
    bytes4 constant MLDSA_VERIFY_SELECTOR = "mlds";
    bytes4 constant MLKEM_ENCAPSULATE_SELECTOR = "encp";
    bytes4 constant MLKEM_DECAPSULATE_SELECTOR = "decp";
    bytes4 constant SLHDSA_VERIFY_SELECTOR = "slhs";

    /// @dev Gas costs
    uint256 constant MLDSA_VERIFY_GAS = 10000;
    uint256 constant MLKEM_ENCAPSULATE_GAS = 8000;
    uint256 constant MLKEM_DECAPSULATE_GAS = 8000;
    uint256 constant SLHDSA_VERIFY_GAS = 15000;

    /// @dev ML-DSA modes
    uint8 constant MLDSA_44 = 0;
    uint8 constant MLDSA_65 = 1;
    uint8 constant MLDSA_87 = 2;

    /// @dev ML-KEM modes
    uint8 constant MLKEM_512 = 0;
    uint8 constant MLKEM_768 = 1;
    uint8 constant MLKEM_1024 = 2;

    error PQCryptoCallFailed();
    error InvalidSignature();
    error InvalidPublicKey();

    /**
     * @notice Verify an ML-DSA-65 signature (recommended security level)
     * @param publicKey The public key (1952 bytes for ML-DSA-65)
     * @param message The message that was signed
     * @param signature The signature (3309 bytes for ML-DSA-65)
     * @return valid True if valid
     */
    function verifyMLDSA65(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        return verifyMLDSA(MLDSA_65, publicKey, message, signature);
    }

    /**
     * @notice Verify an ML-DSA signature
     * @param mode The ML-DSA mode
     * @param publicKey The public key
     * @param message The message
     * @param signature The signature
     * @return valid True if valid
     */
    function verifyMLDSA(
        uint8 mode,
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        // Encode: [selector(4)] [mode(1)] [pubkey_len(2)] [pubkey] [msg_len(2)] [msg] [sig]
        bytes memory input = abi.encodePacked(
            MLDSA_VERIFY_SELECTOR,
            mode,
            uint16(publicKey.length),
            publicKey,
            uint16(message.length),
            message,
            signature
        );

        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(input);
        if (!success || result.length == 0) return false;
        return result[0] == 0x01;
    }

    /**
     * @notice Verify an SLH-DSA signature
     * @param mode The SLH-DSA mode
     * @param publicKey The public key
     * @param message The message
     * @param signature The signature
     * @return valid True if valid
     */
    function verifySLHDSA(
        uint8 mode,
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view returns (bool valid) {
        bytes memory input = abi.encodePacked(
            SLHDSA_VERIFY_SELECTOR,
            mode,
            uint16(publicKey.length),
            publicKey,
            uint16(message.length),
            message,
            signature
        );

        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(input);
        if (!success || result.length == 0) return false;
        return result[0] == 0x01;
    }

    /**
     * @notice ML-KEM encapsulation (ML-KEM-768 recommended)
     * @param mode The ML-KEM mode
     * @param publicKey The recipient's public key
     * @return ciphertext The ciphertext
     * @return sharedSecret The shared secret
     */
    function encapsulateMLKEM(uint8 mode, bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes memory sharedSecret)
    {
        bytes memory input = abi.encodePacked(MLKEM_ENCAPSULATE_SELECTOR, mode, publicKey);

        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(input);
        if (!success) revert PQCryptoCallFailed();

        // Result contains ciphertext + shared secret (32 bytes)
        uint256 ctLen = result.length - 32;
        ciphertext = new bytes(ctLen);
        sharedSecret = new bytes(32);

        for (uint256 i = 0; i < ctLen; i++) {
            ciphertext[i] = result[i];
        }
        for (uint256 i = 0; i < 32; i++) {
            sharedSecret[i] = result[ctLen + i];
        }
    }

    /**
     * @notice ML-KEM decapsulation
     * @param mode The ML-KEM mode
     * @param privateKey The private key
     * @param ciphertext The ciphertext
     * @return sharedSecret The shared secret
     */
    function decapsulateMLKEM(
        uint8 mode,
        bytes memory privateKey,
        bytes memory ciphertext
    ) internal view returns (bytes memory sharedSecret) {
        bytes memory input = abi.encodePacked(
            MLKEM_DECAPSULATE_SELECTOR,
            mode,
            uint16(privateKey.length),
            privateKey,
            ciphertext
        );

        (bool success, bytes memory result) = PRECOMPILE_ADDRESS.staticcall(input);
        if (!success) revert PQCryptoCallFailed();

        return result;
    }
}

/**
 * @title PQCryptoVerifier
 * @dev Abstract contract for post-quantum signature verification
 */
abstract contract PQCryptoVerifier {
    using PQCryptoLib for *;

    error PQSignatureVerificationFailed();

    /**
     * @notice Verify an ML-DSA-65 signature and revert if invalid
     * @param publicKey The public key
     * @param message The message
     * @param signature The signature
     */
    function _verifyMLDSA65OrRevert(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view {
        if (!PQCryptoLib.verifyMLDSA65(publicKey, message, signature)) {
            revert PQSignatureVerificationFailed();
        }
    }

    /**
     * @notice Verify an SLH-DSA signature and revert if invalid
     * @param mode The SLH-DSA mode
     * @param publicKey The public key
     * @param message The message
     * @param signature The signature
     */
    function _verifySLHDSAOrRevert(
        uint8 mode,
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) internal view {
        if (!PQCryptoLib.verifySLHDSA(mode, publicKey, message, signature)) {
            revert PQSignatureVerificationFailed();
        }
    }
}
