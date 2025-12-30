// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

/**
 * @title IVotingWeight
 * @author Lux Industries Inc
 * @notice Interface for contracts that calculate voting weight
 * @dev Enables modular voting weight calculation separate from vote tracking.
 * Implementations can use various methods to determine voting weight:
 * - Token holdings (LRC20)
 * - NFT ownership (LRC721)
 * - Whitelists
 * - Reputation systems
 *
 * Renamed from IVotingWeightV1 to align with Lux naming.
 */
interface IVotingWeight {
    /**
     * @notice Calculates voting weight for a voter at a specific timestamp
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
     * @notice Calculates voting weight for paymaster validation (ERC-4337 gasless voting)
     * @dev Avoids using block.timestamp and block.number which are banned opcodes
     * @param voter_ The address whose voting weight to calculate
     * @param timestamp_ The timestamp at which to calculate weight
     * @param voteData_ Implementation-specific data
     * @return weight The calculated voting weight (0 if not eligible)
     */
    function getVotingWeightForPaymaster(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view returns (uint256 weight);
}
