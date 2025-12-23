// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

interface IVoting {

    struct Votes {
        uint256 approvals;
        uint256 disapprovals;
    }

    struct VotingAmount{
        uint256 approvedTimes;
        uint256 dissaprovedTimes;
    }

    struct Voter {
        string proposal;
        address voterAddress;
        bool vote;
        uint40 timestamp;
    }
    
    enum Status {
      Vote_now,
      soon,
      Closed
    }

    enum Type {
        core,
        community
    }

    struct Proposal {
        string proposal;
        bool exists;
        uint256 voteCount;
        Type proposalType;
        Status proposalStatus;
        uint40 startTime;
        uint40 endTime;
        Votes votes;
    }

    event addedProposal (string newProposals, uint40 timestamp);
    event votedProposal(string proposal, bool choice);
    function changeWithdrawAddress(address _newWithdrawAddress) external;
    function voteProposal(string memory proposal, bool choice) external; 
    function isBlocked(address _addr) external view  returns (bool);
    function blockAddress(address target, bool freeze) external;
    
}