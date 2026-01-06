// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Production lane - stable addresses
address constant STARK_FIELD_ARITH   = address(0x0510);  // Goldilocks field arithmetic
address constant STARK_EXT_ARITH     = address(0x0511);  // Extension field (Fp2)
address constant STARK_POSEIDON2     = address(0x0512);  // Poseidon2 over Goldilocks
address constant STARK_FRI_FOLD      = address(0x0513);  // FRI folding operation
address constant STARK_MERKLE        = address(0x0514);  // Merkle tree verify
address constant STARK_VERIFY        = address(0x051F);  // Full STARK verification

// Research lane - versioned experimental addresses (0x0580+)
// address constant STARK_RESEARCH_V1  = address(0x0580);

/*
 * ISTARKVerifier - Interface for STARK verification precompiles (0x0510-0x051F)
 * Part of the "Cryptographic ISA" - stable production lane
 * 
 * Architecture:
 *   Production Lane: Stable precompiles, never break compatibility
 *   Research Lane: Versioned experimental precompiles (0x0580+)
 * 
 * STARK verification flow:
 *   1. Verify FRI commitment queries (polynomial commitment)
 *   2. Verify constraint polynomial evaluations
 *   3. Verify AIR (Algebraic Intermediate Representation)
 *   4. Produce a Receipt for the verified statement
 * 
 * Gas model (Goldilocks field, 128-bit security):
 *   - Field add: 8 gas
 *   - Field mul: 15 gas  
 *   - Field inv: 800 gas
 *   - Poseidon2 hash: 800 gas
 *   - FRI fold: 2,000 gas per layer
 *   - Full STARK verify: ~100,000-500,000 gas (depends on proof size)
 */

/**
 * @notice Universal Receipt format
 * @dev Core interoperability object across all proof systems
 * 
 * Receipt flow:
 *   1. Proof verified on Z-chain → Receipt created
 *   2. Receipt added to ReceiptRegistry → Merkle root updated
 *   3. Inclusion proof generated for external chains
 *   4. External chain verifies inclusion (or Groth16 wrapper)
 */
struct Receipt {
    // Core fields
    bytes32 programId;       // Hash of the verified program/circuit
    bytes32 claimHash;       // Hash of the public inputs (statement)
    bytes32 receiptHash;     // Self-referential hash of this receipt
    
    // Verification metadata
    uint32 proofSystemId;    // 1=STARK, 2=Groth16, 3=PLONK, 4=Nova, ...
    uint32 version;          // Version of proof system
    uint64 verifiedAt;       // Block timestamp
    uint32 verifiedBlock;    // Block number
    
    // Optional: for aggregation/recursion
    bytes32 parentReceipt;   // 0x0 if not recursive
    bytes32 aggregationRoot; // For batch receipts
}

/**
 * @notice Program registration for the Z-chain registry
 */
struct Program {
    bytes32 programId;       // Unique program identifier
    bytes32 codeHash;        // Hash of program bytecode
    bytes32 vkCommitment;    // Commitment to verification key (if applicable)
    
    // Verification methods (can support multiple)
    uint32[] proofSystems;   // Supported proof systems
    bytes32[] vkHashes;      // VK hashes per proof system
    
    // Metadata
    string name;             // Human-readable name
    string version;          // Semantic version
    uint64 registeredAt;     // Registration timestamp
    address registrar;       // Who registered it
}

/**
 * @notice FRI (Fast Reed-Solomon IOP) verification parameters
 */
struct FRIParams {
    uint8 numQueries;        // Number of FRI queries
    uint8 blowupFactor;      // LDE blowup factor (usually 8 or 16)
    uint8 numLayers;         // Number of FRI layers
    bytes32 domainSeparator; // Domain separator for Fiat-Shamir
}

/**
 * @notice STARK proof structure for verification
 */
struct STARKProof {
    // Commitment phase
    bytes32 traceCommitment;      // Merkle root of trace columns
    bytes32 constraintCommitment; // Merkle root of constraint polys
    
    // FRI layers
    bytes32[] friCommitments;     // FRI layer commitments
    bytes32[][] friQueries;       // Query responses per layer
    bytes32[][] friPaths;         // Merkle paths for queries
    
    // Final values
    uint256[] finalPoly;          // Final polynomial coefficients
    
    // Public inputs
    bytes publicInputs;           // Serialized public inputs
}

/**
 * @title ISTARKVerifier
 * @notice Main STARK verification interface
 */
interface ISTARKVerifier {
    // ============ Events ============
    
    event ProofVerified(
        bytes32 indexed programId,
        bytes32 indexed claimHash,
        bytes32 indexed receiptHash,
        uint32 proofSystem,
        uint64 timestamp
    );
    
    event ReceiptCreated(
        bytes32 indexed receiptHash,
        bytes32 indexed rootBefore,
        bytes32 indexed rootAfter
    );

    // ============ Verification Functions ============
    
    /// @notice Verify a STARK proof
    /// @param programId Registered program identifier
    /// @param proof Serialized STARK proof
    /// @param publicInputs Public inputs to the program
    /// @return valid True if proof is valid
    /// @return receipt The generated receipt (if valid)
    function verifySTARK(
        bytes32 programId,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external returns (bool valid, Receipt memory receipt);

    /// @notice Verify and create receipt in registry
    /// @param programId Registered program identifier  
    /// @param proof Serialized proof
    /// @param publicInputs Public inputs
    /// @return receiptHash Hash of the created receipt
    function verifyAndCreateReceipt(
        bytes32 programId,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external returns (bytes32 receiptHash);

    /// @notice Verify a spend proof (privacy-specific)
    /// @param nullifier Nullifier being spent
    /// @param merkleRoot Expected Merkle root
    /// @param merkleProof Merkle inclusion path
    /// @param starkProof STARK proof of valid spend
    /// @return valid True if spend is valid
    function verifySpend(
        bytes32 nullifier,
        bytes32 merkleRoot,
        bytes32[] calldata merkleProof,
        bytes calldata starkProof
    ) external view returns (bool valid);

    // ============ FRI Verification ============
    
    /// @notice Verify FRI commitment
    /// @param params FRI parameters
    /// @param commitment Polynomial commitment
    /// @param queries Query indices and values
    /// @return valid True if FRI is valid
    function verifyFRI(
        FRIParams calldata params,
        bytes32 commitment,
        bytes calldata queries
    ) external view returns (bool valid);

    /// @notice Perform single FRI fold
    /// @param layer Current layer values
    /// @param challenge Random challenge
    /// @return folded Folded values
    function friFold(
        uint256[] calldata layer,
        uint256 challenge
    ) external view returns (uint256[] memory folded);

    // ============ Field Operations ============
    
    /// @notice Goldilocks field addition
    /// @param a First operand
    /// @param b Second operand
    /// @return result a + b mod p
    function fieldAdd(uint64 a, uint64 b) external pure returns (uint64 result);

    /// @notice Goldilocks field multiplication
    /// @param a First operand
    /// @param b Second operand
    /// @return result a * b mod p
    function fieldMul(uint64 a, uint64 b) external pure returns (uint64 result);

    /// @notice Goldilocks field inversion
    /// @param a Operand
    /// @return result a^(-1) mod p
    function fieldInv(uint64 a) external pure returns (uint64 result);

    // ============ Registry Queries ============
    
    /// @notice Get current receipt tree root
    /// @return root Latest Merkle root of receipts
    function getLatestRoot() external view returns (bytes32 root);

    /// @notice Get historical root at block
    /// @param blockNumber Block to query
    /// @return root Root at that block
    function getRootAtBlock(uint32 blockNumber) external view returns (bytes32 root);

    /// @notice Get a receipt by hash
    /// @param receiptHash Receipt identifier
    /// @return receipt The receipt data
    function getReceipt(bytes32 receiptHash) external view returns (Receipt memory receipt);

    /// @notice Get inclusion proof for a receipt
    /// @param receiptHash Receipt to prove
    /// @return proof Merkle inclusion proof
    /// @return root Root against which to verify
    function getInclusionProof(
        bytes32 receiptHash
    ) external view returns (bytes32[] memory proof, bytes32 root);
}

/**
 * @title STARKLib
 * @notice Library for calling STARK precompiles
 */
library STARKLib {
    /// @dev Goldilocks prime: p = 2^64 - 2^32 + 1
    uint64 constant GOLDILOCKS_PRIME = 18446744069414584321;

    /// @notice Call the STARK verification precompile
    function verify(
        bytes32 programId,
        bytes memory proof,
        bytes memory publicInputs
    ) internal view returns (bool valid, bytes32 receiptHash) {
        (bool success, bytes memory result) = STARK_VERIFY.staticcall(
            abi.encode(programId, proof, publicInputs)
        );
        if (!success || result.length < 64) {
            return (false, bytes32(0));
        }
        (valid, receiptHash) = abi.decode(result, (bool, bytes32));
    }

    /// @notice Call field arithmetic precompile
    function fieldOp(uint8 op, uint64 a, uint64 b) internal view returns (uint64 result) {
        (bool success, bytes memory output) = STARK_FIELD_ARITH.staticcall(
            abi.encodePacked(op, a, b)
        );
        require(success, "STARKLib: field op failed");
        result = abi.decode(output, (uint64));
    }

    /// @notice Call FRI fold precompile
    function friFold(
        uint256[] memory layer,
        uint256 challenge
    ) internal view returns (uint256[] memory folded) {
        (bool success, bytes memory output) = STARK_FRI_FOLD.staticcall(
            abi.encode(layer, challenge)
        );
        require(success, "STARKLib: FRI fold failed");
        folded = abi.decode(output, (uint256[]));
    }

    /// @notice Verify Merkle path using STARK precompile
    function verifyMerkle(
        bytes32 root,
        bytes32 leaf,
        bytes32[] memory path,
        uint256 index
    ) internal view returns (bool valid) {
        (bool success, bytes memory output) = STARK_MERKLE.staticcall(
            abi.encode(root, leaf, path, index)
        );
        if (!success || output.length == 0) return false;
        valid = abi.decode(output, (bool));
    }

    /// @notice Check if precompiles are available
    function isAvailable() internal view returns (bool) {
        (bool success, ) = STARK_VERIFY.staticcall(abi.encodePacked(uint8(0xFF))); // STATUS
        return success;
    }
}
