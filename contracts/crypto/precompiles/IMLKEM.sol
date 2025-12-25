// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.20;

// ML-KEM Security Levels (NIST):
// - ML-KEM-512:  Level 1 (128-bit security)
// - ML-KEM-768:  Level 3 (192-bit security) - Recommended
// - ML-KEM-1024: Level 5 (256-bit security)
uint8 constant MODE_MLKEM_512 = 0x00;
uint8 constant MODE_MLKEM_768 = 0x01;
uint8 constant MODE_MLKEM_1024 = 0x02;

/**
 * @title IMLKEM
 * @dev Interface for ML-KEM (FIPS 203) key encapsulation precompile
 *
 * ML-KEM (Module-Lattice-based Key Encapsulation Mechanism) provides
 * quantum-resistant key exchange per NIST FIPS 203 standard.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000007
 *
 * See LP-4318 for full specification.
 */
interface IMLKEM {

    /**
     * @dev Encapsulates a shared secret using recipient's public key
     * @param mode Security level (0=512, 1=768, 2=1024)
     * @param publicKey The recipient's ML-KEM public key
     * @return ciphertext The encapsulated ciphertext to send
     * @return sharedSecret The 32-byte shared secret
     */
    function encapsulate(uint8 mode, bytes calldata publicKey)
        external
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret);

    /**
     * @dev Decapsulates to recover the shared secret
     * @param mode Security level (0=512, 1=768, 2=1024)
     * @param privateKey The recipient's ML-KEM private key
     * @param ciphertext The received ciphertext
     * @return sharedSecret The 32-byte shared secret
     */
    function decapsulate(
        uint8 mode,
        bytes calldata privateKey,
        bytes calldata ciphertext
    ) external view returns (bytes32 sharedSecret);
}

/**
 * @title MLKEMLib
 * @dev Library for ML-KEM precompile operations
 */
library MLKEMLib {
    address constant MLKEM_PRECOMPILE = 0x0200000000000000000000000000000000000007;

    // Operation codes
    uint8 constant OP_ENCAPSULATE = 0x01;
    uint8 constant OP_DECAPSULATE = 0x02;

    // Mode codes
    uint8 constant MODE_512 = 0x00;
    uint8 constant MODE_768 = 0x01;
    uint8 constant MODE_1024 = 0x02;

    // ML-KEM-512 sizes (NIST Level 1)
    uint256 constant PUBLIC_KEY_SIZE_512 = 800;
    uint256 constant PRIVATE_KEY_SIZE_512 = 1632;
    uint256 constant CIPHERTEXT_SIZE_512 = 768;

    // ML-KEM-768 sizes (NIST Level 3, recommended)
    uint256 constant PUBLIC_KEY_SIZE_768 = 1184;
    uint256 constant PRIVATE_KEY_SIZE_768 = 2400;
    uint256 constant CIPHERTEXT_SIZE_768 = 1088;

    // ML-KEM-1024 sizes (NIST Level 5)
    uint256 constant PUBLIC_KEY_SIZE_1024 = 1568;
    uint256 constant PRIVATE_KEY_SIZE_1024 = 3168;
    uint256 constant CIPHERTEXT_SIZE_1024 = 1568;

    // Shared secret is always 32 bytes
    uint256 constant SHARED_SECRET_SIZE = 32;

    // Gas costs per mode
    uint256 constant GAS_ENCAPSULATE_512 = 50000;
    uint256 constant GAS_ENCAPSULATE_768 = 75000;
    uint256 constant GAS_ENCAPSULATE_1024 = 100000;
    uint256 constant GAS_DECAPSULATE_512 = 60000;
    uint256 constant GAS_DECAPSULATE_768 = 90000;
    uint256 constant GAS_DECAPSULATE_1024 = 120000;

    error MLKEMCallFailed();
    error InvalidResultLength();
    error InvalidPublicKeySize();
    error InvalidMode();

    /**
     * @dev Encapsulate with ML-KEM-768 (recommended)
     */
    function encapsulate768(bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret)
    {
        return encapsulate(MODE_768, publicKey);
    }

    /**
     * @dev Decapsulate with ML-KEM-768 (recommended)
     */
    function decapsulate768(bytes memory privateKey, bytes memory ciphertext)
        internal
        view
        returns (bytes32 sharedSecret)
    {
        return decapsulate(MODE_768, privateKey, ciphertext);
    }

    /**
     * @dev Encapsulate with specified mode
     * @param mode Security level (0=512, 1=768, 2=1024)
     * @param publicKey The recipient's public key
     * @return ciphertext The encapsulated ciphertext
     * @return sharedSecret The 32-byte shared secret
     */
    function encapsulate(uint8 mode, bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret)
    {
        if (mode > MODE_1024) revert InvalidMode();

        bytes memory input = abi.encodePacked(OP_ENCAPSULATE, mode, publicKey);

        (bool success, bytes memory result) = MLKEM_PRECOMPILE.staticcall(input);
        if (!success) revert MLKEMCallFailed();

        // Result is ciphertext || sharedSecret(32 bytes)
        if (result.length < SHARED_SECRET_SIZE) revert InvalidResultLength();

        uint256 ctLen = result.length - SHARED_SECRET_SIZE;
        ciphertext = new bytes(ctLen);
        for (uint256 i = 0; i < ctLen; i++) {
            ciphertext[i] = result[i];
        }

        assembly {
            sharedSecret := mload(add(add(result, 32), ctLen))
        }
    }

    /**
     * @dev Decapsulate with specified mode
     * @param mode Security level (0=512, 1=768, 2=1024)
     * @param privateKey The recipient's private key
     * @param ciphertext The encapsulated ciphertext
     * @return sharedSecret The 32-byte shared secret
     */
    function decapsulate(uint8 mode, bytes memory privateKey, bytes memory ciphertext)
        internal
        view
        returns (bytes32 sharedSecret)
    {
        if (mode > MODE_1024) revert InvalidMode();

        bytes memory input = abi.encodePacked(OP_DECAPSULATE, mode, privateKey, ciphertext);

        (bool success, bytes memory result) = MLKEM_PRECOMPILE.staticcall(input);
        if (!success) revert MLKEMCallFailed();

        if (result.length != SHARED_SECRET_SIZE) revert InvalidResultLength();

        assembly {
            sharedSecret := mload(add(result, 32))
        }
    }

    /**
     * @dev Get public key size for mode
     */
    function getPublicKeySize(uint8 mode) internal pure returns (uint256) {
        if (mode == MODE_512) return PUBLIC_KEY_SIZE_512;
        if (mode == MODE_768) return PUBLIC_KEY_SIZE_768;
        if (mode == MODE_1024) return PUBLIC_KEY_SIZE_1024;
        return 0;
    }

    /**
     * @dev Get ciphertext size for mode
     */
    function getCiphertextSize(uint8 mode) internal pure returns (uint256) {
        if (mode == MODE_512) return CIPHERTEXT_SIZE_512;
        if (mode == MODE_768) return CIPHERTEXT_SIZE_768;
        if (mode == MODE_1024) return CIPHERTEXT_SIZE_1024;
        return 0;
    }

    /**
     * @dev Get security level from mode
     */
    function getSecurityLevel(uint8 mode) internal pure returns (uint8) {
        if (mode == MODE_512) return 1;  // NIST Level 1
        if (mode == MODE_768) return 3;  // NIST Level 3
        if (mode == MODE_1024) return 5; // NIST Level 5
        return 0;
    }

    /**
     * @dev Estimate gas for encapsulation
     */
    function estimateEncapsulateGas(uint8 mode) internal pure returns (uint256) {
        if (mode == MODE_512) return GAS_ENCAPSULATE_512;
        if (mode == MODE_768) return GAS_ENCAPSULATE_768;
        if (mode == MODE_1024) return GAS_ENCAPSULATE_1024;
        return GAS_ENCAPSULATE_768; // Default
    }

    /**
     * @dev Estimate gas for decapsulation
     */
    function estimateDecapsulateGas(uint8 mode) internal pure returns (uint256) {
        if (mode == MODE_512) return GAS_DECAPSULATE_512;
        if (mode == MODE_768) return GAS_DECAPSULATE_768;
        if (mode == MODE_1024) return GAS_DECAPSULATE_1024;
        return GAS_DECAPSULATE_768; // Default
    }
}

/**
 * @title MLKEMKeyExchange
 * @dev Abstract contract for ML-KEM key exchange
 */
abstract contract MLKEMKeyExchange {
    using MLKEMLib for *;

    event KeyEncapsulated(bytes32 indexed ciphertextHash, uint8 mode);
    event KeyDecapsulated(bytes32 indexed ciphertextHash, uint8 mode);

    /**
     * @dev Encapsulate shared secret with ML-KEM-768 (recommended)
     */
    function _encapsulate768(bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret)
    {
        return MLKEMLib.encapsulate768(publicKey);
    }

    /**
     * @dev Decapsulate shared secret with ML-KEM-768 (recommended)
     */
    function _decapsulate768(bytes memory privateKey, bytes memory ciphertext)
        internal
        view
        returns (bytes32 sharedSecret)
    {
        return MLKEMLib.decapsulate768(privateKey, ciphertext);
    }

    /**
     * @dev Encapsulate shared secret with specified mode
     */
    function _encapsulate(uint8 mode, bytes memory publicKey)
        internal
        view
        returns (bytes memory ciphertext, bytes32 sharedSecret)
    {
        return MLKEMLib.encapsulate(mode, publicKey);
    }

    /**
     * @dev Decapsulate shared secret with specified mode
     */
    function _decapsulate(uint8 mode, bytes memory privateKey, bytes memory ciphertext)
        internal
        view
        returns (bytes32 sharedSecret)
    {
        return MLKEMLib.decapsulate(mode, privateKey, ciphertext);
    }
}
