// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IVotingTypes} from "./IVotingTypes.sol";

/**
 * @title IFreezeVotingStandaloneV1
 * @notice Interface for standalone freeze voting that allows token holders to freeze a multisig Safe
 * @dev This interface enables token-based freeze voting for a single multisig Safe without requiring
 * an Governor module. Unlike parent/child freeze voting, this system:
 * - Allows the Safe's own token holders to freeze it
 * - Implements permanent freezing (no auto-unfreeze after time period)
 * - Automatically unfreezes when unfreeze votes reach the threshold
 * - All pre-freeze transactions remain invalidated after unfreeze
 *
 * Key features:
 * - Manages its own list of VotingConfigs (no parent Governor reference)
 * - Owned by the Safe itself (not a parent DAO)
 * - Uses VoteTracker and VotingWeight contracts for modular voting
 * - Tracks freeze and unfreeze votes separately
 * - Supports timelock bypass for atomic unfreeze execution
 *
 * Security model:
 * - Voting configs are immutable after deployment
 * - Unfreeze happens automatically when threshold is reached
 * - All pre-freeze transactions are permanently invalidated by the guard
 */
interface IFreezeVotingStandaloneV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to use a voting config that is not configured */
    error InvalidVotingConfig(uint256 configIndex);

    /** @notice Thrown when an address has already voted on the current proposal */
    error AlreadyVoted();

    /** @notice Thrown when trying to vote on an expired proposal */
    error ProposalExpired();

    /** @notice Thrown when unfreeze votes haven't reached the required threshold */
    error InsufficientVotes();

    /** @notice Thrown when trying to freeze an already frozen DAO */
    error AlreadyFrozen();

    /** @notice Thrown when trying to unfreeze a DAO that isn't frozen */
    error NotFrozen();

    // --- Events ---

    /**
     * @notice Emitted when a new freeze proposal is created
     * @param createdAt Timestamp when the proposal was created
     * @param creator Address that triggered the proposal creation
     */
    event FreezeProposalCreated(
        uint48 indexed createdAt,
        address indexed creator
    );

    /**
     * @notice Emitted when a new unfreeze proposal is created
     * @param createdAt Timestamp when the proposal was created
     * @param creator Address that triggered the proposal creation
     */
    event UnfreezeProposalCreated(
        uint48 indexed createdAt,
        address indexed creator
    );

    /**
     * @notice Emitted when an unfreeze vote is cast
     * @param voter Address that cast the vote
     * @param weight Voting weight applied
     */
    event UnfreezeVoteCast(address indexed voter, uint256 weight);

    /**
     * @notice Emitted when the DAO is unfrozen
     * @param timestamp When the unfreeze occurred
     */
    event DAOUnfrozen(uint48 timestamp);

    // --- Initialize Function ---

    /**
     * @notice Initialize the contract with base parameters
     * @dev Voting configs must be set separately via initialize2 due to circular dependencies
     * @param freezeVotesThreshold_ Voting weight required to freeze the DAO
     * @param unfreezeVotesThreshold_ Voting weight required to unfreeze the DAO
     * @param freezeProposalPeriod_ Duration in seconds that freeze proposals remain active
     * @param unfreezeProposalPeriod_ Duration in seconds that unfreeze proposals remain active
     * @param lightAccountFactory_ Address of the light account factory for gasless voting
     */
    function initialize(
        uint256 freezeVotesThreshold_,
        uint256 unfreezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        uint32 unfreezeProposalPeriod_,
        address lightAccountFactory_
    ) external;

    /**
     * @notice Second initialization step to set voting configs
     * @dev Called after initial deployment to complete circular dependency resolution.
     * Can only be called once when votingConfigs is empty.
     * @param votingConfigs_ Array of voting configs (weightStrategy + voteTracker pairs)
     */
    function initialize2(
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) external;

    // --- View Functions ---

    /**
     * @notice Get all configured voting configs
     * @return configs Array of voting configurations
     */
    function getVotingConfigs()
        external
        view
        returns (IVotingTypes.VotingConfig[] memory configs);

    /**
     * @notice Get a specific voting config by index
     * @param index The index of the voting config
     * @return config The voting configuration
     */
    function votingConfig(
        uint256 index
    ) external view returns (IVotingTypes.VotingConfig memory config);

    /**
     * @notice Get the voting weight threshold required to unfreeze
     * @return threshold The unfreeze threshold
     */
    function unfreezeVotesThreshold() external view returns (uint256 threshold);

    /**
     * @notice Get the duration unfreeze proposals remain active
     * @return period Duration in seconds
     */
    function unfreezeProposalPeriod() external view returns (uint32 period);

    /**
     * @notice Get current unfreeze proposal vote count
     * @return voteCount Current vote count for unfreezing
     */
    function getUnfreezeProposalVotes()
        external
        view
        returns (uint256 voteCount);

    // --- State-Changing Functions ---

    /**
     * @notice Cast a vote to freeze the DAO
     * @dev Creates a new freeze proposal if none exists or current one expired.
     * Aggregates voting weight from all specified configs.
     * @param votingConfigsToUse_ Array of voting configs and their vote data
     * @param lightAccountIndex_ Index of the light account if voting through one (0 if not)
     * @custom:throws AlreadyFrozen if DAO is already frozen
     * @custom:throws AlreadyVoted if voter already voted on current proposal
     * @custom:throws InvalidVotingConfig if config not configured
     * @custom:emits FreezeProposalCreated if new proposal created
     * @custom:emits FreezeVoteCast with total weight
     * @custom:emits DAOFrozen if threshold reached
     */
    function castFreezeVote(
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_,
        uint256 lightAccountIndex_
    ) external;

    /**
     * @notice Cast a vote to unfreeze the DAO
     * @dev Votes accumulate towards unfreezing the DAO with a clean slate.
     * All transactions timelocked before the freeze are invalidated.
     * Automatically unfreezes when threshold is reached.
     * @param votingConfigsToUse_ Array of voting configs and their vote data
     * @param lightAccountIndex_ Index of the light account if voting through one (0 if not)
     * @custom:throws NotFrozen if DAO is not frozen
     * @custom:throws AlreadyVoted if voter already voted on current unfreeze proposal
     * @custom:throws InvalidVotingConfig if config not configured
     * @custom:emits UnfreezeProposalCreated if new proposal created
     * @custom:emits UnfreezeVoteCast with total weight
     * @custom:emits DAOUnfrozen if threshold reached
     */
    function castUnfreezeVote(
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_,
        uint256 lightAccountIndex_
    ) external;
}
