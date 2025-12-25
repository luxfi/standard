// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {IERC1271, ILegacyERC1271} from "./interfaces/IERC1271.sol";

/// @title IRingtailThreshold
/// @dev Interface for the Ringtail Threshold precompile at 0x020000000000000000000000000000000000000B
/// Ringtail is a post-quantum threshold signature scheme based on Module-LWE (Lattice)
interface IRingtailThreshold {
    function verifyThreshold(
        uint32 threshold,
        uint32 totalParties,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title Safe Ringtail Signer
/// @notice Safe smart account owner that can verify Ringtail post-quantum threshold signatures.
/// @dev This contract enables quantum-resistant t-of-n threshold signature verification for Safe multisigs
/// using the Ringtail protocol based on Module-LWE lattice cryptography.
///
/// Ringtail (eprint.iacr.org/2024/1113) provides:
/// - Post-quantum security (resistant to Shor's algorithm)
/// - Two-round threshold signing protocol
/// - LWE-based lattice cryptography (>128-bit classical + quantum security)
/// - Compatible with Quasar consensus validators
///
/// Key Sizes:
/// - Public Key: ~1.5KB (varies by security level)
/// - Signature: ~4KB (larger than classical but quantum-resistant)
///
/// Gas Costs:
/// - Base verification: 150,000 gas
/// - Per party: 10,000 gas
///
/// Usage:
/// 1. Run distributed key generation with threshold parties using Ringtail/T-Chain
/// 2. Deploy SafeRingtailSigner with aggregated public key and threshold params
/// 3. Add the deployed contract address as a Safe owner
/// 4. Threshold parties sign Safe transactions collaboratively
contract SafeRingtailSigner is IERC1271, ILegacyERC1271 {
    /// @dev Ringtail threshold precompile address
    address constant RINGTAIL_PRECOMPILE = 0x020000000000000000000000000000000000000B;

    /// @dev Signature size bounds for Ringtail (~4KB)
    uint256 constant MIN_SIGNATURE_SIZE = 3500;
    uint256 constant MAX_SIGNATURE_SIZE = 5000;

    /// @notice The signing threshold (t)
    uint32 public immutable threshold;

    /// @notice The total number of parties (n)
    uint32 public immutable totalParties;

    /// @notice The aggregated public key (~1.5KB)
    bytes private _PUBLIC_KEY;

    /// @notice The derived signer address from the public key
    address private immutable _SIGNER;

    /// @notice Invalid threshold (must be > 0 and <= totalParties)
    error InvalidThreshold();

    /// @notice Invalid public key (must be ~1.5KB for Ringtail)
    error InvalidPublicKey();

    /// @notice Invalid signature size (must be 3.5-5KB for Ringtail)
    error InvalidSignatureSize();

    /// @param _threshold The minimum number of parties required (t)
    /// @param _totalParties The total number of parties (n)
    /// @param publicKey The Ringtail aggregated public key (~1.5KB)
    constructor(uint32 _threshold, uint32 _totalParties, bytes memory publicKey) {
        if (_threshold == 0 || _threshold > _totalParties) {
            revert InvalidThreshold();
        }
        // Ringtail public keys are ~1.5KB
        if (publicKey.length < 1000 || publicKey.length > 2000) {
            revert InvalidPublicKey();
        }

        threshold = _threshold;
        totalParties = _totalParties;
        _PUBLIC_KEY = publicKey;

        // Derive Ethereum address from public key hash
        _SIGNER = address(uint160(uint256(keccak256(publicKey))));
    }

    /// @notice Returns the aggregated public key
    function publicKey() external view returns (bytes memory) {
        return _PUBLIC_KEY;
    }

    /// @notice Returns the derived signer address
    function signer() external view returns (address) {
        return _SIGNER;
    }

    /// @notice Check if this signer is quantum-resistant
    function isQuantumResistant() external pure returns (bool) {
        return true;
    }

    /// @notice Get the expected signature size range
    function signatureSizeRange() external pure returns (uint256 min, uint256 max) {
        return (MIN_SIGNATURE_SIZE, MAX_SIGNATURE_SIZE);
    }

    /// @notice Estimate gas for verification
    function estimateGas() external view returns (uint256) {
        return 150_000 + (uint256(totalParties) * 10_000);
    }

    /// @notice Checks if the given signature is valid for the given message hash.
    /// @param messageHash The keccak256 hash of the message to be verified.
    /// @param signature The Ringtail threshold signature (~4KB).
    /// @return ok Whether or not the signature is valid.
    function _isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bool ok) {
        // Validate signature size (Ringtail signatures are ~4KB)
        if (signature.length < MIN_SIGNATURE_SIZE || signature.length > MAX_SIGNATURE_SIZE) {
            return false;
        }

        // Call the Ringtail precompile to verify the threshold signature
        return IRingtailThreshold(RINGTAIL_PRECOMPILE).verifyThreshold(
            threshold,
            totalParties,
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

/// @title Safe Ringtail Co-Signer
/// @notice Safe transaction guard requiring an additional Ringtail quantum-resistant signature.
/// @dev Use this to add post-quantum t-of-n threshold co-signing to a Safe.
/// Provides protection against future quantum computer attacks.
contract SafeRingtailCoSigner is IERC1271 {
    /// @dev Ringtail threshold precompile address
    address constant RINGTAIL_PRECOMPILE = 0x020000000000000000000000000000000000000B;

    /// @dev Signature size bounds
    uint256 constant MIN_SIGNATURE_SIZE = 3500;
    uint256 constant MAX_SIGNATURE_SIZE = 5000;

    /// @notice The Safe this co-signer is attached to
    address public immutable safe;

    /// @notice The signing threshold
    uint32 public immutable threshold;

    /// @notice The total number of parties
    uint32 public immutable totalParties;

    /// @notice The aggregated public key
    bytes private _PUBLIC_KEY;

    /// @notice Emitted when a co-signature is verified
    event CoSignatureVerified(bytes32 indexed safeTxHash, uint32 threshold, uint32 totalParties);

    /// @notice Only the Safe can call this function
    error OnlySafe();

    /// @notice Invalid configuration
    error InvalidConfig();

    /// @notice Invalid co-signature
    error InvalidCoSignature();

    constructor(address _safe, uint32 _threshold, uint32 _totalParties, bytes memory publicKey) {
        if (_threshold == 0 || _threshold > _totalParties) revert InvalidConfig();
        if (publicKey.length < 1000 || publicKey.length > 2000) revert InvalidConfig();

        safe = _safe;
        threshold = _threshold;
        totalParties = _totalParties;
        _PUBLIC_KEY = publicKey;
    }

    /// @notice Returns the aggregated public key
    function publicKey() external view returns (bytes memory) {
        return _PUBLIC_KEY;
    }

    /// @notice Check if this co-signer is quantum-resistant
    function isQuantumResistant() external pure returns (bool) {
        return true;
    }

    /// @notice Verifies that the co-signature is valid for the Safe transaction
    function verifyCoSignature(bytes32 safeTxHash, bytes calldata coSignature) external {
        if (msg.sender != safe) revert OnlySafe();
        if (coSignature.length < MIN_SIGNATURE_SIZE || coSignature.length > MAX_SIGNATURE_SIZE) {
            revert InvalidCoSignature();
        }

        bool valid = IRingtailThreshold(RINGTAIL_PRECOMPILE).verifyThreshold(
            threshold,
            totalParties,
            safeTxHash,
            coSignature
        );

        if (!valid) revert InvalidCoSignature();

        emit CoSignatureVerified(safeTxHash, threshold, totalParties);
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 message, bytes calldata signature) external view returns (bytes4 magicValue) {
        if (signature.length < MIN_SIGNATURE_SIZE || signature.length > MAX_SIGNATURE_SIZE) {
            return bytes4(0);
        }

        bool valid = IRingtailThreshold(RINGTAIL_PRECOMPILE).verifyThreshold(
            threshold,
            totalParties,
            message,
            signature
        );

        if (valid) magicValue = IERC1271.isValidSignature.selector;
    }
}

/// @title Safe Ringtail Factory
/// @notice Factory for deploying SafeRingtailSigner instances
contract SafeRingtailFactory {
    /// @notice Emitted when a new Ringtail signer is deployed
    event RingtailSignerDeployed(
        address indexed signer,
        uint32 threshold,
        uint32 totalParties,
        bool quantumResistant
    );

    /// @notice Deploy a new SafeRingtailSigner
    function deploy(
        uint32 threshold,
        uint32 totalParties,
        bytes calldata publicKey
    ) external returns (address) {
        SafeRingtailSigner signer = new SafeRingtailSigner(
            threshold,
            totalParties,
            publicKey
        );

        emit RingtailSignerDeployed(address(signer), threshold, totalParties, true);

        return address(signer);
    }

    /// @notice Deploy a new SafeRingtailCoSigner for a Safe
    function deployCoSigner(
        address safe,
        uint32 threshold,
        uint32 totalParties,
        bytes calldata publicKey
    ) external returns (address) {
        SafeRingtailCoSigner coSigner = new SafeRingtailCoSigner(
            safe,
            threshold,
            totalParties,
            publicKey
        );

        return address(coSigner);
    }
}
