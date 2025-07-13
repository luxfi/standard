// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILux
 * @notice Interface for submitting confidential compute jobs to the Lux Network
 */
interface ILux {
    /// @notice Job status enum
    enum JobStatus {
        PENDING,
        RUNNING,
        COMPLETED,
        FAILED,
        SLASHED
    }

    /// @notice TEE types supported
    enum TeeType {
        SGX,
        TDX,
        SNP,
        GPU
    }

    /// @notice Emitted when a job is submitted
    event JobSubmitted(
        uint256 indexed jobId,
        address indexed submitter,
        bytes32 codeCID,
        uint256 gasLimit
    );

    /// @notice Emitted when a job is completed
    event JobCompleted(
        uint256 indexed jobId,
        address indexed worker,
        bytes32 resultRoot,
        bytes encryptedResult
    );

    /// @notice Emitted when a worker is slashed
    event WorkerSlashed(
        address indexed worker,
        uint256 slashAmount,
        bytes32 fraudProof
    );

    /**
     * @notice Submit a confidential compute job
     * @param target Specific worker address (0 for auto-match)
     * @param codeCID IPFS CID of encrypted code
     * @param payload Encrypted input data
     * @param gasLimit Maximum gas for execution
     * @return jobId Unique job identifier
     */
    function submit(
        address target,
        bytes32 codeCID,
        bytes calldata payload,
        uint256 gasLimit
    ) external payable returns (uint256 jobId);

    /**
     * @notice Get job status and details
     * @param jobId Job identifier
     * @return status Current job status
     * @return submitter Address that submitted the job
     * @return worker Address of assigned worker
     * @return resultRoot Merkle root of execution trace
     */
    function getJob(uint256 jobId) external view returns (
        JobStatus status,
        address submitter,
        address worker,
        bytes32 resultRoot
    );

    /**
     * @notice Register as a worker node
     * @param teeType Type of TEE hardware
     * @param quoteHash Hash of attestation quote
     * @param publicKey Worker's public key for encryption
     */
    function registerWorker(
        TeeType teeType,
        bytes32 quoteHash,
        bytes calldata publicKey
    ) external payable;

    /**
     * @notice Submit job result with attestation
     * @param jobId Job identifier
     * @param result Encrypted result data
     * @param quote TEE attestation quote
     * @param merkleRoot Root of execution trace
     */
    function submitResult(
        uint256 jobId,
        bytes calldata result,
        bytes calldata quote,
        bytes32 merkleRoot
    ) external;

    /**
     * @notice Submit fraud proof to slash a worker
     * @param worker Address of fraudulent worker
     * @param jobId Job where fraud occurred
     * @param proof Cryptographic proof of fraud
     */
    function submitFraudProof(
        address worker,
        uint256 jobId,
        bytes calldata proof
    ) external;
}