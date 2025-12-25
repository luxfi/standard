// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IMLKEM
 * @dev Interface for ML-KEM (Module-Lattice Key Encapsulation Mechanism) precompile
 *
 * ML-KEM (formerly CRYSTALS-Kyber) is the NIST FIPS 203 standard for
 * post-quantum key encapsulation. It provides quantum-resistant key exchange.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000009
 *
 * Security Levels (NIST):
 * - ML-KEM-512:  Level 1 (equivalent to AES-128)
 * - ML-KEM-768:  Level 3 (equivalent to AES-192)
 * - ML-KEM-1024: Level 5 (equivalent to AES-256)
 *
 * Key Sizes (ML-KEM-768, recommended):
 * - Public Key: 1,184 bytes
 * - Private Key: 2,400 bytes
 * - Ciphertext: 1,088 bytes
 * - Shared Secret: 32 bytes
 *
 * Gas Costs:
 * - Encapsulate: 50,000 gas
 * - Decapsulate: 50,000 gas
 *
 * Use Cases:
 * - Quantum-resistant key exchange
 * - Hybrid TLS with classical + PQ
 * - Secure channel establishment
 * - Ephemeral key agreement
 */
interface IMLKEM {
    /**
     * @dev Encapsulates a shared secret using recipient's public key
     *
     * @param publicKey The recipient's ML-KEM public key
     * @return ciphertext The encapsulated ciphertext to send
     * @return sharedSecret The 32-byte shared secret (keep private)
     */
    function encapsulate(bytes calldata publicKey)
        external
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret);

    /**
     * @dev Decapsulates to recover the shared secret
     *
     * @param privateKey The recipient's ML-KEM private key
     * @param ciphertext The received ciphertext
     * @return sharedSecret The 32-byte shared secret
     */
    function decapsulate(
        bytes calldata privateKey,
        bytes calldata ciphertext
    ) external view returns (bytes32 sharedSecret);
}

/**
 * @title MLKEMLib
 * @dev Library for ML-KEM operations
 */
library MLKEMLib {
    address constant MLKEM_PRECOMPILE = 0x0200000000000000000000000000000000000009;

    // ML-KEM-768 sizes (NIST Level 3, recommended)
    uint256 constant PUBLIC_KEY_SIZE_768 = 1184;
    uint256 constant PRIVATE_KEY_SIZE_768 = 2400;
    uint256 constant CIPHERTEXT_SIZE_768 = 1088;
    uint256 constant SHARED_SECRET_SIZE = 32;

    // ML-KEM-512 sizes (NIST Level 1)
    uint256 constant PUBLIC_KEY_SIZE_512 = 800;
    uint256 constant CIPHERTEXT_SIZE_512 = 768;

    // ML-KEM-1024 sizes (NIST Level 5)
    uint256 constant PUBLIC_KEY_SIZE_1024 = 1568;
    uint256 constant CIPHERTEXT_SIZE_1024 = 1568;

    uint256 constant ENCAPSULATE_GAS = 50000;
    uint256 constant DECAPSULATE_GAS = 50000;

    error InvalidMLKEMPublicKey();
    error InvalidMLKEMCiphertext();
    error MLKEMEncapsulationFailed();
    error MLKEMDecapsulationFailed();

    /**
     * @dev Encapsulate with ML-KEM-768
     */
    function encapsulate(bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret)
    {
        if (publicKey.length != PUBLIC_KEY_SIZE_768 &&
            publicKey.length != PUBLIC_KEY_SIZE_512 &&
            publicKey.length != PUBLIC_KEY_SIZE_1024) {
            revert InvalidMLKEMPublicKey();
        }
        return IMLKEM(MLKEM_PRECOMPILE).encapsulate(publicKey);
    }

    /**
     * @dev Decapsulate with ML-KEM
     */
    function decapsulate(
        bytes memory privateKey,
        bytes memory ciphertext
    ) internal view returns (bytes32 sharedSecret) {
        return IMLKEM(MLKEM_PRECOMPILE).decapsulate(privateKey, ciphertext);
    }

    /**
     * @dev Get security level from public key size
     */
    function getSecurityLevel(bytes memory publicKey) internal pure returns (uint8) {
        if (publicKey.length == PUBLIC_KEY_SIZE_512) return 1;
        if (publicKey.length == PUBLIC_KEY_SIZE_768) return 3;
        if (publicKey.length == PUBLIC_KEY_SIZE_1024) return 5;
        return 0;
    }

    /**
     * @dev Check if public key size is valid
     */
    function isValidPublicKey(bytes memory publicKey) internal pure returns (bool) {
        return publicKey.length == PUBLIC_KEY_SIZE_512 ||
               publicKey.length == PUBLIC_KEY_SIZE_768 ||
               publicKey.length == PUBLIC_KEY_SIZE_1024;
    }

    /**
     * @dev Estimate gas for encapsulation
     */
    function estimateEncapsulateGas() internal pure returns (uint256) {
        return ENCAPSULATE_GAS;
    }

    /**
     * @dev Estimate gas for decapsulation
     */
    function estimateDecapsulateGas() internal pure returns (uint256) {
        return DECAPSULATE_GAS;
    }
}

/**
 * @title MLKEMKeyExchange
 * @dev Abstract contract for ML-KEM key exchange
 */
abstract contract MLKEMKeyExchange {
    event KeyEncapsulated(bytes32 indexed ciphertextHash, uint8 securityLevel);
    event KeyDecapsulated(bytes32 indexed ciphertextHash);

    /**
     * @dev Encapsulate shared secret
     */
    function _encapsulate(bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret)
    {
        return MLKEMLib.encapsulate(publicKey);
    }

    /**
     * @dev Decapsulate shared secret
     */
    function _decapsulate(
        bytes memory privateKey,
        bytes memory ciphertext
    ) internal view returns (bytes32 sharedSecret) {
        return MLKEMLib.decapsulate(privateKey, ciphertext);
    }
}
