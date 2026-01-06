// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ISTARKVerifier.sol";

/*
 * IReceiptRegistry - Z-chain Receipt Registry - core interoperability layer
 * Receipts are the universal proof artifact across all proof systems
 * 
 * Architecture:
 *   Z-chain (zkp_*) maintains the source of truth for all verified proofs.
 *   Receipts are inclusion-proved under roots that can be verified:
 *   - Natively on Lux chains (STARK/Poseidon2 precompiles)
 *   - On external EVMs via Groth16 wrapper proofs
 * 
 * RPC Surface (zkp_*):
 *   zkp_registerProgram  - Register a new program/circuit
 *   zkp_getProgram       - Get program metadata
 *   zkp_submitProof      - Submit proof for verification
 *   zkp_getReceipt       - Get receipt by hash
 *   zkp_getLatestRoot    - Get current receipt tree root
 *   zkp_getInclusionProof - Get Merkle proof for receipt
 * 
 * Proof System IDs:
 *   1 = STARK (transparent, PQ-friendlier)
 *   2 = Groth16 (cheap external EVM verification)
 *   3 = PLONK (universal setup)
 *   4 = Nova/Folding (recursion-native)
 *   5-99 = Reserved production lane
 *   100+ = Research lane (versioned, experimental)
 */

// Proof System Constants
uint32 constant PROOF_SYSTEM_STARK   = 1;
uint32 constant PROOF_SYSTEM_GROTH16 = 2;
uint32 constant PROOF_SYSTEM_PLONK   = 3;
uint32 constant PROOF_SYSTEM_NOVA    = 4;
uint32 constant PROOF_SYSTEM_HALO2   = 5;

// Research lane starts at 100
uint32 constant PROOF_SYSTEM_RESEARCH_MIN = 100;

/**
 * @notice Extended Receipt with inclusion proof data
 */
struct ReceiptWithProof {
    Receipt receipt;
    bytes32[] inclusionProof;
    bytes32 root;
    uint32 rootBlock;
}

/**
 * @notice Program version info for upgrades
 */
struct ProgramVersion {
    bytes32 programId;
    uint32 version;
    bytes32 vkHash;
    uint32 proofSystem;
    uint64 activatedAt;
    bool deprecated;
}

/**
 * @notice Batch verification request
 */
struct BatchVerifyRequest {
    bytes32 programId;
    bytes proof;
    bytes publicInputs;
}

/**
 * @notice Batch verification result
 */
struct BatchVerifyResult {
    bool valid;
    bytes32 receiptHash;
    string errorMessage;
}

/**
 * @title IReceiptRegistry
 * @notice Main Receipt Registry interface for Z-chain
 */
interface IReceiptRegistry {
    // ============ Events ============
    
    event ProgramRegistered(
        bytes32 indexed programId,
        address indexed registrar,
        string name,
        uint32[] proofSystems
    );
    
    event ProgramVersionAdded(
        bytes32 indexed programId,
        uint32 indexed version,
        uint32 proofSystem,
        bytes32 vkHash
    );
    
    event ProgramDeprecated(
        bytes32 indexed programId,
        uint32 indexed version
    );
    
    event ProofSubmitted(
        bytes32 indexed receiptHash,
        bytes32 indexed programId,
        bytes32 indexed claimHash,
        uint32 proofSystem
    );
    
    event RootUpdated(
        bytes32 indexed newRoot,
        bytes32 indexed previousRoot,
        uint32 blockNumber,
        uint256 receiptCount
    );
    
    event AggregationCreated(
        bytes32 indexed aggregationRoot,
        bytes32[] receiptHashes,
        uint256 count
    );

    // ============ Program Registry ============
    
    /// @notice Register a new program
    /// @param name Human-readable program name
    /// @param codeHash Hash of program bytecode
    /// @param proofSystems Supported proof systems
    /// @param vkHashes Verification key hashes per system
    /// @return programId Unique program identifier
    function registerProgram(
        string calldata name,
        bytes32 codeHash,
        uint32[] calldata proofSystems,
        bytes32[] calldata vkHashes
    ) external returns (bytes32 programId);
    
    /// @notice Add new version to existing program
    /// @param programId Program to update
    /// @param version New version number
    /// @param proofSystem Proof system for this version
    /// @param vkHash Verification key hash
    function addProgramVersion(
        bytes32 programId,
        uint32 version,
        uint32 proofSystem,
        bytes32 vkHash
    ) external;
    
    /// @notice Deprecate a program version
    /// @param programId Program to deprecate
    /// @param version Version to deprecate
    function deprecateVersion(
        bytes32 programId,
        uint32 version
    ) external;
    
    /// @notice Get program metadata
    /// @param programId Program identifier
    /// @return program Program data
    function getProgram(bytes32 programId) external view returns (Program memory program);
    
    /// @notice Get specific program version
    /// @param programId Program identifier
    /// @param version Version number
    /// @return versionInfo Version metadata
    function getProgramVersion(
        bytes32 programId,
        uint32 version
    ) external view returns (ProgramVersion memory versionInfo);
    
    /// @notice Check if program exists
    /// @param programId Program identifier
    /// @return exists True if registered
    function programExists(bytes32 programId) external view returns (bool exists);

    // ============ Proof Submission ============
    
    /// @notice Submit a proof for verification
    /// @param programId Program identifier
    /// @param proofSystem Proof system used
    /// @param proof Serialized proof
    /// @param publicInputs Public inputs
    /// @return receiptHash Hash of created receipt
    function submitProof(
        bytes32 programId,
        uint32 proofSystem,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external returns (bytes32 receiptHash);
    
    /// @notice Submit multiple proofs in batch
    /// @param requests Array of verification requests
    /// @return results Array of verification results
    function submitBatch(
        BatchVerifyRequest[] calldata requests
    ) external returns (BatchVerifyResult[] memory results);
    
    /// @notice Submit recursive/aggregated proof
    /// @param parentReceipts Receipts being aggregated
    /// @param aggregationProof Proof of valid aggregation
    /// @return aggregationRoot Root of aggregated receipts
    function submitAggregation(
        bytes32[] calldata parentReceipts,
        bytes calldata aggregationProof
    ) external returns (bytes32 aggregationRoot);

    // ============ Receipt Queries ============
    
    /// @notice Get receipt by hash
    /// @param receiptHash Receipt identifier
    /// @return receipt Receipt data
    function getReceipt(bytes32 receiptHash) external view returns (Receipt memory receipt);
    
    /// @notice Get receipt with inclusion proof
    /// @param receiptHash Receipt identifier
    /// @return data Receipt with proof data
    function getReceiptWithProof(
        bytes32 receiptHash
    ) external view returns (ReceiptWithProof memory data);
    
    /// @notice Check if receipt exists
    /// @param receiptHash Receipt identifier
    /// @return exists True if receipt exists
    function receiptExists(bytes32 receiptHash) external view returns (bool exists);
    
    /// @notice Get receipts for a program
    /// @param programId Program identifier
    /// @param offset Pagination offset
    /// @param limit Max results
    /// @return receiptHashes Array of receipt hashes
    function getReceiptsByProgram(
        bytes32 programId,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory receiptHashes);

    // ============ Root Management ============
    
    /// @notice Get current receipt tree root
    /// @return root Latest Merkle root
    function getLatestRoot() external view returns (bytes32 root);
    
    /// @notice Get root at specific block
    /// @param blockNumber Block to query
    /// @return root Root at that block
    function getRootAtBlock(uint32 blockNumber) external view returns (bytes32 root);
    
    /// @notice Get inclusion proof for receipt
    /// @param receiptHash Receipt to prove
    /// @return proof Merkle inclusion proof
    /// @return root Root against which to verify
    function getInclusionProof(
        bytes32 receiptHash
    ) external view returns (bytes32[] memory proof, bytes32 root);
    
    /// @notice Verify inclusion proof
    /// @param receiptHash Receipt hash
    /// @param proof Merkle proof
    /// @param root Expected root
    /// @return valid True if proof is valid
    function verifyInclusion(
        bytes32 receiptHash,
        bytes32[] calldata proof,
        bytes32 root
    ) external view returns (bool valid);
    
    /// @notice Check if root is known/valid
    /// @param root Root to check
    /// @return known True if root exists
    function isKnownRoot(bytes32 root) external view returns (bool known);

    // ============ Cross-Chain Export ============
    
    /// @notice Export receipt for external chain verification
    /// @param receiptHash Receipt to export
    /// @param targetProofSystem Target proof system (e.g., Groth16 for EVM)
    /// @return proof Proof in target format
    function exportReceipt(
        bytes32 receiptHash,
        uint32 targetProofSystem
    ) external view returns (bytes memory proof);
    
    /// @notice Get Groth16 proof for external EVM chains
    /// @param receiptHash Receipt to prove
    /// @return groth16Proof Groth16-formatted proof
    /// @return publicInputs Public inputs for verification
    function getGroth16Proof(
        bytes32 receiptHash
    ) external view returns (bytes memory groth16Proof, bytes memory publicInputs);

    // ============ Statistics ============
    
    /// @notice Get total receipt count
    /// @return count Number of receipts
    function getReceiptCount() external view returns (uint256 count);
    
    /// @notice Get total program count
    /// @return count Number of programs
    function getProgramCount() external view returns (uint256 count);
}

/**
 * @title IReceiptVerifier
 * @notice Interface for verifying receipts on any chain
 * @dev Can be implemented by:
 *   - Native precompile on Lux chains
 *   - Smart contract on external EVMs
 */
interface IReceiptVerifier {
    /// @notice Verify a receipt inclusion proof
    /// @param receiptHash Receipt identifier
    /// @param proof Merkle inclusion proof
    /// @param root Expected root (must be published/known)
    /// @return valid True if receipt is valid
    function verifyReceipt(
        bytes32 receiptHash,
        bytes32[] calldata proof,
        bytes32 root
    ) external view returns (bool valid);
    
    /// @notice Verify using Groth16 proof (for external EVMs)
    /// @param proof Groth16 proof
    /// @param publicInputs Public inputs
    /// @return valid True if proof is valid
    function verifyGroth16(
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view returns (bool valid);
}
