// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IVotingTypes
 * @notice Common types used across voting-related contracts
 * @dev This interface defines shared structs to avoid circular dependencies
 * and promote reusability across voting-related contracts.
 */
interface IVotingTypes {
    /**
     * @notice Configuration for a voting mechanism combining weight calculation and vote tracking
     * @param votingWeight Contract that calculates voting weight based on token holdings
     * @param voteTracker Contract that tracks vote participation to prevent double voting
     */
    struct VotingConfig {
        address votingWeight;
        address voteTracker;
    }

    /**
     * @notice Data structure for casting votes through specific voting configurations
     * @param configIndex Index of the VotingConfig in the votingConfigs array
     * @param voteData Token-specific data (e.g., token IDs for ERC721)
     */
    struct VotingConfigVoteData {
        uint256 configIndex;
        bytes voteData;
    }
}
