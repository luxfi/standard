// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPoseidon2.sol";

/**
 * @title Poseidon2Commitments
 * @notice Library for creating and verifying Poseidon2-based commitments
 * @dev Implements UTXO-style note commitments using Poseidon2 hash function
 * 
 * Key advantages over Pedersen:
 * - Post-quantum secure (hash-based, not discrete log)
 * - ~2000x faster in ZK circuits
 * - 7.5x cheaper gas (800 vs 6000)
 * - Native compatibility with STARK proofs
 * 
 * Commitment scheme:
 *   commitment = Poseidon2(amount || assetId || owner || blindingFactor)
 *   nullifier = Poseidon2(commitment || ownerSecret)
 *   
 * This differs from Pedersen where:
 *   commitment = amount * G + blindingFactor * H
 * 
 * Poseidon2 commitments are:
 * - Binding: Cannot find two different (value, blinding) pairs with same commitment
 * - Hiding: Commitment reveals nothing about value (with random blinding)
 * - But NOT homomorphic: Cannot add commitments directly
 * 
 * For range proofs and balance verification, use STARK/SNARK proofs
 * with arithmetic constraints instead of relying on homomorphism.
 */
library Poseidon2Commitments {
    using Poseidon2 for *;

    /// @notice Note structure for private transactions
    struct Note {
        bytes32 commitment;      // Poseidon2 commitment
        bytes32 assetId;         // Token/asset identifier
        bytes encryptedData;     // FHE-encrypted (amount, owner)
        uint64 createdBlock;     // Block when created
    }

    /// @notice Commitment input parameters
    struct CommitmentInput {
        uint256 amount;          // Token amount
        bytes32 assetId;         // Asset identifier
        address owner;           // Owner address
        bytes32 blindingFactor;  // Random blinding factor
    }

    /// @notice Spend proof for a note
    struct SpendProof {
        bytes32 nullifier;       // Nullifier to prevent double-spending
        bytes32 merkleRoot;      // Root of the commitment tree
        bytes32[] merkleProof;   // Merkle path to the note
        bytes starkProof;        // STARK proof of valid spend
    }

    /// @dev Flag to use fallback (keccak256) when precompile unavailable
    bool private constant USE_FALLBACK = false;

    /// @notice Create a note commitment
    /// @param input Commitment input parameters
    /// @return commitment The Poseidon2 commitment
    function createCommitment(
        CommitmentInput memory input
    ) internal view returns (bytes32 commitment) {
        if (_usePrecompile()) {
            commitment = Poseidon2.noteCommitment(
                input.amount,
                input.assetId,
                input.owner,
                input.blindingFactor
            );
        } else {
            // Fallback for testing on chains without precompile
            commitment = keccak256(abi.encodePacked(
                input.amount,
                input.assetId,
                input.owner,
                input.blindingFactor
            ));
        }
    }

    /// @notice Compute nullifier for spending a note
    /// @param commitment Note commitment being spent
    /// @param ownerSecret Owner's spending secret
    /// @return nullifier Unique spending identifier
    function computeNullifier(
        bytes32 commitment,
        bytes32 ownerSecret
    ) internal view returns (bytes32 nullifier) {
        if (_usePrecompile()) {
            nullifier = Poseidon2.nullifierHash(commitment, ownerSecret);
        } else {
            nullifier = keccak256(abi.encodePacked(commitment, ownerSecret));
        }
    }

    /// @notice Hash two nodes in Merkle tree
    /// @param left Left child
    /// @param right Right child
    /// @return parent Parent hash
    function merkleHash(
        bytes32 left,
        bytes32 right
    ) internal view returns (bytes32 parent) {
        if (_usePrecompile()) {
            parent = Poseidon2.hashPair(left, right);
        } else {
            parent = keccak256(abi.encodePacked(left, right));
        }
    }

    /// @notice Compute Merkle root from leaf and proof
    /// @param leaf Leaf commitment
    /// @param proof Merkle proof path
    /// @param index Leaf index in tree
    /// @return root Computed root
    function computeMerkleRoot(
        bytes32 leaf,
        bytes32[] memory proof,
        uint256 index
    ) internal view returns (bytes32 root) {
        if (_usePrecompile()) {
            root = Poseidon2.merkleRoot(leaf, proof, index);
        } else {
            root = leaf;
            for (uint256 i = 0; i < proof.length; i++) {
                if (index % 2 == 0) {
                    root = keccak256(abi.encodePacked(root, proof[i]));
                } else {
                    root = keccak256(abi.encodePacked(proof[i], root));
                }
                index = index / 2;
            }
        }
    }

    /// @notice Verify a Merkle proof
    /// @param root Expected root
    /// @param leaf Leaf commitment
    /// @param proof Merkle proof path
    /// @param index Leaf index
    /// @return valid True if proof is valid
    function verifyMerkleProof(
        bytes32 root,
        bytes32 leaf,
        bytes32[] memory proof,
        uint256 index
    ) internal view returns (bool valid) {
        return computeMerkleRoot(leaf, proof, index) == root;
    }

    /// @notice Initialize zero values for sparse Merkle tree
    /// @param depth Tree depth
    /// @return zeros Array of zero values at each level
    function initZeros(uint256 depth) internal view returns (bytes32[] memory zeros) {
        zeros = new bytes32[](depth);
        zeros[0] = bytes32(0);
        
        for (uint256 i = 1; i < depth; i++) {
            zeros[i] = merkleHash(zeros[i-1], zeros[i-1]);
        }
    }

    /// @notice Generate commitment parameters (for client-side use)
    /// @param amount Token amount
    /// @param assetId Asset identifier
    /// @param owner Owner address
    /// @return input Commitment input with random blinding factor
    /// @dev In production, blinding factor should be generated securely off-chain
    function prepareCommitment(
        uint256 amount,
        bytes32 assetId,
        address owner
    ) internal view returns (CommitmentInput memory input) {
        // WARNING: This is for testing only!
        // In production, use proper randomness from client side
        bytes32 blindingFactor = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            amount,
            assetId
        ));
        
        input = CommitmentInput({
            amount: amount,
            assetId: assetId,
            owner: owner,
            blindingFactor: blindingFactor
        });
    }

    /// @notice Check if Poseidon2 precompile is available
    function _usePrecompile() private view returns (bool) {
        if (USE_FALLBACK) return false;
        return Poseidon2.isPrecompileAvailable();
    }
}
