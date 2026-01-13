// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DAO
/// @notice Lux DAO governance - minimal on-chain governance
/// @dev Simple Governor-style contract for protocol governance
contract DAO is ReentrancyGuard {
    using ECDSA for bytes32;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 eta;                // Execution time (for timelock)
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        mapping(address => Receipt) receipts;
    }

    struct Receipt {
        bool hasVoted;
        uint8 support;  // 0 = Against, 1 = For, 2 = Abstain
        uint256 votes;
    }

    struct ProposalInfo {
        uint256 id;
        address proposer;
        uint256 eta;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Minimum time between proposal and vote start
    uint256 public constant VOTING_DELAY = 1 days;

    /// @notice Duration of voting period
    uint256 public constant VOTING_PERIOD = 3 days;

    /// @notice Minimum votes needed to create proposal
    uint256 public constant PROPOSAL_THRESHOLD = 100_000e18; // 100k tokens

    /// @notice Minimum votes for quorum
    uint256 public constant QUORUM_VOTES = 1_000_000e18; // 1M tokens

    /// @notice Timelock delay for execution
    uint256 public constant TIMELOCK_DELAY = 2 days;

    /// @notice Grace period for execution
    uint256 public constant GRACE_PERIOD = 14 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Governance token (must implement IVotes for snapshot-based voting)
    IVotes public immutable token;

    /// @notice Proposal count
    uint256 public proposalCount;

    /// @notice All proposals
    mapping(uint256 => Proposal) public proposals;

    /// @notice Latest proposal per proposer
    mapping(address => uint256) public latestProposalIds;

    /// @notice Guardian with veto power
    address public guardian;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);
    event ProposalCanceled(uint256 id);
    event ProposalQueued(uint256 id, uint256 eta);
    event ProposalExecuted(uint256 id);
    event GuardianUpdated(address oldGuardian, address newGuardian);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InsufficientVotes();
    error InvalidProposalLength();
    error ActiveProposalExists();
    error InvalidProposalState();
    error OnlyGuardian();
    error OnlyProposer();
    error AlreadyVoted();
    error VotingClosed();
    error TimelockNotReady();
    error ProposalExpired();
    error ExecutionFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _token, address _guardian) {
        token = IVotes(_token);
        guardian = _guardian;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSAL LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Create a new proposal
    /// @param targets Target addresses for calls
    /// @param values ETH values for calls
    /// @param calldatas Call data for each target
    /// @param description Human readable description
    /// @return Proposal ID
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        // Validate arrays
        if (targets.length != values.length || targets.length != calldatas.length) {
            revert InvalidProposalLength();
        }
        if (targets.length == 0) revert InvalidProposalLength();

        // Check proposer has enough votes (use current checkpoint)
        uint256 votes = _getCurrentVotes(msg.sender);
        if (votes < PROPOSAL_THRESHOLD) revert InsufficientVotes();

        // Check no active proposal
        uint256 latestId = latestProposalIds[msg.sender];
        if (latestId != 0) {
            ProposalState state = _state(latestId);
            if (state == ProposalState.Active || state == ProposalState.Pending) {
                revert ActiveProposalExists();
            }
        }

        // Create proposal
        proposalCount++;
        uint256 proposalId = proposalCount;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.startBlock = block.number + VOTING_DELAY / 12; // ~12s blocks
        proposal.endBlock = proposal.startBlock + VOTING_PERIOD / 12;

        latestProposalIds[msg.sender] = proposalId;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            proposal.startBlock,
            proposal.endBlock,
            description
        );

        return proposalId;
    }

    /// @notice Queue a succeeded proposal for execution
    /// @param proposalId Proposal to queue
    function queue(uint256 proposalId) external {
        if (_state(proposalId) != ProposalState.Succeeded) revert InvalidProposalState();

        Proposal storage proposal = proposals[proposalId];
        proposal.eta = block.timestamp + TIMELOCK_DELAY;

        emit ProposalQueued(proposalId, proposal.eta);
    }

    /// @notice Execute a queued proposal
    /// @param proposalId Proposal to execute
    function execute(uint256 proposalId) external payable nonReentrant {
        if (_state(proposalId) != ProposalState.Queued) revert InvalidProposalState();

        Proposal storage proposal = proposals[proposalId];

        if (block.timestamp < proposal.eta) revert TimelockNotReady();
        if (block.timestamp > proposal.eta + GRACE_PERIOD) revert ProposalExpired();

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, bytes memory returnData) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            if (!success) {
                // Bubble up revert
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }

        emit ProposalExecuted(proposalId);
    }

    /// @notice Cancel a proposal
    /// @param proposalId Proposal to cancel
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        // Only proposer or guardian can cancel
        if (msg.sender != proposal.proposer && msg.sender != guardian) {
            revert OnlyProposer();
        }

        ProposalState state = _state(proposalId);
        if (state == ProposalState.Executed) revert InvalidProposalState();

        proposal.canceled = true;

        emit ProposalCanceled(proposalId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Cast vote
    /// @param proposalId Proposal to vote on
    /// @param support 0 = Against, 1 = For, 2 = Abstain
    function castVote(uint256 proposalId, uint8 support) external {
        _castVote(msg.sender, proposalId, support, "");
    }

    /// @notice Cast vote with reason
    /// @param proposalId Proposal to vote on
    /// @param support 0 = Against, 1 = For, 2 = Abstain
    /// @param reason Vote reason
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        _castVote(msg.sender, proposalId, support, reason);
    }

    /// @notice Cast vote by signature
    /// @param proposalId Proposal to vote on
    /// @param support 0 = Against, 1 = For, 2 = Abstain
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("LuxDAO")),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Ballot(uint256 proposalId,uint8 support)"),
                proposalId,
                support
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v, r, s);

        require(signer != address(0), "Invalid signature");

        _castVote(signer, proposalId, support, "");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get proposal state
    function state(uint256 proposalId) external view returns (ProposalState) {
        return _state(proposalId);
    }

    /// @notice Get proposal info
    function getProposal(uint256 proposalId) external view returns (ProposalInfo memory) {
        Proposal storage p = proposals[proposalId];
        return ProposalInfo({
            id: p.id,
            proposer: p.proposer,
            eta: p.eta,
            startBlock: p.startBlock,
            endBlock: p.endBlock,
            forVotes: p.forVotes,
            againstVotes: p.againstVotes,
            abstainVotes: p.abstainVotes,
            canceled: p.canceled,
            executed: p.executed
        });
    }

    /// @notice Get proposal actions
    function getActions(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.calldatas);
    }

    /// @notice Get vote receipt
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /// @notice Check if account has voted
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].receipts[voter].hasVoted;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Update guardian
    function setGuardian(address newGuardian) external {
        if (msg.sender != guardian) revert OnlyGuardian();
        emit GuardianUpdated(guardian, newGuardian);
        guardian = newGuardian;
    }

    /// @notice Abdicate guardian powers
    function abdicateGuardian() external {
        if (msg.sender != guardian) revert OnlyGuardian();
        emit GuardianUpdated(guardian, address(0));
        guardian = address(0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _state(uint256 proposalId) internal view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.canceled) return ProposalState.Canceled;
        if (proposal.executed) return ProposalState.Executed;
        if (block.number <= proposal.startBlock) return ProposalState.Pending;
        if (block.number <= proposal.endBlock) return ProposalState.Active;

        // Voting ended
        if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < QUORUM_VOTES) {
            return ProposalState.Defeated;
        }

        if (proposal.eta == 0) return ProposalState.Succeeded;
        if (block.timestamp >= proposal.eta + GRACE_PERIOD) return ProposalState.Expired;

        return ProposalState.Queued;
    }

    function _castVote(
        address voter,
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) internal {
        if (_state(proposalId) != ProposalState.Active) revert VotingClosed();

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];

        if (receipt.hasVoted) revert AlreadyVoted();

        // Use snapshot at proposal startBlock to prevent flash loan attacks
        uint256 votes = _getVotes(voter, proposal.startBlock);

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        if (support == 0) {
            proposal.againstVotes += votes;
        } else if (support == 1) {
            proposal.forVotes += votes;
        } else if (support == 2) {
            proposal.abstainVotes += votes;
        }

        emit VoteCast(voter, proposalId, support, votes, reason);
    }

    /// @notice Get voting power for an account at a specific block
    /// @dev Uses snapshot-based voting to prevent flash loan attacks (HAL-03 compliant)
    /// @param account Address to check voting power for
    /// @param snapshotBlock Block number to snapshot votes at
    function _getVotes(address account, uint256 snapshotBlock) internal view returns (uint256) {
        // Use checkpointed balances to prevent flash loan attacks
        // Votes are snapshotted at the proposal's startBlock
        return token.getPastVotes(account, snapshotBlock);
    }

    /// @notice Get current voting power (for proposal threshold checks)
    /// @dev Uses previous block to ensure checkpoint exists
    function _getCurrentVotes(address account) internal view returns (uint256) {
        // Use block.number - 1 to ensure the checkpoint exists
        return token.getPastVotes(account, block.number - 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECEIVE
    // ═══════════════════════════════════════════════════════════════════════

    receive() external payable {}
}
