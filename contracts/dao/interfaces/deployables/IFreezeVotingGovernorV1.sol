// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IVotingTypes} from "./IVotingTypes.sol";

/**
 * @title IFreezeVotingGovernorV1
 * @notice Freeze voting implementation for Governor-based parent DAOs
 * @dev This contract enables token holders of an Governor-based parent DAO to vote
 * to freeze a child DAO. It leverages the parent's existing voting adapters and
 * token infrastructure for freeze voting.
 *
 * Key features:
 * - Uses parent DAO's strategy and voting configurations for voting weight
 * - Automatic new freeze proposal creation if previous one expired
 * - Supports multiple voting adapters in a single vote
 * - Light Account support for gasless freeze voting
 *
 * Freeze voting process:
 * 1. If no active proposal exists, first voter creates one automatically
 * 2. Voters use parent's voting adapters to cast weighted votes
 * 3. When threshold is reached, child DAO is immediately frozen
 * 4. Parent DAO (owner) can unfreeze at any time
 *
 * Integration:
 * - References parent's Governor module for strategy information
 * - Voting weight calculated through parent's voting configurations
 * - Owned by the parent DAO for administrative control
 */
interface IFreezeVotingGovernorV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to use a voting config not configured in the parent's strategy */
    error InvalidVotingConfig(uint256 configIndex);

    /**
     * @notice Thrown when attempting to vote with no voting weight
     * @param configIndex The index of the voting configuration that has no weight
     * @param voteData The vote data provided by the user for this config
     */
    error NoVotingWeight(uint256 configIndex, bytes voteData);

    // --- Events ---

    /**
     * @notice Emitted when a new freeze proposal is created
     * @param proposer The address that triggered the proposal creation (first voter)
     * @param strategy The parent DAO's strategy contract used for this freeze proposal
     */
    event FreezeProposalCreated(
        address indexed proposer,
        address indexed strategy
    );

    /**
     * @notice Emitted when a freeze vote is recorded for a specific voting config
     * @param voter The address that cast the vote
     * @param freezeProposalId The freeze proposal timestamp ID
     * @param weight The voting weight applied from this config
     * @param voteData The processed vote data for this config
     */
    event FreezeVoteRecorded(
        address indexed voter,
        uint256 freezeProposalId,
        uint256 weight,
        bytes voteData
    );

    // --- Initializer Functions ---

    /**
     * @notice Initializes the freeze voting contract for an Governor-based parent DAO
     * @param owner_ The parent DAO that will have unfreeze powers
     * @param freezeVotesThreshold_ Voting weight required to freeze the child DAO
     * @param freezeProposalPeriod_ Duration in seconds that freeze proposals remain active
     * @param parentGovernor_ The parent DAO's Governor module address
     * @param lightAccountFactory_ Factory for Light Account support (ERC-4337)
     */
    function initialize(
        address owner_,
        uint256 freezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        address parentGovernor_,
        address lightAccountFactory_
    ) external;

    // --- View Functions ---

    /**
     * @notice Returns the parent DAO's Governor module
     * @dev Used to access the parent's strategy for voting adapter validation
     * @return parentGovernor The parent's Governor module address
     */
    function parentGovernor() external view returns (address parentGovernor);

    /**
     * @notice Returns the strategy contract used for the current freeze proposal
     * @dev Captured from parent Governor when the freeze proposal is created
     * @return freezeProposalStrategy The strategy address for the active freeze proposal
     */
    function freezeProposalStrategy()
        external
        view
        returns (address freezeProposalStrategy);

    // --- State-Changing Functions ---

    /**
     * @notice Casts a freeze vote using the parent DAO's voting configurations
     * @dev If no active freeze proposal exists, creates one automatically.
     * Aggregates voting weight from all specified configs. If total votes
     * reach threshold, the child DAO is immediately frozen.
     * @param votingConfigsToUse_ Array of voting configurations and their data
     * @param lightAccountIndex_ Index for Light Account resolution (0 for direct voting)
     * @custom:throws InvalidVotingConfig if config not in parent's strategy
     * @custom:throws NoVotingWeight if any config returns zero voting weight
     * @custom:throws NoVotes if voter has zero total weight
     * @custom:emits FreezeProposalCreated if new proposal started
     * @custom:emits FreezeVoteCast with voter and weight
     */
    function castFreezeVote(
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_,
        uint256 lightAccountIndex_
    ) external;

    /**
     * @notice Allows the owner to manually unfreeze the child DAO
     * @dev Only the parent DAO (owner) can call this function. Resets all freeze
     * state including proposal counts, frozen status, and strategy snapshot.
     * @custom:access Restricted to owner (parent DAO)
     */
    function unfreeze() external;
}
