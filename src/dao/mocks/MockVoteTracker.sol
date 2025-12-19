// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IVoteTrackerV1
} from "../interfaces/dao/deployables/IVoteTrackerV1.sol";

/**
 * @title MockVoteTracker
 * @dev Mock implementation of VoteTrackerV1 for testing
 */
contract MockVoteTracker is IVoteTrackerV1 {
    mapping(uint256 => mapping(address => mapping(bytes32 => bool)))
        private _hasVoted;
    address[] public authorizedCallers;

    modifier onlyAuthorizedCaller() {
        bool isAuthorized = false;
        for (uint256 i = 0; i < authorizedCallers.length; i++) {
            if (msg.sender == authorizedCallers[i]) {
                isAuthorized = true;
                break;
            }
        }
        if (!isAuthorized) revert UnauthorizedCaller(msg.sender);
        _;
    }

    function recordVote(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external override onlyAuthorizedCaller {
        bytes32 key = keccak256(voteData_);
        if (_hasVoted[contextId_][voter_][key]) {
            revert AlreadyVoted(contextId_, voter_, voteData_);
        }
        _hasVoted[contextId_][voter_][key] = true;
    }

    function hasVoted(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external view override returns (bool) {
        bytes32 key = keccak256(voteData_);
        return _hasVoted[contextId_][voter_][key];
    }

    function getAuthorizedCallers() external view returns (address[] memory) {
        return authorizedCallers;
    }

    function initialize(address[] memory authorizedCallers_) external {
        authorizedCallers = authorizedCallers_;
    }
}
