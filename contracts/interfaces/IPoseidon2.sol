// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPoseidon2
 * @notice Interface for Poseidon2 hash precompile at 0x0501
 * @dev Poseidon2 is a ZK-friendly hash function that is:
 *      - Post-quantum secure (hash-based security, not discrete log)
 *      - Optimized for STARK/SNARK circuits
 *      - ~2000x faster than Pedersen commitments in circuits
 *      - Uses BN254 scalar field (same as zkSNARK circuits)
 * 
 * Gas costs:
 *   - Hash (1-4 elements): 800 gas
 *   - Hash (5-8 elements): 1,200 gas
 *   - Hash (9-16 elements): 2,000 gas
 *   - NoteCommitment: 800 gas
 *   - NullifierHash: 800 gas
 *   - MerkleRoot: 400 gas per level
 */
interface IPoseidon2 {
    /// @notice Hash multiple field elements
    /// @param inputs Concatenated 32-byte field elements (1-16 elements)
    /// @return result 32-byte Poseidon2 hash
    function hash(bytes calldata inputs) external view returns (bytes32 result);

    /// @notice Hash two field elements (Merkle tree pair)
    /// @param left Left child hash
    /// @param right Right child hash
    /// @return result Parent hash
    function hashPair(bytes32 left, bytes32 right) external view returns (bytes32 result);

    /// @notice Compute note commitment: H(amount || assetId || owner || blindingFactor)
    /// @param amount Token amount (will be converted to field element)
    /// @param assetId Asset identifier hash
    /// @param owner Owner address (padded to 32 bytes)
    /// @param blindingFactor Random blinding factor for hiding
    /// @return commitment Note commitment hash
    function noteCommitment(
        uint256 amount,
        bytes32 assetId,
        address owner,
        bytes32 blindingFactor
    ) external view returns (bytes32 commitment);

    /// @notice Compute nullifier hash: H(commitment || secret)
    /// @param commitment Note commitment being spent
    /// @param secret Owner's secret key
    /// @return nullifier Unique identifier for spent note
    function nullifierHash(
        bytes32 commitment,
        bytes32 secret
    ) external view returns (bytes32 nullifier);

    /// @notice Compute Merkle root from leaf and proof
    /// @param leaf Leaf commitment
    /// @param proof Merkle proof path (sibling hashes)
    /// @param index Position of leaf in tree
    /// @return root Computed Merkle root
    function merkleRoot(
        bytes32 leaf,
        bytes32[] calldata proof,
        uint256 index
    ) external view returns (bytes32 root);
}

/**
 * @title Poseidon2
 * @notice Library for calling Poseidon2 precompile
 */
library Poseidon2 {
    /// @dev Poseidon2 precompile address
    address constant PRECOMPILE = address(0x0501);

    /// @notice Hash arbitrary data using Poseidon2
    function hash(bytes memory data) internal view returns (bytes32 result) {
        (bool success, bytes memory output) = PRECOMPILE.staticcall(
            abi.encodePacked(uint8(0x01), data) // 0x01 = HASH opcode
        );
        require(success, "Poseidon2: hash failed");
        result = abi.decode(output, (bytes32));
    }

    /// @notice Hash two values (Merkle pair)
    function hashPair(bytes32 left, bytes32 right) internal view returns (bytes32 result) {
        (bool success, bytes memory output) = PRECOMPILE.staticcall(
            abi.encodePacked(uint8(0x02), left, right) // 0x02 = HASH_PAIR opcode
        );
        require(success, "Poseidon2: hashPair failed");
        result = abi.decode(output, (bytes32));
    }

    /// @notice Compute note commitment
    function noteCommitment(
        uint256 amount,
        bytes32 assetId,
        address owner,
        bytes32 blindingFactor
    ) internal view returns (bytes32 commitment) {
        (bool success, bytes memory output) = PRECOMPILE.staticcall(
            abi.encodePacked(
                uint8(0x03), // NOTE_COMMITMENT opcode
                amount,
                assetId,
                bytes32(uint256(uint160(owner))),
                blindingFactor
            )
        );
        require(success, "Poseidon2: noteCommitment failed");
        commitment = abi.decode(output, (bytes32));
    }

    /// @notice Compute nullifier for spending a note
    function nullifierHash(
        bytes32 commitment,
        bytes32 secret
    ) internal view returns (bytes32 nullifier) {
        (bool success, bytes memory output) = PRECOMPILE.staticcall(
            abi.encodePacked(
                uint8(0x04), // NULLIFIER_HASH opcode
                commitment,
                secret
            )
        );
        require(success, "Poseidon2: nullifierHash failed");
        nullifier = abi.decode(output, (bytes32));
    }

    /// @notice Compute Merkle root
    function merkleRoot(
        bytes32 leaf,
        bytes32[] memory proof,
        uint256 index
    ) internal view returns (bytes32 root) {
        root = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                root = hashPair(root, proof[i]);
            } else {
                root = hashPair(proof[i], root);
            }
            index = index / 2;
        }
    }

    /// @notice Fallback using keccak256 if precompile unavailable
    /// @dev Used for testing on chains without the precompile
    function hashFallback(bytes memory data) internal pure returns (bytes32) {
        return keccak256(data);
    }

    /// @notice Check if precompile is available
    function isPrecompileAvailable() internal view returns (bool) {
        (bool success, ) = PRECOMPILE.staticcall(abi.encodePacked(uint8(0x00))); // 0x00 = STATUS
        return success;
    }
}
