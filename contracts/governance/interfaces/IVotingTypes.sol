// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

/**
 * @title IVotingTypes
 * @author Lux Industries Inc
 * @notice Common types for governance voting system
 */
interface IVotingTypes {
    /**
     * @notice Configuration for a voting source
     * @dev Combines a voting weight calculator with a vote tracker
     * @param votingWeight Contract that calculates voting power
     * @param voteTracker Contract that tracks votes cast
     */
    struct VotingConfig {
        address votingWeight;
        address voteTracker;
    }

    /**
     * @notice Data for casting a vote through a specific config
     * @param configIndex Index of the voting config to use
     * @param voteData Additional data for the config (e.g., token IDs)
     */
    struct VotingConfigVoteData {
        uint256 configIndex;
        bytes voteData;
    }
}
