// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IVotingWeightV1
} from "../interfaces/dao/deployables/IVotingWeightV1.sol";

/**
 * @title MockVotingWeight
 * @dev Generic mock implementation of voting weight strategy for testing.
 * This contract can simulate any voting weight strategy behavior.
 */
contract MockVotingWeight is IVotingWeightV1 {
    address public token;
    uint256 public weightPerToken;

    // Mock storage for voting weights
    mapping(address => mapping(uint256 => uint256)) private _mockWeights;
    mapping(address => mapping(uint256 => bool)) private _hasMockWeightBeenSet;

    // Default weights for easier testing
    mapping(address => uint256) private _defaultWeights;
    mapping(address => bool) private _hasDefaultWeight;

    // Mock storage for weight and processed data
    uint256 private _weight;
    bytes private _processedData;

    function initialize(address token_, uint256 weightPerToken_) external {
        token = token_;
        weightPerToken = weightPerToken_;
    }

    /**
     * @dev Sets a specific voting weight for testing
     */
    function setMockWeight(
        address voter,
        uint256 timestamp,
        uint256 weight
    ) external {
        _mockWeights[voter][timestamp] = weight;
        _hasMockWeightBeenSet[voter][timestamp] = true;
    }

    /**
     * @dev Sets a default weight for a voter (used when no specific timestamp weight is set)
     */
    function setDefaultWeight(address voter, uint256 weight) external {
        _defaultWeights[voter] = weight;
        _hasDefaultWeight[voter] = true;
    }

    /**
     * @dev Set weight for simple testing
     */
    function setWeight(uint256 weight) external {
        _weight = weight;
    }

    /**
     * @dev Set processed data for testing
     */
    function setProcessedData(bytes calldata data) external {
        _processedData = data;
    }

    function calculateWeight(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view override returns (uint256, bytes memory) {
        // If specific mock weight is set for this voter/timestamp, use it
        if (_hasMockWeightBeenSet[voter_][timestamp_]) {
            return (_mockWeights[voter_][timestamp_], voteData_);
        }
        // Return default weight if set
        if (_hasDefaultWeight[voter_]) {
            return (_defaultWeights[voter_], voteData_);
        }
        // If general weight is set, return it with processed data
        if (_weight > 0) {
            if (_processedData.length > 0) {
                return (_weight, _processedData);
            } else {
                return (_weight, voteData_);
            }
        }

        // If weightPerToken is set and voteData contains token IDs, calculate weight
        // This allows the mock to simulate ERC721-like behavior when needed
        if (weightPerToken > 0 && voteData_.length > 0) {
            // Try to decode as token IDs array, if it fails just return 0
            try this.decodeTokenIds(voteData_) returns (
                uint256[] memory tokenIds
            ) {
                return (tokenIds.length * weightPerToken, voteData_);
            } catch {
                // If decode fails, just return 0
                return (0, voteData_);
            }
        }

        // Default behavior - return 0 (no weight)
        return (0, voteData_);
    }

    function getVotingWeightForPaymaster(
        address voter_,
        uint256 timestamp_,
        bytes calldata voteData_
    ) external view override returns (uint256) {
        if (_hasMockWeightBeenSet[voter_][timestamp_]) {
            return _mockWeights[voter_][timestamp_];
        }
        // Return default weight if set
        if (_hasDefaultWeight[voter_]) {
            return _defaultWeights[voter_];
        }

        // If weightPerToken is set and voteData contains token IDs, calculate weight
        if (weightPerToken > 0 && voteData_.length > 0) {
            // Try to decode as token IDs array, if it fails just return 0
            try this.decodeTokenIds(voteData_) returns (
                uint256[] memory tokenIds
            ) {
                return tokenIds.length * weightPerToken;
            } catch {
                // If decode fails, just return 0
                return 0;
            }
        }

        // Default behavior - return 0
        return 0;
    }

    /**
     * @dev Helper function to decode token IDs from vote data
     * This is external so it can be called via try-catch
     */
    function decodeTokenIds(
        bytes calldata voteData_
    ) external pure returns (uint256[] memory) {
        return abi.decode(voteData_, (uint256[]));
    }
}
