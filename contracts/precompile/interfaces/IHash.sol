// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHash - High-Performance Hashing Precompile Interfaces
 * @notice GPU-accelerated cryptographic hash functions via Metal/CUDA
 * @dev Precompile addresses: 0xA000-0xA003 (Lux Hashing range)
 *
 * Address Map:
 *   0xA000 - Poseidon2 (ZK-friendly hash)
 *   0xA001 - Poseidon2 Sponge (variable-length)
 *   0xA002 - Pedersen Hash (curve-based)
 *   0xA003 - Blake3 (high-performance)
 *
 * Performance (Apple M1 Max):
 *   Blake3:    ~50 GB/s (GPU) / ~1 GB/s (CPU)
 *   Poseidon2: ~500 MB/s (GPU) / ~50 MB/s (CPU)
 *   Pedersen:  ~100 MB/s (GPU) / ~10 MB/s (CPU)
 */

// ============================================================================
// BLAKE3 INTERFACE (0xA003)
// ============================================================================

/**
 * @title IBlake3
 * @notice Blake3 cryptographic hash precompile at 0xA003
 * @dev High-performance general-purpose hashing
 * @dev Gas: 15 per 32 bytes (minimum 100)
 */
interface IBlake3 {
    /// @notice Hash data using Blake3
    /// @param data Input data to hash
    /// @return digest 32-byte Blake3 hash
    function hash(bytes calldata data) external view returns (bytes32 digest);

    /// @notice Keyed Blake3 hash (MAC)
    /// @param key 32-byte key
    /// @param data Input data
    /// @return digest 32-byte keyed hash
    function hashKeyed(
        bytes32 key,
        bytes calldata data
    ) external view returns (bytes32 digest);

    /// @notice Extended output (XOF mode)
    /// @param data Input data
    /// @param outputLength Desired output length in bytes
    /// @return output Variable-length hash output
    function hashXOF(
        bytes calldata data,
        uint32 outputLength
    ) external view returns (bytes memory output);

    /// @notice Derive key from context and material
    /// @param context Context string for domain separation
    /// @param material Key material
    /// @return key Derived 32-byte key
    function deriveKey(
        string calldata context,
        bytes calldata material
    ) external view returns (bytes32 key);

    /// @notice Compute merkle root from leaves
    /// @param leaves Array of 32-byte leaf hashes
    /// @return root Merkle tree root
    function merkleRoot(
        bytes32[] calldata leaves
    ) external view returns (bytes32 root);

    /// @notice Hash multiple inputs in batch
    /// @param inputs Array of data to hash
    /// @return digests Array of 32-byte hashes
    function batchHash(
        bytes[] calldata inputs
    ) external view returns (bytes32[] memory digests);
}

// ============================================================================
// POSEIDON2 INTERFACE (0xA000-0xA001)
// ============================================================================

/**
 * @title IPoseidon2
 * @notice Poseidon2 ZK-friendly hash at 0xA000
 * @dev Optimized for SNARK/STARK circuits
 * @dev Gas: 40 per field element (minimum 200)
 */
interface IPoseidon2 {
    /// @notice Hash 2 field elements
    /// @param a First input
    /// @param b Second input
    /// @return digest Hash output
    function hash2(
        uint256 a,
        uint256 b
    ) external view returns (uint256 digest);

    /// @notice Hash 4 field elements
    function hash4(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) external view returns (uint256 digest);

    /// @notice Hash 8 field elements (single compression)
    function hash8(
        uint256[8] calldata inputs
    ) external view returns (uint256 digest);

    /// @notice Hash array of field elements
    /// @param inputs Field elements to hash
    /// @return digest Single hash output
    function hashMany(
        uint256[] calldata inputs
    ) external view returns (uint256 digest);

    /// @notice Compute merkle root with Poseidon2
    /// @param leaves Array of field element leaves
    /// @return root Merkle root
    function merkleRoot(
        uint256[] calldata leaves
    ) external view returns (uint256 root);

    /// @notice Hash bytes to field element
    /// @param data Raw bytes to hash
    /// @return digest Field element hash
    function hashBytes(
        bytes calldata data
    ) external view returns (uint256 digest);
}

/**
 * @title IPoseidon2Sponge
 * @notice Poseidon2 sponge construction at 0xA001
 * @dev For variable-length input/output
 */
interface IPoseidon2Sponge {
    /// @notice Absorb data into sponge and squeeze output
    /// @param inputs Field elements to absorb
    /// @param outputCount Number of outputs to squeeze
    /// @return outputs Squeezed field elements
    function sponge(
        uint256[] calldata inputs,
        uint32 outputCount
    ) external view returns (uint256[] memory outputs);

    /// @notice Encrypt using Poseidon2 in sponge mode
    /// @param key Encryption key (field element)
    /// @param nonce Nonce (field element)
    /// @param plaintext Data to encrypt
    /// @return ciphertext Encrypted data
    function encrypt(
        uint256 key,
        uint256 nonce,
        uint256[] calldata plaintext
    ) external view returns (uint256[] memory ciphertext);

    /// @notice Decrypt using Poseidon2 in sponge mode
    /// @param key Decryption key
    /// @param nonce Nonce used during encryption
    /// @param ciphertext Data to decrypt
    /// @return plaintext Decrypted data
    function decrypt(
        uint256 key,
        uint256 nonce,
        uint256[] calldata ciphertext
    ) external view returns (uint256[] memory plaintext);
}

// ============================================================================
// PEDERSEN HASH INTERFACE (0xA002)
// ============================================================================

/**
 * @title IPedersen
 * @notice Pedersen hash (BN254 curve) at 0xA002
 * @dev Curve-based hash with algebraic structure
 * @dev Gas: 3000 per 256-bit chunk (minimum 3000)
 */
interface IPedersen {
    /// @notice Hash data using Pedersen hash
    /// @param data Input data to hash
    /// @return x X-coordinate of resulting point
    /// @return y Y-coordinate of resulting point
    function hash(
        bytes calldata data
    ) external view returns (uint256 x, uint256 y);

    /// @notice Pedersen commitment: C = v*G + r*H
    /// @param value Value to commit
    /// @param blinding Blinding factor
    /// @return commitment 64-byte commitment (x || y)
    function commit(
        uint256 value,
        uint256 blinding
    ) external view returns (bytes memory commitment);

    /// @notice Verify Pedersen commitment opening
    /// @param commitment The commitment to verify
    /// @param value Claimed value
    /// @param blinding Blinding factor used
    /// @return valid True if commitment opens correctly
    function verify(
        bytes calldata commitment,
        uint256 value,
        uint256 blinding
    ) external view returns (bool valid);

    /// @notice Batch Pedersen commitments
    /// @param values Values to commit
    /// @param blindings Blinding factors
    /// @return commitments Array of commitments
    function batchCommit(
        uint256[] calldata values,
        uint256[] calldata blindings
    ) external view returns (bytes[] memory commitments);

    /// @notice Add two commitments homomorphically
    /// @param commitment1 First commitment
    /// @param commitment2 Second commitment
    /// @return sum Commitment to sum of values
    function add(
        bytes calldata commitment1,
        bytes calldata commitment2
    ) external view returns (bytes memory sum);

    /// @notice Subtract commitments homomorphically
    /// @param commitment1 First commitment
    /// @param commitment2 Second commitment
    /// @return diff Commitment to difference
    function sub(
        bytes calldata commitment1,
        bytes calldata commitment2
    ) external view returns (bytes memory diff);

    /// @notice Scalar multiply a commitment
    /// @param commitment Input commitment
    /// @param scalar Scalar multiplier
    /// @return result Commitment to scaled value
    function scalarMul(
        bytes calldata commitment,
        uint256 scalar
    ) external view returns (bytes memory result);
}

// ============================================================================
// HELPER LIBRARY
// ============================================================================

/**
 * @title HashLib
 * @notice Convenience library for hashing operations
 */
library HashLib {
    // Precompile addresses (Lux Hashing range 0xA0XX)
    address constant POSEIDON2 = address(0xA000);
    address constant POSEIDON2_SPONGE = address(0xA001);
    address constant PEDERSEN = address(0xA002);
    address constant BLAKE3 = address(0xA003);

    /// @notice Hash with Blake3 (most efficient for general data)
    function blake3(bytes memory data) internal view returns (bytes32) {
        (bool success, bytes memory result) = BLAKE3.staticcall(
            abi.encodeCall(IBlake3.hash, (data))
        );
        require(success, "Blake3 hash failed");
        return abi.decode(result, (bytes32));
    }

    /// @notice Hash with keyed Blake3 (MAC)
    function blake3Keyed(
        bytes32 key,
        bytes memory data
    ) internal view returns (bytes32) {
        (bool success, bytes memory result) = BLAKE3.staticcall(
            abi.encodeCall(IBlake3.hashKeyed, (key, data))
        );
        require(success, "Blake3 keyed hash failed");
        return abi.decode(result, (bytes32));
    }

    /// @notice Derive key with Blake3
    function blake3DeriveKey(
        string memory context,
        bytes memory material
    ) internal view returns (bytes32) {
        (bool success, bytes memory result) = BLAKE3.staticcall(
            abi.encodeCall(IBlake3.deriveKey, (context, material))
        );
        require(success, "Blake3 key derivation failed");
        return abi.decode(result, (bytes32));
    }

    /// @notice Compute Blake3 merkle root
    function blake3MerkleRoot(
        bytes32[] memory leaves
    ) internal view returns (bytes32) {
        (bool success, bytes memory result) = BLAKE3.staticcall(
            abi.encodeCall(IBlake3.merkleRoot, (leaves))
        );
        require(success, "Blake3 merkle root failed");
        return abi.decode(result, (bytes32));
    }

    /// @notice Hash with Poseidon2 (ZK-friendly)
    function poseidon2(uint256 a, uint256 b) internal view returns (uint256) {
        (bool success, bytes memory result) = POSEIDON2.staticcall(
            abi.encodeCall(IPoseidon2.hash2, (a, b))
        );
        require(success, "Poseidon2 hash failed");
        return abi.decode(result, (uint256));
    }

    /// @notice Hash array with Poseidon2
    function poseidon2Many(
        uint256[] memory inputs
    ) internal view returns (uint256) {
        (bool success, bytes memory result) = POSEIDON2.staticcall(
            abi.encodeCall(IPoseidon2.hashMany, (inputs))
        );
        require(success, "Poseidon2 hash failed");
        return abi.decode(result, (uint256));
    }

    /// @notice Compute Poseidon2 merkle root
    function poseidon2MerkleRoot(
        uint256[] memory leaves
    ) internal view returns (uint256) {
        (bool success, bytes memory result) = POSEIDON2.staticcall(
            abi.encodeCall(IPoseidon2.merkleRoot, (leaves))
        );
        require(success, "Poseidon2 merkle root failed");
        return abi.decode(result, (uint256));
    }

    /// @notice Create Pedersen commitment
    function pedersenCommit(
        uint256 value,
        uint256 blinding
    ) internal view returns (bytes memory) {
        (bool success, bytes memory result) = PEDERSEN.staticcall(
            abi.encodeCall(IPedersen.commit, (value, blinding))
        );
        require(success, "Pedersen commit failed");
        return abi.decode(result, (bytes));
    }

    /// @notice Verify Pedersen commitment
    function pedersenVerify(
        bytes memory commitment,
        uint256 value,
        uint256 blinding
    ) internal view returns (bool) {
        (bool success, bytes memory result) = PEDERSEN.staticcall(
            abi.encodeCall(IPedersen.verify, (commitment, value, blinding))
        );
        return success && abi.decode(result, (bool));
    }

    /// @notice Add two Pedersen commitments (homomorphic)
    function pedersenAdd(
        bytes memory c1,
        bytes memory c2
    ) internal view returns (bytes memory) {
        (bool success, bytes memory result) = PEDERSEN.staticcall(
            abi.encodeCall(IPedersen.add, (c1, c2))
        );
        require(success, "Pedersen add failed");
        return abi.decode(result, (bytes));
    }

    /// @notice Choose hash function based on use case
    /// @dev Returns Blake3 for general data, Poseidon2 for ZK circuits
    function optimalHash(
        bytes memory data,
        bool zkFriendly
    ) internal view returns (bytes32) {
        if (zkFriendly) {
            // Use Poseidon2 for ZK circuits (returns field element)
            (bool success, bytes memory result) = POSEIDON2.staticcall(
                abi.encodeCall(IPoseidon2.hashBytes, (data))
            );
            require(success, "Poseidon2 hash failed");
            return bytes32(abi.decode(result, (uint256)));
        } else {
            // Use Blake3 for general purpose
            return blake3(data);
        }
    }
}

// ============================================================================
// EXAMPLE CONSUMER CONTRACTS
// ============================================================================

/**
 * @title HashConsumer
 * @notice Example contract using hash precompiles
 */
abstract contract HashConsumer {
    using HashLib for *;

    /// @notice Compute content hash
    function computeContentHash(
        bytes calldata content
    ) external view returns (bytes32) {
        return HashLib.blake3(content);
    }

    /// @notice Create authenticated message
    function createMAC(
        bytes32 key,
        bytes calldata message
    ) external view returns (bytes32) {
        return HashLib.blake3Keyed(key, message);
    }

    /// @notice Verify merkle inclusion
    function verifyMerkleProof(
        bytes32 root,
        bytes32 leaf,
        bytes32[] calldata proof,
        uint256 index
    ) external view returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                bytes32[] memory pair = new bytes32[](2);
                pair[0] = computed;
                pair[1] = proof[i];
                computed = HashLib.blake3MerkleRoot(pair);
            } else {
                bytes32[] memory pair = new bytes32[](2);
                pair[0] = proof[i];
                pair[1] = computed;
                computed = HashLib.blake3MerkleRoot(pair);
            }
            index /= 2;
        }
        return computed == root;
    }
}

/**
 * @title ConfidentialBalance
 * @notice Example: Pedersen commitments for hidden balances
 */
abstract contract ConfidentialBalance {
    using HashLib for *;

    mapping(address => bytes) private balanceCommitments;

    /// @notice Set balance commitment
    function setBalance(bytes calldata commitment) external {
        balanceCommitments[msg.sender] = commitment;
    }

    /// @notice Add to balance (homomorphic)
    function addBalance(bytes calldata addCommitment) external {
        bytes memory current = balanceCommitments[msg.sender];
        if (current.length == 0) {
            balanceCommitments[msg.sender] = addCommitment;
        } else {
            balanceCommitments[msg.sender] = HashLib.pedersenAdd(current, addCommitment);
        }
    }

    /// @notice Prove balance is at least amount
    function proveMinBalance(
        uint256 claimedValue,
        uint256 blinding
    ) external view returns (bool) {
        bytes memory commitment = balanceCommitments[msg.sender];
        return HashLib.pedersenVerify(commitment, claimedValue, blinding);
    }
}
