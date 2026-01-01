// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {Transaction} from "@luxfi/contracts/governance/base/Transaction.sol";

/**
 * @title IGovernor
 * @author Lux Industries Inc
 * @notice Central governance module for DAOs using the Lux Protocol
 * @dev This module serves as the core governance system that manages proposals and executes
 * transactions through a Gnosis Safe. It acts as a modular controller, enabling flexible
 * governance with support for various voting strategies and token standards.
 *
 * Key features:
 * - Proposal submission with customizable proposer adapters
 * - Flexible voting through a delegated strategy contract
 * - Timelock mechanism for security
 * - Execution period constraints
 * - Safe integration for transaction execution
 *
 * The module delegates voting logic to a Strategy contract, allowing DAOs to
 * customize their voting mechanisms without modifying the core governance module.
 *
 * Integration requirements:
 * - Must be enabled as a module on the target Safe
 * - Requires a valid Strategy contract for voting
 * - Supports various proposer adapters for access control
 */
interface IGovernor {
    // --- Errors ---

    /** @notice Thrown when attempting to set a zero address as the strategy */
    error InvalidStrategy();

    /** @notice Thrown when attempting to access a proposal that doesn't exist */
    error InvalidProposal();

    /** @notice Thrown when the proposer adapter rejects the proposal submission */
    error InvalidProposer();

    /** @notice Thrown when attempting to execute a proposal that is not EXECUTABLE */
    error ProposalNotExecutable();

    /** @notice Thrown when transaction details don't match the stored hash */
    error InvalidTxHash();

    /** @notice Thrown when a transaction execution fails */
    error TxFailed();

    /** @notice Thrown when executing with an empty transactions array */
    error InvalidTxs();

    // --- Structs ---

    /**
     * @notice Stores all data associated with a proposal
     * @dev Proposals are immutable once created
     * @param executionCounter Tracks executed transactions (enables partial execution)
     * @param timelockPeriod Time delay after voting before execution
     * @param executionPeriod Duration after timelock when execution is allowed
     * @param strategy The voting strategy for this proposal
     * @param txHashes Array of transaction hashes in the proposal
     */
    struct Proposal {
        uint32 executionCounter;
        uint32 timelockPeriod;
        uint32 executionPeriod;
        address strategy;
        bytes32[] txHashes;
    }

    // --- Enums ---

    /**
     * @notice Proposal lifecycle states
     * @dev State transitions:
     * - ACTIVE → FAILED (if voting fails) or TIMELOCKED (if voting passes)
     * - TIMELOCKED → EXECUTABLE (after timelock expires)
     * - EXECUTABLE → EXECUTED (all txs done) or EXPIRED (window passed)
     */
    enum ProposalState {
        ACTIVE,
        TIMELOCKED,
        EXECUTABLE,
        EXECUTED,
        EXPIRED,
        FAILED
    }

    // --- Events ---

    /**
     * @notice Emitted when a new proposal is created
     * @param strategy The voting strategy for this proposal
     * @param proposalId The unique proposal identifier
     * @param proposer The address that submitted the proposal
     * @param transactions Transactions to execute if passed
     * @param metadata IPFS hash or other metadata
     */
    event ProposalCreated(
        address strategy,
        uint32 proposalId,
        address proposer,
        Transaction[] transactions,
        string metadata
    );

    /**
     * @notice Emitted when proposal transactions are executed
     * @param proposalId The executed proposal ID
     * @param txHashes Transaction hashes that were executed
     */
    event ProposalExecuted(uint32 proposalId, bytes32[] txHashes);

    /**
     * @notice Emitted when timelock period is updated
     * @param timelockPeriod New timelock period in seconds
     */
    event TimelockPeriodUpdated(uint32 timelockPeriod);

    /**
     * @notice Emitted when execution period is updated
     * @param executionPeriod New execution period in seconds
     */
    event ExecutionPeriodUpdated(uint32 executionPeriod);

    /**
     * @notice Emitted when strategy is updated
     * @param strategy New strategy address
     */
    event StrategyUpdated(address strategy);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the governance module
     * @param owner_ The owner address
     * @param vault_ The Safe/vault address (was avatar)
     * @param target_ The target for transactions (usually same as vault)
     * @param strategy_ The initial voting strategy
     * @param timelockPeriod_ Initial timelock in seconds
     * @param executionPeriod_ Initial execution window in seconds
     */
    function initialize(
        address owner_,
        address vault_,
        address target_,
        address strategy_,
        uint32 timelockPeriod_,
        uint32 executionPeriod_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns total proposals created
     * @return Total number of proposals
     */
    function totalProposalCount() external view returns (uint32);

    /**
     * @notice Returns the default timelock period
     * @return Timelock period in seconds
     */
    function timelockPeriod() external view returns (uint32);

    /**
     * @notice Returns the default execution period
     * @return Execution period in seconds
     */
    function executionPeriod() external view returns (uint32);

    /**
     * @notice Returns proposal data
     * @param proposalId_ The proposal ID
     * @return The proposal struct
     */
    function proposals(uint32 proposalId_) external view returns (Proposal memory);

    /**
     * @notice Returns the default strategy
     * @return Strategy contract address
     */
    function strategy() external view returns (address);

    /**
     * @notice Returns the current state of a proposal
     * @param proposalId_ The proposal ID
     * @return The proposal state
     */
    function proposalState(uint32 proposalId_) external view returns (ProposalState);

    /**
     * @notice Generates data for transaction hashing
     * @param transaction_ The transaction
     * @param nonce_ A nonce value
     * @return The encoded hash data
     */
    function generateTxHashData(
        Transaction calldata transaction_,
        uint256 nonce_
    ) external view returns (bytes memory);

    /**
     * @notice Computes the hash for a transaction
     * @param transaction_ The transaction
     * @return The transaction hash
     */
    function getTxHash(Transaction calldata transaction_) external view returns (bytes32);

    /**
     * @notice Returns a transaction hash from a proposal
     * @param proposalId_ The proposal ID
     * @param txIndex_ The transaction index
     * @return The transaction hash
     */
    function getProposalTxHash(
        uint32 proposalId_,
        uint32 txIndex_
    ) external view returns (bytes32);

    /**
     * @notice Returns all transaction hashes for a proposal
     * @param proposalId_ The proposal ID
     * @return Array of transaction hashes
     */
    function getProposalTxHashes(uint32 proposalId_) external view returns (bytes32[] memory);

    /**
     * @notice Returns detailed proposal information
     * @param proposalId_ The proposal ID
     * @return strategy The voting strategy
     * @return txHashes Transaction hashes
     * @return timelockPeriod Timelock period
     * @return executionPeriod Execution period
     * @return executionCounter Executed transaction count
     */
    function getProposal(
        uint32 proposalId_
    ) external view returns (
        address strategy,
        bytes32[] memory txHashes,
        uint32 timelockPeriod,
        uint32 executionPeriod,
        uint32 executionCounter
    );

    // --- State-Changing Functions ---

    /**
     * @notice Updates the default timelock period
     * @param timelockPeriod_ New timelock in seconds
     */
    function updateTimelockPeriod(uint32 timelockPeriod_) external;

    /**
     * @notice Updates the default execution period
     * @param executionPeriod_ New execution period in seconds
     */
    function updateExecutionPeriod(uint32 executionPeriod_) external;

    /**
     * @notice Updates the default strategy
     * @param strategy_ New strategy address
     */
    function updateStrategy(address strategy_) external;

    /**
     * @notice Submits a new proposal
     * @param transactions_ Transactions to execute if passed
     * @param metadata_ IPFS hash or other metadata
     * @param proposerAdapter_ Adapter that validates proposer
     * @param proposerAdapterData_ Data for the adapter
     */
    function submitProposal(
        Transaction[] calldata transactions_,
        string calldata metadata_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) external;

    /**
     * @notice Executes transactions from an EXECUTABLE proposal
     * @param proposalId_ The proposal ID
     * @param transactions_ Transactions to execute (must match stored hashes)
     */
    function executeProposal(
        uint32 proposalId_,
        Transaction[] calldata transactions_
    ) external;
}
