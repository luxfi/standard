// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRangeProofVerifier
 * @notice Interface for Bulletproof range proof verification
 * @dev Verifies that committed values are within specified ranges without revealing them
 * 
 * Range proofs ensure:
 * 1. Amount is non-negative (≥ 0)
 * 2. Amount is bounded (< 2^64 for practical purposes)
 * 3. Commitment matches the proven value
 * 
 * Uses BN254 precompiles (0x06, 0x07, 0x08) for efficient verification
 */
interface IRangeProofVerifier {
    /// @notice Bulletproof proof structure
    struct BulletproofProof {
        bytes32 A;           // Commitment to aL, aR
        bytes32 S;           // Commitment to sL, sR
        bytes32 T1;          // Commitment to t1
        bytes32 T2;          // Commitment to t2
        uint256 taux;        // Blinding factor for t
        uint256 mu;          // Blinding factor for A, S
        uint256 t;           // Polynomial evaluation
        bytes L;             // Left points (log n)
        bytes R;             // Right points (log n)
        uint256 a;           // Final scalar a
        uint256 b;           // Final scalar b
    }

    /// @notice Aggregate proof for multiple values
    struct AggregateProof {
        bytes32[] commitments;  // Multiple Pedersen commitments
        BulletproofProof proof; // Single aggregate proof
        uint8 numValues;        // Number of values in aggregate
    }

    /// @notice Verify a single range proof
    /// @param commitment The Pedersen commitment (C = vG + rH)
    /// @param proof The Bulletproof proof
    /// @param bitLength The maximum bit length (e.g., 64 for values < 2^64)
    /// @return True if the proof is valid
    function verifySingle(
        bytes32 commitment,
        BulletproofProof calldata proof,
        uint8 bitLength
    ) external view returns (bool);

    /// @notice Verify an aggregate range proof for multiple values
    /// @param aggProof The aggregate proof structure
    /// @param bitLength The maximum bit length per value
    /// @return True if all values are in range
    function verifyAggregate(
        AggregateProof calldata aggProof,
        uint8 bitLength
    ) external view returns (bool);

    /// @notice Verify a range proof with custom bounds
    /// @param commitment The commitment to verify
    /// @param proof The proof data
    /// @param minValue Minimum allowed value
    /// @param maxValue Maximum allowed value
    /// @return True if value is in [minValue, maxValue]
    function verifyCustomRange(
        bytes32 commitment,
        bytes calldata proof,
        uint256 minValue,
        uint256 maxValue
    ) external view returns (bool);

    /// @notice Get generator points for the proof system
    /// @return G Base point
    /// @return H Blinding point
    function getGenerators() external view returns (bytes32 G, bytes32 H);

    /// @notice Compute Pedersen commitment off-chain helper
    /// @param value The value to commit
    /// @param blinding The blinding factor
    /// @return The commitment
    function computeCommitment(
        uint256 value,
        uint256 blinding
    ) external view returns (bytes32);
}
