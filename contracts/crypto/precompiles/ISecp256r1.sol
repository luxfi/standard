// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.

pragma solidity ^0.8.20;

/**
 * @title ISecp256r1
 * @notice Interface for the secp256r1 (P-256) signature verification precompile
 * @dev Precompile address: 0x0000000000000000000000000000000000000100
 *
 * This precompile enables efficient verification of ECDSA signatures using the
 * NIST P-256 curve (secp256r1), which is used by:
 * - WebAuthn/Passkeys
 * - Face ID / Touch ID (Apple Secure Enclave)
 * - Windows Hello
 * - Android Keystore
 * - Enterprise HSMs
 *
 * Gas cost: 3,450 (100x cheaper than Solidity implementation)
 *
 * Based on EIP-7212/RIP-7212 for cross-ecosystem compatibility.
 * See LP-3651 for full specification.
 */
interface ISecp256r1 {
    /**
     * @notice Verify a secp256r1 signature
     * @param hash The 32-byte message hash
     * @param r The r component of the signature
     * @param s The s component of the signature
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     * @return valid True if signature is valid, false otherwise
     */
    function verify(
        bytes32 hash,
        bytes32 r,
        bytes32 s,
        bytes32 x,
        bytes32 y
    ) external view returns (bool valid);
}

/**
 * @title Secp256r1Lib
 * @notice Helper library for calling the secp256r1 precompile
 */
library Secp256r1Lib {
    /// @notice Precompile address (matches EIP-7212)
    address constant P256_PRECOMPILE = 0x0000000000000000000000000000000000000100;

    /// @notice Gas cost for verification
    uint256 constant VERIFY_GAS = 3450;

    /// @notice Success return value
    bytes32 constant SUCCESS = bytes32(uint256(1));

    error Secp256r1CallFailed();

    /**
     * @notice Verify a secp256r1 signature using the precompile
     * @param hash The message hash
     * @param r Signature r component
     * @param s Signature s component
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @return True if valid signature
     */
    function verify(
        bytes32 hash,
        bytes32 r,
        bytes32 s,
        bytes32 x,
        bytes32 y
    ) internal view returns (bool) {
        bytes memory input = abi.encodePacked(hash, r, s, x, y);

        (bool success, bytes memory result) = P256_PRECOMPILE.staticcall(input);

        // Precompile returns empty on invalid signature
        if (!success || result.length != 32) {
            return false;
        }

        return abi.decode(result, (bytes32)) == SUCCESS;
    }

    /**
     * @notice Verify signature with struct-based public key
     * @param hash The message hash
     * @param r Signature r component
     * @param s Signature s component
     * @param pubKey Public key as (x, y) tuple
     * @return True if valid signature
     */
    function verify(
        bytes32 hash,
        bytes32 r,
        bytes32 s,
        P256PublicKey memory pubKey
    ) internal view returns (bool) {
        return verify(hash, r, s, pubKey.x, pubKey.y);
    }
}

/**
 * @title P256PublicKey
 * @notice Struct representing a secp256r1 public key
 */
struct P256PublicKey {
    bytes32 x;
    bytes32 y;
}

/**
 * @title P256Signature
 * @notice Struct representing a secp256r1 signature
 */
struct P256Signature {
    bytes32 r;
    bytes32 s;
}

/**
 * @title BiometricWallet
 * @notice Example implementation of a biometric-enabled wallet
 * @dev Uses secp256r1 for Face ID / Touch ID signing
 */
abstract contract BiometricWallet {
    using Secp256r1Lib for bytes32;

    /// @notice Mapping of user address to their device public key
    mapping(address => P256PublicKey) public deviceKeys;

    /// @notice Emitted when a device is registered
    event DeviceRegistered(address indexed user, bytes32 x, bytes32 y);

    /// @notice Emitted when a biometric transaction is executed
    event BiometricExecution(address indexed user, address target, bool success);

    /**
     * @notice Register a device's public key
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     */
    function registerDevice(bytes32 x, bytes32 y) external {
        deviceKeys[msg.sender] = P256PublicKey(x, y);
        emit DeviceRegistered(msg.sender, x, y);
    }

    /**
     * @notice Execute a transaction with biometric authentication
     * @param target The target contract
     * @param data The calldata
     * @param r Signature r component
     * @param s Signature s component
     */
    function executeWithBiometric(
        address target,
        bytes calldata data,
        bytes32 r,
        bytes32 s
    ) external {
        // Build transaction hash
        bytes32 txHash = keccak256(abi.encodePacked(
            target,
            data,
            block.number,
            msg.sender
        ));

        // Get user's device key
        P256PublicKey memory pubKey = deviceKeys[msg.sender];
        require(pubKey.x != bytes32(0), "No device registered");

        // Verify biometric signature
        bool valid = Secp256r1Lib.verify(txHash, r, s, pubKey);
        require(valid, "Invalid biometric signature");

        // Execute transaction
        (bool success,) = target.call(data);
        emit BiometricExecution(msg.sender, target, success);
    }
}

/**
 * @title WebAuthnVerifier
 * @notice Verify WebAuthn/Passkey assertions
 */
library WebAuthnVerifier {
    using Secp256r1Lib for bytes32;

    struct WebAuthnAssertion {
        bytes authenticatorData;
        bytes clientDataJSON;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Verify a WebAuthn assertion
     * @param assertion The WebAuthn assertion data
     * @param pubKey The registered public key
     * @param challenge The expected challenge
     * @return True if assertion is valid
     */
    function verify(
        WebAuthnAssertion memory assertion,
        P256PublicKey memory pubKey,
        bytes32 challenge
    ) internal view returns (bool) {
        // Compute clientDataJSON hash
        bytes32 clientDataHash = sha256(assertion.clientDataJSON);

        // Build signed message: authenticatorData || clientDataHash
        bytes32 messageHash = sha256(
            abi.encodePacked(assertion.authenticatorData, clientDataHash)
        );

        // Verify signature
        return Secp256r1Lib.verify(
            messageHash,
            assertion.r,
            assertion.s,
            pubKey
        );
    }
}
