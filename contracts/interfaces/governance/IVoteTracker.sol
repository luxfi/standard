// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

/**
 * @title IVoteTracker
 * @author Lux Industries Inc
 * @notice Interface for contracts that track voting participation
 * @dev Enables modular vote tracking separate from weight calculation.
 * Implementations can track votes differently based on token type:
 * - LRC20: Simple address-based tracking (one vote per address)
 * - LRC721: Token ID-based tracking (prevent reuse of specific NFTs)
 *
 * Renamed from IVoteTrackerV1 to align with Lux naming.
 */
interface IVoteTracker {
    // --- Errors ---

    error AlreadyVoted(uint256 contextId, address voter, bytes voteData);
    error UnauthorizedCaller(address caller);

    // --- Initializers ---

    /**
     * @notice Initializes the vote tracker with authorized callers
     * @param authorizedCallers_ Contracts authorized to record votes
     */
    function initialize(address[] memory authorizedCallers_) external;

    // --- View Functions ---

    /**
     * @notice Checks if a vote has already been recorded
     * @param contextId_ The voting context (e.g., proposalId)
     * @param voter_ The address to check
     * @param voteData_ Token-specific data (e.g., NFT token IDs)
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
     * @param contextId_ The voting context (e.g., proposalId)
     * @param voter_ The address casting the vote
     * @param voteData_ Processed vote data from weight strategy
     */
    function recordVote(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external;
}
