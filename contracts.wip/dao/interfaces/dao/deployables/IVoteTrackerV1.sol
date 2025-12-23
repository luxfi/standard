// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IVoteTrackerV1
 * @notice Interface for contracts that track voting participation
 * @dev This interface enables modular vote tracking separate from weight calculation.
 * Implementations can track votes differently based on token type:
 * - ERC20: Simple address-based tracking (one vote per address)
 * - ERC721: Token ID-based tracking (prevent reuse of specific NFTs)
 *
 * The separation of vote tracking from weight calculation allows:
 * - Different tracking strategies for different token types
 * - Reuse of tracking logic across voting contexts
 * - Clear separation of concerns
 *
 * Vote trackers are responsible for:
 * - Recording that a vote has occurred
 * - Preventing double voting
 * - Validating vote data format
 * - NOT calculating weights or validating token ownership
 */
interface IVoteTrackerV1 {
    // --- Errors ---

    /**
     * @notice Thrown when attempting to record a vote that has already been cast
     * @param contextId The voting context where the vote was already recorded
     * @param voter The address that already voted
     * @param voteData The vote data that was already used
     */
    error AlreadyVoted(uint256 contextId, address voter, bytes voteData);

    /**
     * @notice Thrown when an unauthorized address attempts to record votes
     * @param caller The address that attempted to call the function
     */
    error UnauthorizedCaller(address caller);

    // --- Initializers ---

    /**
     * @notice Initializes the vote tracker with authorized callers
     * @param authorizedCallers_ Initial set of contracts authorized to record votes
     */
    function initialize(address[] memory authorizedCallers_) external;

    // --- View Functions ---

    /**
     * @notice Checks if a vote has already been recorded
     * @dev Implementations should check based on their tracking strategy:
     * - ERC20: Check if voter address has voted for this context
     * - ERC721: Check if any token IDs in voteData have been used
     * @param contextId_ The voting context (e.g., proposalId or freezeProposalTimestamp)
     * @param voter_ The address to check
     * @param voteData_ Token-specific data to check (e.g., NFT token IDs)
     * @return hasVoted True if vote has been recorded
     */
    function hasVoted(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external view returns (bool hasVoted);

    // --- State-Changing Functions ---

    /**
     * @notice Records that a vote has been cast
     * @dev Implementations should record based on their tracking strategy:
     * - ERC20: Mark voter address as having voted
     * - ERC721: Mark specific token IDs as used
     * Should revert if vote has already been recorded.
     * @param contextId_ The voting context (e.g., proposalId or freezeProposalTimestamp)
     * @param voter_ The address casting the vote
     * @param voteData_ Processed vote data from weight strategy (e.g., validated NFT IDs)
     * @custom:throws AlreadyVoted if vote has been recorded
     */
    function recordVote(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external;
}
