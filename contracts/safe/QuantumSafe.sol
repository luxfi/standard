// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {IERC1271, ILegacyERC1271} from "./interfaces/IERC1271.sol";
import {ISafe} from "./interfaces/ISafe.sol";
import {IERC165} from "./interfaces/IERC165.sol";

/// @title IFROST
/// @dev Interface for FROST Schnorr threshold signature precompile
interface IFROST {
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title ICGGMP21
/// @dev Interface for CGGMP21 threshold ECDSA precompile
interface ICGGMP21 {
    function verify(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title IMLDSA
/// @dev Interface for ML-DSA post-quantum signature precompile
interface IMLDSA {
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title IRingtailThreshold
/// @dev Interface for Ringtail post-quantum threshold signature precompile
interface IRingtailThreshold {
    function verifyThreshold(
        uint32 threshold,
        uint32 totalParties,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title IBLS
/// @dev Interface for BLS signature verification precompile (Quasar consensus)
interface IBLS {
    function verify(
        bytes calldata publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool valid);
}

/// @title QuantumSafe
/// @notice Unified Safe signer supporting multiple signature algorithms:
///         FROST, CGGMP21, ML-DSA, RINGTAIL (PQ threshold), and HYBRID modes
/// @dev This contract enables quantum-resistant and threshold signature verification
///      for Gnosis Safe multisigs with algorithm flexibility.
///
/// Supported Algorithms:
/// - FROST: Schnorr threshold signatures (Bitcoin Taproot compatible)
/// - CGGMP21: ECDSA threshold signatures (Ethereum/Bitcoin compatible)
/// - MLDSA: Post-quantum lattice-based signatures (NIST FIPS 204)
/// - RINGTAIL: Post-quantum threshold signatures (LWE-based lattice)
/// - HYBRID: BLS + Ringtail (classical aggregation + post-quantum threshold)
/// - HYBRID_PQ: Ringtail + ML-DSA (full post-quantum threshold + single)
///
/// Security Levels:
/// - FROST/CGGMP21: Classical security (NOT quantum-resistant)
/// - ML-DSA-65: NIST Level 3 (equivalent to AES-192)
/// - RINGTAIL: Post-quantum threshold (~128-bit quantum security)
/// - HYBRID: Quantum-resistant with classical fallback
/// - HYBRID_PQ: Full post-quantum protection
contract QuantumSafe is IERC1271, ILegacyERC1271, IERC165 {
    /// @dev Precompile addresses
    address constant FROST_PRECOMPILE = 0x020000000000000000000000000000000000000c;
    address constant CGGMP21_PRECOMPILE = 0x020000000000000000000000000000000000000D;
    address constant MLDSA_PRECOMPILE = 0x0200000000000000000000000000000000000006;
    address constant RINGTAIL_PRECOMPILE = 0x020000000000000000000000000000000000000B;
    address constant BLS_PRECOMPILE = 0x0300000000000000000000000000000000000021;

    /// @dev Signature sizes
    uint256 constant FROST_SIG_SIZE = 64;
    uint256 constant CGGMP21_SIG_SIZE = 65;
    uint256 constant CGGMP21_PUBKEY_SIZE = 65;
    uint256 constant MLDSA_SIG_SIZE = 3309;
    uint256 constant MLDSA_PUBKEY_SIZE = 1952;
    uint256 constant RINGTAIL_MIN_SIG_SIZE = 3500;
    uint256 constant RINGTAIL_MAX_SIG_SIZE = 5000;
    uint256 constant RINGTAIL_MIN_PUBKEY_SIZE = 1000;
    uint256 constant RINGTAIL_MAX_PUBKEY_SIZE = 2000;
    uint256 constant BLS_SIG_SIZE = 96;
    uint256 constant BLS_PUBKEY_SIZE = 48;

    /// @notice Signature algorithm types
    enum Algorithm {
        FROST,      // Schnorr threshold (t-of-n) - NOT quantum-safe
        CGGMP21,    // ECDSA threshold (t-of-n) - NOT quantum-safe
        MLDSA,      // Post-quantum single signer (FIPS 204)
        RINGTAIL,   // Post-quantum threshold (LWE-based lattice)
        HYBRID,     // BLS + Ringtail (aggregated classical + PQ threshold)
        HYBRID_PQ   // Ringtail + ML-DSA (full PQ: threshold + single)
    }

    /// @notice The algorithm this signer uses
    Algorithm public immutable algorithm;

    /// @notice Threshold parameters (for threshold algorithms)
    uint32 public immutable threshold;
    uint32 public immutable totalSigners;

    /// @notice FROST public key (32 bytes compressed)
    bytes32 public immutable frostPublicKey;

    /// @notice CGGMP21 public key (65 bytes uncompressed)
    bytes private _cggmpPublicKey;

    /// @notice ML-DSA public key (1952 bytes)
    bytes private _mldsaPublicKey;

    /// @notice Ringtail public key (~1.5KB)
    bytes private _ringtailPublicKey;

    /// @notice BLS public key (48 bytes compressed)
    bytes private _blsPublicKey;

    /// @notice Derived signer address
    address public immutable signer;

    /// @notice Invalid algorithm specified
    error InvalidAlgorithm();

    /// @notice Invalid threshold configuration
    error InvalidThreshold();

    /// @notice Invalid public key for the algorithm
    error InvalidPublicKey();

    /// @notice Invalid signature size for the algorithm
    error InvalidSignatureSize();

    /// @param _algorithm The signature algorithm to use
    /// @param _threshold Signing threshold (for threshold algorithms, 0 for single-signer)
    /// @param _totalSigners Total signers (for threshold algorithms, 0 for single-signer)
    /// @param _frostPubKey FROST public key (32 bytes, or empty)
    /// @param _cggmpPubKey CGGMP21 public key (65 bytes, or empty)
    /// @param _mldsaPubKey ML-DSA public key (1952 bytes, or empty)
    /// @param _ringtailPubKey Ringtail public key (~1.5KB, or empty)
    /// @param _blsPubKey BLS public key (48 bytes, or empty)
    constructor(
        Algorithm _algorithm,
        uint32 _threshold,
        uint32 _totalSigners,
        bytes32 _frostPubKey,
        bytes memory _cggmpPubKey,
        bytes memory _mldsaPubKey,
        bytes memory _ringtailPubKey,
        bytes memory _blsPubKey
    ) {
        algorithm = _algorithm;

        if (_algorithm == Algorithm.FROST) {
            if (_threshold == 0 || _threshold > _totalSigners) revert InvalidThreshold();
            if (_frostPubKey == bytes32(0)) revert InvalidPublicKey();
            threshold = _threshold;
            totalSigners = _totalSigners;
            frostPublicKey = _frostPubKey;
            signer = address(uint160(uint256(keccak256(abi.encodePacked(_frostPubKey)))));
        }
        else if (_algorithm == Algorithm.CGGMP21) {
            if (_threshold == 0 || _threshold > _totalSigners) revert InvalidThreshold();
            if (_cggmpPubKey.length != CGGMP21_PUBKEY_SIZE || _cggmpPubKey[0] != 0x04) revert InvalidPublicKey();
            threshold = _threshold;
            totalSigners = _totalSigners;
            _cggmpPublicKey = _cggmpPubKey;
            // Derive address from public key (skip 0x04 prefix)
            bytes memory pubKeyNoPrefix = new bytes(64);
            for (uint256 i = 0; i < 64; i++) {
                pubKeyNoPrefix[i] = _cggmpPubKey[i + 1];
            }
            signer = address(uint160(uint256(keccak256(pubKeyNoPrefix))));
        }
        else if (_algorithm == Algorithm.MLDSA) {
            if (_mldsaPubKey.length != MLDSA_PUBKEY_SIZE) revert InvalidPublicKey();
            threshold = 0;
            totalSigners = 0;
            _mldsaPublicKey = _mldsaPubKey;
            signer = address(uint160(uint256(keccak256(_mldsaPubKey))));
        }
        else if (_algorithm == Algorithm.RINGTAIL) {
            if (_threshold == 0 || _threshold > _totalSigners) revert InvalidThreshold();
            if (_ringtailPubKey.length < RINGTAIL_MIN_PUBKEY_SIZE || 
                _ringtailPubKey.length > RINGTAIL_MAX_PUBKEY_SIZE) revert InvalidPublicKey();
            threshold = _threshold;
            totalSigners = _totalSigners;
            _ringtailPublicKey = _ringtailPubKey;
            signer = address(uint160(uint256(keccak256(_ringtailPubKey))));
        }
        else if (_algorithm == Algorithm.HYBRID) {
            // HYBRID = BLS + Ringtail (classical aggregation + post-quantum threshold)
            if (_threshold == 0 || _threshold > _totalSigners) revert InvalidThreshold();
            if (_blsPubKey.length != BLS_PUBKEY_SIZE) revert InvalidPublicKey();
            if (_ringtailPubKey.length < RINGTAIL_MIN_PUBKEY_SIZE ||
                _ringtailPubKey.length > RINGTAIL_MAX_PUBKEY_SIZE) revert InvalidPublicKey();
            threshold = _threshold;
            totalSigners = _totalSigners;
            _blsPublicKey = _blsPubKey;
            _ringtailPublicKey = _ringtailPubKey;
            signer = address(uint160(uint256(keccak256(abi.encodePacked(_blsPubKey, _ringtailPubKey)))));
        }
        else if (_algorithm == Algorithm.HYBRID_PQ) {
            if (_threshold == 0 || _threshold > _totalSigners) revert InvalidThreshold();
            if (_ringtailPubKey.length < RINGTAIL_MIN_PUBKEY_SIZE ||
                _ringtailPubKey.length > RINGTAIL_MAX_PUBKEY_SIZE) revert InvalidPublicKey();
            if (_mldsaPubKey.length != MLDSA_PUBKEY_SIZE) revert InvalidPublicKey();
            threshold = _threshold;
            totalSigners = _totalSigners;
            _ringtailPublicKey = _ringtailPubKey;
            _mldsaPublicKey = _mldsaPubKey;
            signer = address(uint160(uint256(keccak256(abi.encodePacked(_ringtailPubKey, _mldsaPubKey)))));
        }
        else {
            revert InvalidAlgorithm();
        }
    }

    /// @notice Get CGGMP21 public key
    function cggmpPublicKey() external view returns (bytes memory) {
        return _cggmpPublicKey;
    }

    /// @notice Get ML-DSA public key
    function mldsaPublicKey() external view returns (bytes memory) {
        return _mldsaPublicKey;
    }

    /// @notice Get Ringtail public key
    function ringtailPublicKey() external view returns (bytes memory) {
        return _ringtailPublicKey;
    }

    /// @notice Get BLS public key
    function blsPublicKey() external view returns (bytes memory) {
        return _blsPublicKey;
    }

    /// @notice Verify signature based on configured algorithm
    function _isValidSignature(bytes32 messageHash, bytes calldata signature) public view returns (bool) {
        if (algorithm == Algorithm.FROST) {
            return _verifyFROST(messageHash, signature);
        }
        else if (algorithm == Algorithm.CGGMP21) {
            return _verifyCGGMP21(messageHash, signature);
        }
        else if (algorithm == Algorithm.MLDSA) {
            return _verifyMLDSA(messageHash, signature);
        }
        else if (algorithm == Algorithm.RINGTAIL) {
            return _verifyRingtail(messageHash, signature);
        }
        else if (algorithm == Algorithm.HYBRID) {
            return _verifyHybrid(messageHash, signature);
        }
        else if (algorithm == Algorithm.HYBRID_PQ) {
            return _verifyHybridPQ(messageHash, signature);
        }
        return false;
    }

    /// @dev Verify FROST Schnorr threshold signature
    function _verifyFROST(bytes32 messageHash, bytes calldata signature) internal view returns (bool) {
        if (signature.length != FROST_SIG_SIZE) return false;

        return IFROST(FROST_PRECOMPILE).verify(
            threshold,
            totalSigners,
            frostPublicKey,
            messageHash,
            signature
        );
    }

    /// @dev Verify CGGMP21 threshold ECDSA signature
    function _verifyCGGMP21(bytes32 messageHash, bytes calldata signature) internal view returns (bool) {
        if (signature.length != CGGMP21_SIG_SIZE) return false;

        return ICGGMP21(CGGMP21_PRECOMPILE).verify(
            threshold,
            totalSigners,
            _cggmpPublicKey,
            messageHash,
            signature
        );
    }

    /// @dev Verify ML-DSA post-quantum signature
    function _verifyMLDSA(bytes32 messageHash, bytes calldata signature) internal view returns (bool) {
        if (signature.length != MLDSA_SIG_SIZE) return false;

        return IMLDSA(MLDSA_PRECOMPILE).verify(
            _mldsaPublicKey,
            abi.encodePacked(messageHash),
            signature
        );
    }

    /// @dev Verify Ringtail post-quantum threshold signature
    function _verifyRingtail(bytes32 messageHash, bytes calldata signature) internal view returns (bool) {
        if (signature.length < RINGTAIL_MIN_SIG_SIZE || signature.length > RINGTAIL_MAX_SIG_SIZE) {
            return false;
        }

        return IRingtailThreshold(RINGTAIL_PRECOMPILE).verifyThreshold(
            threshold,
            totalSigners,
            messageHash,
            signature
        );
    }

    /// @dev Verify hybrid BLS + Ringtail signature
    /// @param signature Format: [BLS_SIG (96 bytes)][Ringtail_SIG (~4KB)]
    function _verifyHybrid(bytes32 messageHash, bytes calldata signature) internal view returns (bool) {
        // Minimum size: BLS (96) + Ringtail min (3500) = 3596
        uint256 minSize = BLS_SIG_SIZE + RINGTAIL_MIN_SIG_SIZE;
        uint256 maxSize = BLS_SIG_SIZE + RINGTAIL_MAX_SIG_SIZE;
        if (signature.length < minSize || signature.length > maxSize) return false;

        // Split signature: BLS is fixed 96 bytes, Ringtail is variable
        bytes calldata blsSig = signature[0:BLS_SIG_SIZE];
        bytes calldata ringtailSig = signature[BLS_SIG_SIZE:signature.length];

        // Both must verify
        bool blsValid = IBLS(BLS_PRECOMPILE).verify(
            _blsPublicKey,
            messageHash,
            blsSig
        );

        bool ringtailValid = IRingtailThreshold(RINGTAIL_PRECOMPILE).verifyThreshold(
            threshold,
            totalSigners,
            messageHash,
            ringtailSig
        );

        return blsValid && ringtailValid;
    }

    /// @dev Verify hybrid PQ Ringtail + ML-DSA signature (full post-quantum)
    /// @param signature Format: [Ringtail_SIG (~4KB)][ML-DSA_SIG (3309 bytes)]
    function _verifyHybridPQ(bytes32 messageHash, bytes calldata signature) internal view returns (bool) {
        // Minimum size: Ringtail min (3500) + ML-DSA (3309) = 6809
        uint256 minSize = RINGTAIL_MIN_SIG_SIZE + MLDSA_SIG_SIZE;
        uint256 maxSize = RINGTAIL_MAX_SIG_SIZE + MLDSA_SIG_SIZE;
        if (signature.length < minSize || signature.length > maxSize) return false;

        // Ringtail signature is variable, ML-DSA is fixed at end
        uint256 ringtailLen = signature.length - MLDSA_SIG_SIZE;
        bytes calldata ringtailSig = signature[0:ringtailLen];
        bytes calldata mldsaSig = signature[ringtailLen:signature.length];

        // Both must verify
        bool ringtailValid = IRingtailThreshold(RINGTAIL_PRECOMPILE).verifyThreshold(
            threshold,
            totalSigners,
            messageHash,
            ringtailSig
        );

        bool mldsaValid = IMLDSA(MLDSA_PRECOMPILE).verify(
            _mldsaPublicKey,
            abi.encodePacked(messageHash),
            mldsaSig
        );

        return ringtailValid && mldsaValid;
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

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1271).interfaceId ||
               interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Get algorithm name
    function algorithmName() external view returns (string memory) {
        if (algorithm == Algorithm.FROST) return "FROST";
        if (algorithm == Algorithm.CGGMP21) return "CGGMP21";
        if (algorithm == Algorithm.MLDSA) return "ML-DSA-65";
        if (algorithm == Algorithm.RINGTAIL) return "RINGTAIL";
        if (algorithm == Algorithm.HYBRID) return "HYBRID (BLS + Ringtail)";
        if (algorithm == Algorithm.HYBRID_PQ) return "HYBRID_PQ (Ringtail + ML-DSA)";
        return "UNKNOWN";
    }

    /// @notice Check if algorithm is quantum-resistant
    function isQuantumResistant() external view returns (bool) {
        return algorithm == Algorithm.MLDSA || 
               algorithm == Algorithm.RINGTAIL || 
               algorithm == Algorithm.HYBRID ||
               algorithm == Algorithm.HYBRID_PQ;
    }

    /// @notice Check if algorithm is threshold-based
    function isThreshold() external view returns (bool) {
        return algorithm == Algorithm.FROST ||
               algorithm == Algorithm.CGGMP21 ||
               algorithm == Algorithm.RINGTAIL ||
               algorithm == Algorithm.HYBRID ||
               algorithm == Algorithm.HYBRID_PQ;
    }

    /// @notice Get expected signature size for the algorithm (returns range for variable-size)
    function expectedSignatureSize() external view returns (uint256 min, uint256 max) {
        if (algorithm == Algorithm.FROST) return (FROST_SIG_SIZE, FROST_SIG_SIZE);
        if (algorithm == Algorithm.CGGMP21) return (CGGMP21_SIG_SIZE, CGGMP21_SIG_SIZE);
        if (algorithm == Algorithm.MLDSA) return (MLDSA_SIG_SIZE, MLDSA_SIG_SIZE);
        if (algorithm == Algorithm.RINGTAIL) return (RINGTAIL_MIN_SIG_SIZE, RINGTAIL_MAX_SIG_SIZE);
        if (algorithm == Algorithm.HYBRID) {
            return (BLS_SIG_SIZE + RINGTAIL_MIN_SIG_SIZE, BLS_SIG_SIZE + RINGTAIL_MAX_SIG_SIZE);
        }
        if (algorithm == Algorithm.HYBRID_PQ) {
            return (RINGTAIL_MIN_SIG_SIZE + MLDSA_SIG_SIZE, RINGTAIL_MAX_SIG_SIZE + MLDSA_SIG_SIZE);
        }
        return (0, 0);
    }
}

/// @title QuantumSafe Factory
/// @notice Factory for deploying QuantumSafe instances
contract QuantumSafeFactory {
    event QuantumSafeDeployed(
        address indexed signer,
        QuantumSafe.Algorithm algorithm,
        uint32 threshold,
        uint32 totalSigners,
        bool quantumResistant
    );

    /// @notice Deploy a FROST-based QuantumSafe (NOT quantum-resistant)
    function deployFROST(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey
    ) external returns (address) {
        QuantumSafe qs = new QuantumSafe(
            QuantumSafe.Algorithm.FROST,
            threshold,
            totalSigners,
            publicKey,
            "",
            "",
            "",
            ""
        );
        emit QuantumSafeDeployed(address(qs), QuantumSafe.Algorithm.FROST, threshold, totalSigners, false);
        return address(qs);
    }

    /// @notice Deploy a CGGMP21-based QuantumSafe (NOT quantum-resistant)
    function deployCGGMP21(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey
    ) external returns (address) {
        QuantumSafe qs = new QuantumSafe(
            QuantumSafe.Algorithm.CGGMP21,
            threshold,
            totalSigners,
            bytes32(0),
            publicKey,
            "",
            "",
            ""
        );
        emit QuantumSafeDeployed(address(qs), QuantumSafe.Algorithm.CGGMP21, threshold, totalSigners, false);
        return address(qs);
    }

    /// @notice Deploy an ML-DSA-based QuantumSafe (quantum-resistant, single signer)
    function deployMLDSA(bytes calldata publicKey) external returns (address) {
        QuantumSafe qs = new QuantumSafe(
            QuantumSafe.Algorithm.MLDSA,
            0,
            0,
            bytes32(0),
            "",
            publicKey,
            "",
            ""
        );
        emit QuantumSafeDeployed(address(qs), QuantumSafe.Algorithm.MLDSA, 0, 0, true);
        return address(qs);
    }

    /// @notice Deploy a Ringtail-based QuantumSafe (quantum-resistant threshold)
    function deployRingtail(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata publicKey
    ) external returns (address) {
        QuantumSafe qs = new QuantumSafe(
            QuantumSafe.Algorithm.RINGTAIL,
            threshold,
            totalSigners,
            bytes32(0),
            "",
            "",
            publicKey,
            ""
        );
        emit QuantumSafeDeployed(address(qs), QuantumSafe.Algorithm.RINGTAIL, threshold, totalSigners, true);
        return address(qs);
    }

    /// @notice Deploy a hybrid QuantumSafe (BLS + Ringtail)
    function deployHybrid(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata blsPublicKey,
        bytes calldata ringtailPublicKey
    ) external returns (address) {
        QuantumSafe qs = new QuantumSafe(
            QuantumSafe.Algorithm.HYBRID,
            threshold,
            totalSigners,
            bytes32(0),
            "",
            "",
            ringtailPublicKey,
            blsPublicKey
        );
        emit QuantumSafeDeployed(address(qs), QuantumSafe.Algorithm.HYBRID, threshold, totalSigners, true);
        return address(qs);
    }

    /// @notice Deploy a full PQ hybrid QuantumSafe (Ringtail + ML-DSA)
    function deployHybridPQ(
        uint32 threshold,
        uint32 totalSigners,
        bytes calldata ringtailPublicKey,
        bytes calldata mldsaPublicKey
    ) external returns (address) {
        QuantumSafe qs = new QuantumSafe(
            QuantumSafe.Algorithm.HYBRID_PQ,
            threshold,
            totalSigners,
            bytes32(0),
            "",
            mldsaPublicKey,
            ringtailPublicKey,
            ""
        );
        emit QuantumSafeDeployed(address(qs), QuantumSafe.Algorithm.HYBRID_PQ, threshold, totalSigners, true);
        return address(qs);
    }
}
