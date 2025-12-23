// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {ISafe} from "@safe-global/safe-smart-account/interfaces/ISafe.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title LuxSafeGovernor
 * @author Lux Industries Inc
 * @notice Azorius-style governance module for Safe multisig
 * @dev Enables on-chain voting for Safe transactions
 * 
 * This is a modular governance system that attaches to a Safe wallet:
 * - Proposals can be submitted by token holders meeting threshold
 * - Voting is weighted by token holdings (ERC20Votes or ERC721Votes)
 * - Passed proposals can be executed through the Safe
 * 
 * Built on Safe v1.5.0 and OpenZeppelin Contracts v5.1.0
 */
contract LuxSafeGovernor {
    /// @notice Contract version
    string public constant VERSION = "1.0.0";

    /// @notice The Safe this module governs
    address payable public immutable safe;

    /// @notice The voting token
    IVotes public immutable votingToken;

    /// @notice Minimum tokens to create a proposal
    uint256 public proposalThreshold;

    /// @notice Voting period in blocks
    uint256 public votingPeriod;

    /// @notice Quorum required (basis points, 10000 = 100%)
    uint256 public quorumBps;

    /// @notice Proposal counter
    uint256 public proposalCount;

    /// @notice Proposal state enum
    enum ProposalState {
        Pending,
        Active,
        Defeated,
        Succeeded,
        Executed,
        Cancelled
    }

    /// @notice Proposal struct
    struct Proposal {
        address proposer;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool cancelled;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        Enum.Operation[] operations;
    }

    /// @notice Proposal ID => Proposal
    mapping(uint256 => Proposal) public proposals;

    /// @notice Proposal ID => Voter => Has voted
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 weight
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);

    // Errors
    error NotSafe();
    error BelowProposalThreshold();
    error InvalidProposal();
    error ProposalNotActive();
    error AlreadyVoted();
    error ProposalNotSucceeded();
    error ExecutionFailed();

    /// @notice Modifier for Safe-only functions
    modifier onlySafe() {
        if (msg.sender != safe) revert NotSafe();
        _;
    }

    /**
     * @notice Constructor
     * @param _safe The Safe this module governs
     * @param _votingToken The voting token (must implement IVotes)
     * @param _proposalThreshold Minimum tokens to create proposal
     * @param _votingPeriod Voting period in blocks
     * @param _quorumBps Quorum in basis points
     */
    constructor(
        address payable _safe,
        IVotes _votingToken,
        uint256 _proposalThreshold,
        uint256 _votingPeriod,
        uint256 _quorumBps
    ) {
        safe = _safe;
        votingToken = _votingToken;
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumBps = _quorumBps;
    }

    /**
     * @notice Create a new proposal
     * @param targets Target addresses for calls
     * @param values ETH values for calls
     * @param calldatas Calldata for calls
     * @param operations Operation types (Call or DelegateCall)
     * @param description Proposal description
     * @return proposalId The ID of the new proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        Enum.Operation[] memory operations,
        string memory description
    ) external returns (uint256 proposalId) {
        uint256 votes = votingToken.getVotes(msg.sender);
        if (votes < proposalThreshold) revert BelowProposalThreshold();
        if (targets.length != values.length || targets.length != calldatas.length)
            revert InvalidProposal();

        proposalId = ++proposalCount;
        uint256 startBlock = block.number + 1;
        uint256 endBlock = startBlock + votingPeriod;

        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executed: false,
            cancelled: false,
            targets: targets,
            values: values,
            calldatas: calldatas,
            operations: operations
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            startBlock,
            endBlock,
            description
        );
    }

    /**
     * @notice Cast a vote
     * @param proposalId Proposal ID
     * @param support 0 = Against, 1 = For, 2 = Abstain
     */
    function castVote(uint256 proposalId, uint8 support) external {
        if (state(proposalId) != ProposalState.Active) revert ProposalNotActive();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        Proposal storage proposal = proposals[proposalId];
        uint256 weight = votingToken.getPastVotes(msg.sender, proposal.startBlock);

        hasVoted[proposalId][msg.sender] = true;

        if (support == 0) {
            proposal.againstVotes += weight;
        } else if (support == 1) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    /**
     * @notice Execute a succeeded proposal
     * @param proposalId Proposal ID
     */
    function execute(uint256 proposalId) external {
        if (state(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded();

        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            bool success = ISafe(safe).execTransactionFromModule(
                proposal.targets[i],
                proposal.values[i],
                proposal.calldatas[i],
                proposal.operations[i]
            );
            if (!success) revert ExecutionFailed();
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (proposer or Safe only)
     * @param proposalId Proposal ID
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (msg.sender != proposal.proposer && msg.sender != safe) revert NotSafe();
        proposal.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Get proposal state
     * @param proposalId Proposal ID
     * @return The current state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.cancelled) return ProposalState.Cancelled;
        if (proposal.executed) return ProposalState.Executed;
        if (block.number < proposal.startBlock) return ProposalState.Pending;
        if (block.number <= proposal.endBlock) return ProposalState.Active;

        // Calculate quorum
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 totalSupply = votingToken.getPastTotalSupply(proposal.startBlock);
        uint256 quorumVotes = (totalSupply * quorumBps) / 10000;

        if (totalVotes < quorumVotes || proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        }

        return ProposalState.Succeeded;
    }

    /**
     * @notice Update governance parameters (Safe only)
     */
    function setProposalThreshold(uint256 _proposalThreshold) external onlySafe {
        proposalThreshold = _proposalThreshold;
    }

    function setVotingPeriod(uint256 _votingPeriod) external onlySafe {
        votingPeriod = _votingPeriod;
    }

    function setQuorumBps(uint256 _quorumBps) external onlySafe {
        quorumBps = _quorumBps;
    }

    /// @notice Returns the governor version
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
