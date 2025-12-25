// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {IERC1271, ILegacyERC1271} from "./interfaces/IERC1271.sol";
import {ISafe} from "./interfaces/ISafe.sol";

/// @title ICGGMP21
/// @dev Interface for ECDSA verification (LSS produces standard ECDSA signatures)
interface ICGGMP21 {
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title Safe LSS Signer
/// @notice Safe smart account owner supporting LSS (Linear Secret Sharing) with dynamic resharing.
/// @dev This contract enables t-of-n threshold ECDSA signatures with live key resharing,
/// allowing the signing group to change without reconstructing the master key.
///
/// LSS (Linear Secret Sharing) MPC Protocol Features:
/// - Dynamic resharing: Add/remove signers without changing public key
/// - Threshold changes: Transition from T-of-N to T'-of-(N±k)
/// - Generation tracking: Maintain history for rollback capability
/// - Standard ECDSA compatibility: Signatures work on Ethereum, Bitcoin, etc.
///
/// Integration with T-Chain:
/// - T-Chain coordinates LSS key generation and resharing
/// - Off-chain MPC protocol handles distributed signing
/// - This contract verifies the resulting ECDSA signatures on-chain
///
/// Usage:
/// 1. Initialize LSS key generation on T-Chain
/// 2. Deploy SafeLSSSigner with initial public key and threshold
/// 3. Add as Safe owner
/// 4. Threshold parties sign via LSS coordinator
/// 5. Reshare to add/remove parties as needed (governance-controlled)
contract SafeLSSSigner is IERC1271, ILegacyERC1271 {
    /// @dev CGGMP21 precompile for ECDSA verification (LSS produces standard ECDSA)
    address constant CGGMP21_PRECOMPILE = 0x020000000000000000000000000000000000000D;

    /// @dev Public key and signature sizes
    uint256 constant PUBLIC_KEY_SIZE = 65;
    uint256 constant SIGNATURE_SIZE = 65;

    /// @notice The Safe this signer is attached to
    address public immutable safe;

    /// @notice The current signing threshold (t)
    uint32 public threshold;

    /// @notice The current total number of signers (n)
    uint32 public totalSigners;

    /// @notice The current aggregated public key (65 bytes uncompressed secp256k1)
    bytes public publicKey;

    /// @notice The current generation (incremented on each resharing)
    uint256 public generation;

    /// @notice Derived signer address from public key
    address public signer;

    /// @notice Historical generations for audit trail
    struct GenerationInfo {
        uint32 threshold;
        uint32 totalSigners;
        bytes publicKey;
        uint256 timestamp;
        bytes32 commitment;
    }

    /// @notice Generation history (generation => info)
    mapping(uint256 => GenerationInfo) public generations;

    /// @notice Emitted when the signing group is reshared
    event Reshared(
        uint256 indexed generation,
        uint32 newThreshold,
        uint32 newTotalSigners,
        bytes32 commitment
    );

    /// @notice Emitted when a signature is verified
    event SignatureVerified(bytes32 indexed messageHash, uint256 generation);

    /// @notice Only the Safe can call this function
    error OnlySafe();

    /// @notice Invalid configuration
    error InvalidConfig();

    /// @notice Invalid public key size or format
    error InvalidPublicKey();

    /// @notice Public key unchanged during reshare
    error PublicKeyMustBeUnchanged();

    /// @param _safe The Safe address this signer belongs to
    /// @param _threshold Initial signing threshold (t)
    /// @param _totalSigners Initial total signers (n)
    /// @param _publicKey Initial 65-byte uncompressed secp256k1 public key
    constructor(
        address _safe,
        uint32 _threshold,
        uint32 _totalSigners,
        bytes memory _publicKey
    ) {
        if (_threshold == 0 || _threshold > _totalSigners) revert InvalidConfig();
        if (_publicKey.length != PUBLIC_KEY_SIZE || _publicKey[0] != 0x04) revert InvalidPublicKey();

        safe = _safe;
        threshold = _threshold;
        totalSigners = _totalSigners;
        publicKey = _publicKey;
        generation = 1;

        // Derive Ethereum address from public key
        bytes memory pubKeyNoPrefix = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            pubKeyNoPrefix[i] = _publicKey[i + 1];
        }
        signer = address(uint160(uint256(keccak256(pubKeyNoPrefix))));

        // Record initial generation
        generations[1] = GenerationInfo({
            threshold: _threshold,
            totalSigners: _totalSigners,
            publicKey: _publicKey,
            timestamp: block.timestamp,
            commitment: keccak256(abi.encodePacked(_threshold, _totalSigners, _publicKey))
        });
    }

    modifier onlySafe() {
        if (msg.sender != safe) revert OnlySafe();
        _;
    }

    /// @notice Reshare the signing group with new threshold/total
    /// @dev Called by Safe after off-chain LSS resharing completes on T-Chain
    /// @param newThreshold New signing threshold
    /// @param newTotalSigners New total number of signers
    /// @param commitment Cryptographic commitment from resharing protocol
    /// @custom:security The public key MUST remain unchanged after resharing
    function reshare(
        uint32 newThreshold,
        uint32 newTotalSigners,
        bytes32 commitment
    ) external onlySafe {
        if (newThreshold == 0 || newThreshold > newTotalSigners) revert InvalidConfig();

        // Update state
        threshold = newThreshold;
        totalSigners = newTotalSigners;
        generation++;

        // Record in history
        generations[generation] = GenerationInfo({
            threshold: newThreshold,
            totalSigners: newTotalSigners,
            publicKey: publicKey, // Public key unchanged
            timestamp: block.timestamp,
            commitment: commitment
        });

        emit Reshared(generation, newThreshold, newTotalSigners, commitment);
    }

    /// @notice Emergency rollback to previous generation
    /// @dev Only used if current generation has issues
    /// @param targetGeneration The generation to rollback to
    function rollback(uint256 targetGeneration) external onlySafe {
        require(targetGeneration > 0 && targetGeneration < generation, "Invalid generation");

        GenerationInfo storage target = generations[targetGeneration];
        require(target.timestamp > 0, "Generation not found");

        threshold = target.threshold;
        totalSigners = target.totalSigners;
        // Note: publicKey stays the same (LSS invariant)

        generation = targetGeneration;
    }

    /// @notice Checks if the given signature is valid for the given message hash.
    /// @param messageHash The keccak256 hash of the message to be verified.
    /// @param signature The 65-byte ECDSA signature (r || s || v).
    /// @return ok Whether or not the signature is valid.
    function _isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bool ok) {
        if (signature.length != SIGNATURE_SIZE) {
            return false;
        }

        return ICGGMP21(CGGMP21_PRECOMPILE).verify(
            threshold,
            totalSigners,
            publicKey,
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

    /// @notice Get generation info
    function getGeneration(uint256 gen) external view returns (
        uint32 t,
        uint32 n,
        bytes memory pk,
        uint256 ts,
        bytes32 commitment
    ) {
        GenerationInfo storage info = generations[gen];
        return (info.threshold, info.totalSigners, info.publicKey, info.timestamp, info.commitment);
    }
}

/// @title LSS Coordinator Interface
/// @dev Interface for interacting with T-Chain LSS coordinator
interface ILSSCoordinator {
    /// @notice Request a new signing session
    function requestSign(bytes32 messageHash, address callback) external returns (bytes32 sessionId);

    /// @notice Request resharing with new parameters
    function requestReshare(
        address signer,
        uint32 newThreshold,
        uint32 newTotalSigners,
        address[] calldata newParties
    ) external returns (bytes32 sessionId);

    /// @notice Get current generation for a signer
    function getGeneration(address signer) external view returns (uint256);
}

/// @title Safe LSS Factory
/// @notice Factory for deploying SafeLSSSigner instances
contract SafeLSSFactory {
    /// @notice Emitted when a new LSS signer is deployed
    event LSSSignerDeployed(
        address indexed safe,
        address indexed signer,
        uint32 threshold,
        uint32 totalSigners
    );

    /// @notice Deploy a new SafeLSSSigner for a Safe
    /// @param safe The Safe address
    /// @param threshold Initial signing threshold
    /// @param totalSigners Initial total signers
    /// @param publicKey Initial aggregated public key
    function deploy(
        address safe,
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey
    ) external returns (address) {
        SafeLSSSigner signer = new SafeLSSSigner(
            safe,
            threshold,
            totalSigners,
            publicKey
        );

        emit LSSSignerDeployed(safe, address(signer), threshold, totalSigners);

        return address(signer);
    }

    /// @notice Compute deployment address
    function computeAddress(
        address safe,
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 salt
    ) external view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(SafeLSSSigner).creationCode,
            abi.encode(safe, threshold, totalSigners, publicKey)
        );

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(bytecode)
        )))));
    }
}
