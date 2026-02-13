// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {Transaction} from "../Module.sol";

/**
 * @title IModuleGovernorV1
 * @notice Central governance module for DAOs using the Governor Protocol
 * @dev This module serves as the core governance system that manages proposals and executes
 * transactions through a Gnosis Safe. It acts as a Zodiac module, enabling modular
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
interface IModuleGovernorV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to set a zero address as the strategy */
    error InvalidStrategy();

    /** @notice Thrown when attempting to access a proposal that doesn't exist (ID >= totalProposalCount) */
    error InvalidProposal();

    /** @notice Thrown when the proposer adapter rejects the proposal submission */
    error InvalidProposer();

    /** @notice Thrown when attempting to execute a proposal that is not in the EXECUTABLE state */
    error ProposalNotExecutable();

    /** @notice Thrown when the provided transaction details don't match the stored transaction hash */
    error InvalidTxHash();

    /** @notice Thrown when a transaction execution fails during proposal execution */
    error TxFailed();

    /** @notice Thrown when attempting to execute a proposal with an empty transactions array */
    error InvalidTxs();

    // --- Structs ---

    /**
     * @notice Stores all data associated with a proposal
     * @dev Proposals are immutable once created - their parameters are locked at submission time
     * @param executionCounter Tracks how many transactions have been executed (enables partial execution)
     * @param timelockPeriod Time delay (in seconds) after voting ends before execution is allowed
     * @param executionPeriod Duration (in seconds) after timelock expires during which execution is allowed
     * @param strategy The voting strategy contract used for this specific proposal (immutable per proposal)
     * @param txHashes Array of hashes for each transaction in the proposal
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
     * @notice Represents the current state of a proposal in its lifecycle
     * @dev State transitions are determined by timestamps and voting results from the strategy
     *
     * State Machine Flow:
     * - ACTIVE: Initial state when proposal is created. Voting is open.
     *   → FAILED: If strategy.isPassed() returns false when voting ends
     *   → TIMELOCKED: If strategy.isPassed() returns true when voting ends
     * - TIMELOCKED: Voting passed, waiting for timelock period
     *   → EXECUTABLE: When block.timestamp > votingEnd + timelockPeriod
     * - EXECUTABLE: Ready for execution
     *   → EXECUTED: When all transactions have been executed (executionCounter == txHashes.length)
     *   → EXPIRED: When block.timestamp > votingEnd + timelockPeriod + executionPeriod
     * - FAILED: Terminal state - voting did not pass
     * - EXECUTED: Terminal state - proposal fully executed
     * - EXPIRED: Terminal state - execution period passed without full execution
     *
     * Values:
     * - ACTIVE: Proposal is in voting period (current time <= voting end)
     * - TIMELOCKED: Voting passed, waiting for timelock period to expire
     * - EXECUTABLE: Timelock expired, can be executed within execution period
     * - EXECUTED: All transactions have been successfully executed
     * - EXPIRED: Execution period passed without full execution
     * - FAILED: Voting did not pass according to strategy rules
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
     * @notice Emitted when a new proposal is successfully created
     * @param strategy The voting strategy contract that will manage voting for this proposal
     * @param proposalId The unique identifier assigned to this proposal
     * @param proposer The address that submitted the proposal
     * @param transactions Array of transactions that will be executed if the proposal passes
     * @param metadata IPFS hash or other metadata describing the proposal
     */
    event ProposalCreated(
        address strategy,
        uint32 proposalId,
        address proposer,
        Transaction[] transactions,
        string metadata
    );

    /**
     * @notice Emitted when proposal transactions are successfully executed
     * @param proposalId The ID of the executed proposal
     * @param txHashes Array of transaction hashes that were executed
     */
    event ProposalExecuted(uint32 proposalId, bytes32[] txHashes);

    /**
     * @notice Emitted when the timelock period is updated
     * @param timelockPeriod The new timelock period in seconds
     */
    event TimelockPeriodUpdated(uint32 timelockPeriod);

    /**
     * @notice Emitted when the execution period is updated
     * @param executionPeriod The new execution period in seconds
     */
    event ExecutionPeriodUpdated(uint32 executionPeriod);

    /**
     * @notice Emitted when the default strategy is updated
     * @param strategy The new default strategy address
     */
    event StrategyUpdated(address strategy);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the Governor module with governance parameters
     * @dev Can only be called once during deployment. Sets up the module as a Zodiac module
     * with the specified Safe (avatar/target) and governance parameters.
     * @param owner_ The address that will have owner privileges (can update strategy, periods)
     * @param avatar_ The Safe address that will execute transactions (can be same as target)
     * @param target_ The Safe address that this module will interact with (usually same as avatar)
     * @param strategy_ The initial voting strategy contract address
     * @param timelockPeriod_ Initial timelock period in seconds (can be 0)
     * @param executionPeriod_ Initial execution period in seconds (can be 0 for no deadline)
     * @custom:throws InvalidStrategy if strategy_ is the zero address
     */
    function initialize(
        address owner_,
        address avatar_,
        address target_,
        address strategy_,
        uint32 timelockPeriod_,
        uint32 executionPeriod_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns the total number of proposals that have been created
     * @dev Proposal IDs are 0-indexed, so valid IDs range from 0 to totalProposalCount-1
     * @return totalProposalCount The total number of proposals created
     */
    function totalProposalCount()
        external
        view
        returns (uint32 totalProposalCount);

    /**
     * @notice Returns the current default timelock period for new proposals
     * @dev This value is used for new proposals; existing proposals keep their original timelock
     * @return timelockPeriod The timelock period in seconds
     */
    function timelockPeriod() external view returns (uint32 timelockPeriod);

    /**
     * @notice Returns the current default execution period for new proposals
     * @dev This value is used for new proposals; existing proposals keep their original period
     * @return executionPeriod The execution period in seconds
     */
    function executionPeriod() external view returns (uint32 executionPeriod);

    /**
     * @notice Returns the full proposal struct for a given proposal ID
     * @dev Returns empty/default values for non-existent proposals (ID >= totalProposalCount)
     * @param proposalId_ The ID of the proposal to retrieve
     * @return proposal The complete proposal data
     */
    function proposals(
        uint32 proposalId_
    ) external view returns (Proposal memory proposal);

    /**
     * @notice Returns the current default strategy address for new proposals
     * @dev This is used for new proposals; existing proposals keep their original strategy
     * @return strategy The default strategy contract address
     */
    function strategy() external view returns (address strategy);

    /**
     * @notice Calculates and returns the current state of a proposal
     * @dev State is determined dynamically based on timestamps and voting results.
     * Reverts for non-existent proposals (ID >= totalProposalCount).
     * @param proposalId_ The ID of the proposal
     * @return proposalState The current state of the proposal
     * @custom:throws InvalidProposal if proposalId_ >= totalProposalCount
     */
    function proposalState(
        uint32 proposalId_
    ) external view returns (ProposalState proposalState);

    /**
     * @notice Generates the data that will be hashed to create a transaction hash
     * @dev Used internally for EIP-712 style hashing. Includes domain separator and transaction data.
     * @param transaction_ The transaction details to hash
     * @param nonce_ A unique nonce to prevent hash collisions
     * @return txHashData The encoded data ready for hashing
     */
    function generateTxHashData(
        Transaction calldata transaction_,
        uint256 nonce_
    ) external view returns (bytes memory txHashData);

    /**
     * @notice Computes the hash for a transaction
     * @dev Uses a deterministic nonce based on proposal count and transaction count.
     * This hash is stored in the proposal and validated during execution.
     * @param transaction_ The transaction to hash
     * @return txHash The computed transaction hash
     */
    function getTxHash(
        Transaction calldata transaction_
    ) external view returns (bytes32 txHash);

    /**
     * @notice Returns the transaction hash at a specific index in a proposal
     * @dev Reverts if the transaction index is out of bounds
     * @param proposalId_ The proposal ID
     * @param txIndex_ The index of the transaction in the proposal
     * @return txHash The transaction hash at the specified index
     * @custom:throws InvalidTxHash if txIndex_ is out of bounds
     */
    function getProposalTxHash(
        uint32 proposalId_,
        uint32 txIndex_
    ) external view returns (bytes32 txHash);

    /**
     * @notice Returns all transaction hashes for a proposal
     * @dev Returns an empty array for non-existent proposals
     * @param proposalId_ The proposal ID
     * @return txHashes Array of all transaction hashes in the proposal
     */
    function getProposalTxHashes(
        uint32 proposalId_
    ) external view returns (bytes32[] memory txHashes);

    /**
     * @notice Returns detailed information about a proposal
     * @dev Convenience function that unpacks the proposal struct. Returns default values
     * for non-existent proposals.
     * @param proposalId_ The proposal ID
     * @return strategy The voting strategy used for this proposal
     * @return txHashes Array of transaction hashes
     * @return timelockPeriod The timelock period for this proposal
     * @return executionPeriod The execution period for this proposal
     * @return executionCounter Number of transactions already executed
     */
    function getProposal(
        uint32 proposalId_
    )
        external
        view
        returns (
            address strategy,
            bytes32[] memory txHashes,
            uint32 timelockPeriod,
            uint32 executionPeriod,
            uint32 executionCounter
        );

    // --- State-Changing Functions ---

    /**
     * @notice Updates the default timelock period for new proposals
     * @dev Only callable by the owner. Does not affect existing proposals.
     * @param timelockPeriod_ The new timelock period in seconds
     * @custom:access Restricted to owner
     */
    function updateTimelockPeriod(uint32 timelockPeriod_) external;

    /**
     * @notice Updates the default execution period for new proposals
     * @dev Only callable by the owner. Does not affect existing proposals.
     * @param executionPeriod_ The new execution period in seconds
     * @custom:access Restricted to owner
     */
    function updateExecutionPeriod(uint32 executionPeriod_) external;

    /**
     * @notice Updates the default strategy for new proposals
     * @dev Only callable by the owner. Does not affect existing proposals.
     * Each proposal uses the strategy that was set at the time of its creation.
     * @param strategy_ The new strategy contract address
     * @custom:access Restricted to owner
     * @custom:throws InvalidStrategy if strategy_ is the zero address
     */
    function updateStrategy(address strategy_) external;

    /**
     * @notice Submits a new proposal with a set of transactions
     * @dev The proposal is validated by the proposer adapter before creation.
     * The strategy is notified to initialize voting for the new proposal.
     * Transaction hashes are computed and stored to ensure execution integrity.
     * @param transactions_ Array of transactions to execute if proposal passes
     * @param metadata_ IPFS hash or other metadata describing the proposal
     * @param proposerAdapter_ Contract that validates if the proposer can submit
     * @param proposerAdapterData_ Additional data for the proposer adapter validation
     * @custom:throws InvalidProposer if the proposer adapter rejects the submission
     * @custom:emits ProposalCreated with proposal details
     */
    function submitProposal(
        Transaction[] calldata transactions_,
        string calldata metadata_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) external;

    /**
     * @notice Executes transactions from a proposal that is in the EXECUTABLE state
     * @dev Executes all or remaining transactions in the proposal. Supports partial execution
     * where some transactions can be executed in one call and the rest in subsequent calls.
     * Each transaction is validated against its stored hash before execution.
     * @param proposalId_ The ID of the proposal to execute
     * @param transactions_ The transaction details (must match stored hashes)
     * @custom:throws ProposalNotExecutable if proposal is not in EXECUTABLE state
     * @custom:throws InvalidTxs if transactions array is empty
     * @custom:throws InvalidTxHash if transaction details don't match stored hashes
     * @custom:throws TxFailed if a transaction execution fails
     * @custom:emits ProposalExecuted when all transactions are successfully executed
     */
    function executeProposal(
        uint32 proposalId_,
        Transaction[] calldata transactions_
    ) external;
}
