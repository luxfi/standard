// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IVotingWeightV1
 * @notice Interface for contracts that calculate voting weight
 * @dev This interface enables modular voting weight calculation separate from vote tracking.
 * Implementations can use various methods to determine voting weight (token holdings,
 * whitelists, reputation systems, etc.).
 *
 * The separation of weight calculation from vote tracking allows:
 * - Reuse of weight calculations across different voting contexts
 * - Clean testing of weight calculation logic
 * - Easy addition of new voting weight strategies
 *
 * Voting weight contracts are responsible for:
 * - Storing configuration for weight calculation
 * - Calculating voting weight at specific timestamps
 * - Processing and validating vote data
 * - Returning processed data for vote tracking
 */
interface IVotingWeightV1 {
    // --- View Functions ---

    /**
     * @notice Calculates voting weight for a voter at a specific timestamp
     * @dev Implementations define their own logic for weight calculation.
     * @param voter_ The address whose voting weight to calculate
     * @param timestamp_ The timestamp at which to calculate weight (for snapshot)
     * @param voteData_ Implementation-specific data needed for weight calculation
     * @return weight The calculated voting weight
     * @return processedData Implementation-specific data for vote tracking
     */
    function calculateWeight(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view returns (uint256 weight, bytes memory processedData);

    /**
     * @notice Calculates voting weight for paymaster validation without using banned opcodes
     * @dev This function exists specifically for ERC-4337 paymaster validation during gasless voting.
     * It avoids using block.timestamp and block.number which are banned opcodes in the validation phase.
     * This function should ONLY be used for gas sponsorship validation,
     * NOT for actual voting operations which should use calculateWeight() for efficiency.
     * @param voter_ The address whose voting weight to calculate
     * @param timestamp_ The timestamp at which to calculate weight (proposal start time)
     * @param voteData_ Implementation-specific data needed for weight calculation
     * @return weight The calculated voting weight (0 if not eligible)
     */
    function getVotingWeightForPaymaster(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view returns (uint256 weight);
}
