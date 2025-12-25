// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {IERC1271, ILegacyERC1271} from "./interfaces/IERC1271.sol";

/// @title ICGGMP21
/// @dev Interface for the CGGMP21 threshold ECDSA precompile at 0x020000000000000000000000000000000000000D
interface ICGGMP21 {
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title Safe CGGMP21 Signer
/// @notice Safe smart account owner that can verify CGGMP21 threshold ECDSA signatures.
/// @dev This contract enables t-of-n threshold ECDSA signature verification for Safe multisigs
/// using the CGGMP21 protocol with identifiable aborts.
///
/// CGGMP21 is a modern threshold ECDSA protocol that provides:
/// - Identifiable aborts (malicious parties can be detected)
/// - Key refresh without changing public key
/// - Compatible with standard ECDSA verification (Ethereum, Bitcoin, etc.)
///
/// Key Sizes:
/// - Public Key: 65 bytes (uncompressed secp256k1)
/// - Signature: 65 bytes (r || s || v)
///
/// Usage:
/// 1. Run distributed key generation with threshold party using CGGMP21 protocol
/// 2. Deploy SafeCGGMP21Signer with aggregated public key and threshold params
/// 3. Add the deployed contract address as a Safe owner
/// 4. Threshold parties sign Safe transactions collaboratively
contract SafeCGGMP21Signer is IERC1271, ILegacyERC1271 {
    /// @dev CGGMP21 precompile address
    address constant CGGMP21_PRECOMPILE = 0x020000000000000000000000000000000000000D;

    /// @dev Uncompressed secp256k1 public key size
    uint256 constant PUBLIC_KEY_SIZE = 65;

    /// @dev ECDSA signature size (r || s || v)
    uint256 constant SIGNATURE_SIZE = 65;

    /// @notice The signing threshold (t)
    uint32 public immutable threshold;

    /// @notice The total number of signers (n)
    uint32 public immutable totalSigners;

    /// @notice The aggregated public key (65 bytes uncompressed secp256k1)
    bytes private _PUBLIC_KEY;

    /// @notice The derived signer address from the public key
    address private immutable _SIGNER;

    /// @notice Invalid threshold (must be > 0 and <= totalSigners)
    error InvalidThreshold();

    /// @notice Invalid public key size (must be 65 bytes for uncompressed secp256k1)
    error InvalidPublicKeySize();

    /// @notice Invalid public key format (must start with 0x04 for uncompressed)
    error InvalidPublicKeyFormat();

    /// @param _threshold The minimum number of signers required (t)
    /// @param _totalSigners The total number of signers (n)
    /// @param publicKey The 65-byte uncompressed secp256k1 aggregated public key
    constructor(uint32 _threshold, uint32 _totalSigners, bytes memory publicKey) {
        if (_threshold == 0 || _threshold > _totalSigners) {
            revert InvalidThreshold();
        }
        if (publicKey.length != PUBLIC_KEY_SIZE) {
            revert InvalidPublicKeySize();
        }
        if (publicKey[0] != 0x04) {
            revert InvalidPublicKeyFormat();
        }

        threshold = _threshold;
        totalSigners = _totalSigners;
        _PUBLIC_KEY = publicKey;

        // Derive Ethereum address from uncompressed public key (skip 0x04 prefix)
        bytes memory pubKeyNoPrefix = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            pubKeyNoPrefix[i] = publicKey[i + 1];
        }
        _SIGNER = address(uint160(uint256(keccak256(pubKeyNoPrefix))));
    }

    /// @notice Returns the aggregated public key
    function publicKey() external view returns (bytes memory) {
        return _PUBLIC_KEY;
    }

    /// @notice Returns the derived signer address
    function signer() external view returns (address) {
        return _SIGNER;
    }

    /// @notice Checks if the given signature is valid for the given message hash.
    /// @param messageHash The keccak256 hash of the message to be verified.
    /// @param signature The 65-byte ECDSA signature (r || s || v).
    /// @return ok Whether or not the signature is valid.
    function _isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bool ok) {
        // Validate signature size
        if (signature.length != SIGNATURE_SIZE) {
            return false;
        }

        // Call the CGGMP21 precompile to verify the threshold signature
        return ICGGMP21(CGGMP21_PRECOMPILE).verify(
            threshold,
            totalSigners,
            _PUBLIC_KEY,
            messageHash,
            signature
        );
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 message, bytes calldata signature) public view returns (bytes4 magicValue) {
        if (_isValidSignature(message, signature)) {
            magicValue = IERC1271.isValidSignature.selector;
        }
    }

    /// @inheritdoc ILegacyERC1271
    function isValidSignature(bytes memory message, bytes calldata signature) public view returns (bytes4 magicValue) {
        if (_isValidSignature(keccak256(message), signature)) {
            magicValue = ILegacyERC1271.isValidSignature.selector;
        }
    }
}

/// @title Safe CGGMP21 Co-Signer
/// @notice Safe transaction guard requiring an additional CGGMP21 threshold signature.
/// @dev Use this to add institutional-grade t-of-n threshold ECDSA co-signing to a Safe.
contract SafeCGGMP21CoSigner is IERC1271 {
    /// @dev CGGMP21 precompile address
    address constant CGGMP21_PRECOMPILE = 0x020000000000000000000000000000000000000D;

    /// @dev Public key and signature sizes
    uint256 constant PUBLIC_KEY_SIZE = 65;
    uint256 constant SIGNATURE_SIZE = 65;

    /// @notice The Safe this co-signer is attached to
    address public immutable safe;

    /// @notice The signing threshold
    uint32 public immutable threshold;

    /// @notice The total number of signers
    uint32 public immutable totalSigners;

    /// @notice The aggregated public key
    bytes private _PUBLIC_KEY;

    /// @notice Emitted when a co-signature is verified
    event CoSignatureVerified(bytes32 indexed safeTxHash, uint32 threshold, uint32 totalSigners);

    /// @notice Only the Safe can call this function
    error OnlySafe();

    /// @notice Invalid configuration
    error InvalidConfig();

    /// @notice Invalid co-signature
    error InvalidCoSignature();

    constructor(address _safe, uint32 _threshold, uint32 _totalSigners, bytes memory publicKey) {
        if (_threshold == 0 || _threshold > _totalSigners) revert InvalidConfig();
        if (publicKey.length != PUBLIC_KEY_SIZE || publicKey[0] != 0x04) revert InvalidConfig();

        safe = _safe;
        threshold = _threshold;
        totalSigners = _totalSigners;
        _PUBLIC_KEY = publicKey;
    }

    /// @notice Returns the aggregated public key
    function publicKey() external view returns (bytes memory) {
        return _PUBLIC_KEY;
    }

    /// @notice Verifies that the co-signature is valid for the Safe transaction
    function verifyCoSignature(bytes32 safeTxHash, bytes calldata coSignature) external {
        if (msg.sender != safe) revert OnlySafe();
        if (coSignature.length != SIGNATURE_SIZE) revert InvalidCoSignature();

        bool valid = ICGGMP21(CGGMP21_PRECOMPILE).verify(
            threshold,
            totalSigners,
            _PUBLIC_KEY,
            safeTxHash,
            coSignature
        );

        if (!valid) revert InvalidCoSignature();

        emit CoSignatureVerified(safeTxHash, threshold, totalSigners);
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 message, bytes calldata signature) external view returns (bytes4 magicValue) {
        if (signature.length != SIGNATURE_SIZE) return bytes4(0);

        bool valid = ICGGMP21(CGGMP21_PRECOMPILE).verify(
            threshold,
            totalSigners,
            _PUBLIC_KEY,
            message,
            signature
        );

        if (valid) magicValue = IERC1271.isValidSignature.selector;
    }
}
