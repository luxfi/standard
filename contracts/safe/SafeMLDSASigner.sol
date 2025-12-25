// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {IERC1271, ILegacyERC1271} from "./interfaces/IERC1271.sol";

/// @title IMLDSA
/// @dev Interface for the ML-DSA precompile at 0x0200000000000000000000000000000000000006
interface IMLDSA {
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title Safe ML-DSA Signer
/// @notice Safe smart account owner that can verify ML-DSA (FIPS 204) post-quantum signatures.
/// @dev This contract enables quantum-resistant signature verification for Safe multisigs
/// using the ML-DSA-65 algorithm (security level 3, equivalent to AES-192).
///
/// ML-DSA (Module-Lattice-Based Digital Signature Algorithm) is standardized in FIPS 204
/// and provides security against both classical and quantum computer attacks.
///
/// Key Sizes (ML-DSA-65):
/// - Public Key: 1952 bytes
/// - Signature: 3309 bytes
///
/// Usage:
/// 1. Generate an ML-DSA-65 keypair offline
/// 2. Deploy SafeMLDSASigner with the public key
/// 3. Add the deployed contract address as a Safe owner
/// 4. Sign Safe transactions with the ML-DSA private key
contract SafeMLDSASigner is IERC1271, ILegacyERC1271 {
    /// @dev ML-DSA precompile address
    address constant MLDSA_PRECOMPILE = 0x0200000000000000000000000000000000000006;

    /// @dev ML-DSA-65 public key size
    uint256 constant PUBLIC_KEY_SIZE = 1952;

    /// @dev ML-DSA-65 signature size
    uint256 constant SIGNATURE_SIZE = 3309;

    /// @notice The signer's ML-DSA-65 public key (1952 bytes)
    bytes private _PUBLIC_KEY;

    /// @notice The public address derived from the public key hash
    address private immutable _SIGNER;

    /// @notice The public key size is invalid (must be 1952 bytes for ML-DSA-65)
    error InvalidPublicKeySize();

    /// @notice The public key is empty or all zeros
    error InvalidPublicKey();

    /// @param publicKey The 1952-byte ML-DSA-65 public key
    constructor(bytes memory publicKey) {
        if (publicKey.length != PUBLIC_KEY_SIZE) {
            revert InvalidPublicKeySize();
        }

        // Basic validation: ensure public key is not all zeros
        bool allZeros = true;
        for (uint256 i = 0; i < 32 && allZeros; i++) {
            if (publicKey[i] != 0) {
                allZeros = false;
            }
        }
        if (allZeros) {
            revert InvalidPublicKey();
        }

        _PUBLIC_KEY = publicKey;
        // Derive a deterministic address from the public key hash
        _SIGNER = address(uint160(uint256(keccak256(publicKey))));
    }

    /// @notice Returns the signer's ML-DSA-65 public key
    function publicKey() external view returns (bytes memory) {
        return _PUBLIC_KEY;
    }

    /// @notice Returns the derived signer address
    function signer() external view returns (address) {
        return _SIGNER;
    }

    /// @notice Checks if the given signature is valid for the given message hash.
    /// @param messageHash The keccak256 hash of the message to be verified.
    /// @param signature The 3309-byte ML-DSA-65 signature.
    /// @return ok Whether or not the signature is valid.
    function _isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bool ok) {
        // Validate signature size
        if (signature.length != SIGNATURE_SIZE) {
            return false;
        }

        // Call the ML-DSA precompile to verify the signature
        // The precompile expects: publicKey, message, signature
        // We pass the messageHash as a 32-byte message
        return IMLDSA(MLDSA_PRECOMPILE).verify(
            _PUBLIC_KEY,
            abi.encodePacked(messageHash),
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

/// @title Safe ML-DSA Co-Signer
/// @notice Safe transaction guard that requires an additional ML-DSA signature.
/// @dev Use this to add quantum-resistant co-signing requirements to a Safe.
/// The co-signer signature must be appended to the Safe transaction signatures.
///
/// This provides defense-in-depth: even if ECDSA is broken by quantum computers,
/// the ML-DSA co-signature requirement protects the Safe.
contract SafeMLDSACoSigner is IERC1271 {
    /// @dev ML-DSA precompile address
    address constant MLDSA_PRECOMPILE = 0x0200000000000000000000000000000000000006;

    /// @dev ML-DSA-65 public key size
    uint256 constant PUBLIC_KEY_SIZE = 1952;

    /// @dev ML-DSA-65 signature size
    uint256 constant SIGNATURE_SIZE = 3309;

    /// @notice The Safe this co-signer is attached to
    address public immutable safe;

    /// @notice The co-signer's ML-DSA-65 public key
    bytes private _PUBLIC_KEY;

    /// @notice Emitted when a co-signature is verified
    event CoSignatureVerified(bytes32 indexed safeTxHash, address indexed safe);

    /// @notice Only the Safe can call this function
    error OnlySafe();

    /// @notice The public key size is invalid
    error InvalidPublicKeySize();

    /// @notice The co-signature is invalid
    error InvalidCoSignature();

    /// @param _safe The Safe address this co-signer protects
    /// @param publicKey The 1952-byte ML-DSA-65 public key
    constructor(address _safe, bytes memory publicKey) {
        if (publicKey.length != PUBLIC_KEY_SIZE) {
            revert InvalidPublicKeySize();
        }
        safe = _safe;
        _PUBLIC_KEY = publicKey;
    }

    /// @notice Returns the co-signer's ML-DSA-65 public key
    function publicKey() external view returns (bytes memory) {
        return _PUBLIC_KEY;
    }

    /// @notice Verifies that the co-signature is valid for the Safe transaction
    /// @param safeTxHash The Safe transaction hash
    /// @param coSignature The ML-DSA-65 co-signature (3309 bytes)
    function verifyCoSignature(bytes32 safeTxHash, bytes calldata coSignature) external {
        if (msg.sender != safe) {
            revert OnlySafe();
        }

        if (coSignature.length != SIGNATURE_SIZE) {
            revert InvalidCoSignature();
        }

        bool valid = IMLDSA(MLDSA_PRECOMPILE).verify(
            _PUBLIC_KEY,
            abi.encodePacked(safeTxHash),
            coSignature
        );

        if (!valid) {
            revert InvalidCoSignature();
        }

        emit CoSignatureVerified(safeTxHash, safe);
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 message, bytes calldata signature) external view returns (bytes4 magicValue) {
        if (signature.length != SIGNATURE_SIZE) {
            return bytes4(0);
        }

        bool valid = IMLDSA(MLDSA_PRECOMPILE).verify(
            _PUBLIC_KEY,
            abi.encodePacked(message),
            signature
        );

        if (valid) {
            magicValue = IERC1271.isValidSignature.selector;
        }
    }
}
