// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title MultiDAOGovernor
 * @author Lux Industries
 * @notice Multi-DAO governance system with configurable domain DAOs
 * @dev Enables specialized domain DAOs with distinct voting parameters
 *
 * Features:
 * - Configurable critical DAOs during deployment
 * - Per-DAO quorum and threshold requirements
 * - Delegation to specific DAOs
 * - Cross-DAO coordination for joint proposals
 * - Constitutional amendment process
 * - Community DAO registration
 */
contract MultiDAOGovernor is AccessControl, ReentrancyGuard {

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant COUNCIL_ROLE = keccak256("COUNCIL_ROLE");
    bytes32 public constant PROPOSAL_ROLE = keccak256("PROPOSAL_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant DAO_REGISTRY_ROLE = keccak256("DAO_REGISTRY_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct DAOConfig {
        bytes32 id;
        string name;
        string symbol;
        uint16 quorumBasisPoints;      // e.g., 2000 = 20%
        uint16 thresholdBasisPoints;   // e.g., 6700 = 67%
    }

    struct DAO {
        bytes32 id;
        string name;
        string symbol;
        uint16 quorumBasisPoints;
        uint16 thresholdBasisPoints;
        bytes32 domainHash;
        uint256 totalDelegated;
        bool isCritical;
        bool active;
    }

    struct Proposal {
        bytes32 id;
        address proposer;
        bytes32[] targetDAOs;
        string description;
        bytes callData;
        uint256 snapshotBlock;
        uint256 startBlock;
        uint256 endBlock;
        ProposalState state;
        bool isConstitutional;
        mapping(bytes32 => DAOVote) daoVotes;
    }

    struct DAOVote {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool tallied;
        bool passed;
    }

    struct Delegation {
        mapping(bytes32 => address) daoDelegate;
        mapping(bytes32 => uint256) daoWeight;
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Executed,
        Expired
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant VOTING_PERIOD = 50400;      // ~7 days at 12s blocks
    uint256 public constant VOTING_DELAY = 1;           // 1 block
    uint256 public constant TIMELOCK_STANDARD = 17280;  // ~48 hours
    uint256 public constant TIMELOCK_TREASURY = 25920;  // ~72 hours
    uint256 public constant TIMELOCK_CONSTITUTIONAL = 50400; // ~7 days

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Governance token
    ERC20Votes public governanceToken;

    /// @notice DAO registry
    mapping(bytes32 => DAO) public daos;
    bytes32[] public daoIds;
    bytes32[] public criticalDaoIds;

    /// @notice Strategy DAO ID (for constitutional amendments)
    bytes32 public strategyDAOId;

    /// @notice Constitutional approval count required
    uint256 public constitutionalApprovalCount;

    /// @notice Proposals
    mapping(bytes32 => Proposal) internal _proposals;
    bytes32[] public proposalIds;
    uint256 public proposalCount;

    /// @notice Delegations
    mapping(address => Delegation) internal _delegations;

    /// @notice Votes cast (proposalId => voter => DAO => voted)
    mapping(bytes32 => mapping(address => mapping(bytes32 => bool))) public hasVoted;

    /// @notice Proposal threshold (tokens required to propose)
    uint256 public proposalThreshold;

    /// @notice Bridge for cross-chain voting
    address public votingBridge;

    /// @notice Emergency pause
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event DAOCreated(bytes32 indexed id, string name, string symbol, bool isCritical);
    event DAOUpdated(bytes32 indexed id, uint16 quorum, uint16 threshold);
    event DAODeactivated(bytes32 indexed id);
    event ProposalCreated(
        bytes32 indexed proposalId,
        address indexed proposer,
        bytes32[] targetDAOs,
        string description,
        bool isConstitutional
    );
    event ProposalCanceled(bytes32 indexed proposalId);
    event ProposalExecuted(bytes32 indexed proposalId);
    event VoteCast(
        bytes32 indexed proposalId,
        bytes32 indexed dao,
        address indexed voter,
        uint8 support,
        uint256 weight
    );
    event DelegationSet(address indexed delegator, bytes32 indexed dao, address indexed delegate);
    event TallyReceived(bytes32 indexed proposalId, bytes32 indexed dao, bool passed);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error DAONotFound();
    error DAOAlreadyExists();
    error ProposalNotFound();
    error ProposalNotActive();
    error ProposalAlreadyExists();
    error InsufficientVotingPower();
    error AlreadyVoted();
    error InvalidState();
    error Unauthorized();
    error Paused();
    error QuorumNotReached();
    error ThresholdNotReached();
    error ConstitutionalRequirementsNotMet();
    error CannotDeactivateCriticalDAO();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the MultiDAOGovernor
     * @param _governanceToken Governance token address
     * @param _admin Admin address
     * @param _votingBridge Bridge for cross-chain voting
     * @param _proposalThreshold Tokens required to propose
     * @param _criticalDAOs Array of critical DAO configurations
     * @param _strategyDAOId ID of the strategy DAO (for constitutional amendments)
     * @param _constitutionalApprovalCount DAOs required for constitutional changes
     */
    constructor(
        address _governanceToken,
        address _admin,
        address _votingBridge,
        uint256 _proposalThreshold,
        DAOConfig[] memory _criticalDAOs,
        bytes32 _strategyDAOId,
        uint256 _constitutionalApprovalCount
    ) {
        governanceToken = ERC20Votes(_governanceToken);
        votingBridge = _votingBridge;
        proposalThreshold = _proposalThreshold;
        strategyDAOId = _strategyDAOId;
        constitutionalApprovalCount = _constitutionalApprovalCount;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(COUNCIL_ROLE, _admin);
        if (_votingBridge != address(0)) {
            _grantRole(BRIDGE_ROLE, _votingBridge);
        }

        // Initialize critical DAOs
        for (uint256 i = 0; i < _criticalDAOs.length; i++) {
            _createDAO(
                _criticalDAOs[i].id,
                _criticalDAOs[i].name,
                _criticalDAOs[i].symbol,
                _criticalDAOs[i].quorumBasisPoints,
                _criticalDAOs[i].thresholdBasisPoints,
                true
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    function _createDAO(
        bytes32 id,
        string memory name,
        string memory symbol,
        uint16 quorum,
        uint16 threshold,
        bool isCritical
    ) internal {
        daos[id] = DAO({
            id: id,
            name: name,
            symbol: symbol,
            quorumBasisPoints: quorum,
            thresholdBasisPoints: threshold,
            domainHash: keccak256(abi.encodePacked(name)),
            totalDelegated: 0,
            isCritical: isCritical,
            active: true
        });
        daoIds.push(id);
        if (isCritical) {
            criticalDaoIds.push(id);
        }
        emit DAOCreated(id, name, symbol, isCritical);
    }

    /**
     * @notice Register a new community DAO
     * @param id Unique DAO identifier
     * @param name DAO name
     * @param symbol DAO symbol
     * @param quorum Quorum in basis points
     * @param threshold Threshold in basis points
     */
    function registerDAO(
        bytes32 id,
        string calldata name,
        string calldata symbol,
        uint16 quorum,
        uint16 threshold
    ) external onlyRole(DAO_REGISTRY_ROLE) {
        if (daos[id].active) revert DAOAlreadyExists();
        _createDAO(id, name, symbol, quorum, threshold, false);
    }

    /**
     * @notice Deactivate a community DAO (critical DAOs cannot be deactivated)
     */
    function deactivateDAO(bytes32 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!daos[id].active) revert DAONotFound();
        if (daos[id].isCritical) revert CannotDeactivateCriticalDAO();
        daos[id].active = false;
        emit DAODeactivated(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DELEGATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Delegate voting power to a specific DAO representative
     */
    function delegateToDAO(bytes32 daoId, address delegate) external {
        if (!daos[daoId].active) revert DAONotFound();
        _delegations[msg.sender].daoDelegate[daoId] = delegate;
        emit DelegationSet(msg.sender, daoId, delegate);
    }

    /**
     * @notice Delegate with weight split across multiple DAOs
     */
    function delegateMultiple(
        bytes32[] calldata daoIdList,
        address[] calldata delegates,
        uint256[] calldata weights
    ) external {
        require(
            daoIdList.length == delegates.length &&
            delegates.length == weights.length,
            "Length mismatch"
        );

        uint256 totalWeight;
        for (uint256 i = 0; i < daoIdList.length; i++) {
            if (!daos[daoIdList[i]].active) revert DAONotFound();
            _delegations[msg.sender].daoDelegate[daoIdList[i]] = delegates[i];
            _delegations[msg.sender].daoWeight[daoIdList[i]] = weights[i];
            totalWeight += weights[i];
            emit DelegationSet(msg.sender, daoIdList[i], delegates[i]);
        }
        require(totalWeight == BASIS_POINTS, "Weights must sum to 10000");
    }

    /**
     * @notice Self-delegate to retain direct voting power
     */
    function selfDelegate(bytes32 daoId) external {
        if (!daos[daoId].active) revert DAONotFound();
        _delegations[msg.sender].daoDelegate[daoId] = msg.sender;
        emit DelegationSet(msg.sender, daoId, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROPOSALS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new proposal
     */
    function createProposal(
        bytes32[] calldata targetDAOs,
        string calldata description,
        bytes calldata callData,
        bool isConstitutional
    ) external nonReentrant returns (bytes32 proposalId) {
        if (paused) revert Paused();

        uint256 votingPower = governanceToken.getVotes(msg.sender);
        if (votingPower < proposalThreshold) revert InsufficientVotingPower();

        for (uint256 i = 0; i < targetDAOs.length; i++) {
            if (!daos[targetDAOs[i]].active) revert DAONotFound();
        }

        if (isConstitutional) {
            bool hasStrategy = false;
            for (uint256 i = 0; i < targetDAOs.length; i++) {
                if (targetDAOs[i] == strategyDAOId) {
                    hasStrategy = true;
                    break;
                }
            }
            require(hasStrategy, "Constitutional requires strategy DAO");
            require(targetDAOs.length >= constitutionalApprovalCount, "Need more DAOs");
        }

        proposalId = keccak256(abi.encodePacked(
            msg.sender,
            block.number,
            proposalCount++
        ));

        Proposal storage proposal = _proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.targetDAOs = targetDAOs;
        proposal.description = description;
        proposal.callData = callData;
        proposal.snapshotBlock = block.number;
        proposal.startBlock = block.number + VOTING_DELAY;
        proposal.endBlock = block.number + VOTING_DELAY + VOTING_PERIOD;
        proposal.state = ProposalState.Pending;
        proposal.isConstitutional = isConstitutional;

        proposalIds.push(proposalId);

        emit ProposalCreated(proposalId, msg.sender, targetDAOs, description, isConstitutional);
    }

    /**
     * @notice Cancel a proposal
     */
    function cancelProposal(bytes32 proposalId) external {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == bytes32(0)) revert ProposalNotFound();

        bool isProposer = msg.sender == proposal.proposer;
        bool isCouncil = hasRole(COUNCIL_ROLE, msg.sender);

        if (!isProposer && !isCouncil) revert Unauthorized();
        if (proposal.state != ProposalState.Pending && proposal.state != ProposalState.Active) {
            revert InvalidState();
        }

        proposal.state = ProposalState.Canceled;
        emit ProposalCanceled(proposalId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Cast vote on a proposal for a specific DAO
     */
    function castVote(
        bytes32 proposalId,
        bytes32 daoId,
        uint8 support
    ) external nonReentrant {
        if (paused) revert Paused();

        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == bytes32(0)) revert ProposalNotFound();
        if (block.number < proposal.startBlock || block.number > proposal.endBlock) {
            revert ProposalNotActive();
        }
        if (hasVoted[proposalId][msg.sender][daoId]) revert AlreadyVoted();

        address delegate = _delegations[msg.sender].daoDelegate[daoId];
        if (delegate != address(0) && delegate != msg.sender) {
            revert Unauthorized();
        }

        uint256 weight = governanceToken.getPastVotes(msg.sender, proposal.snapshotBlock);
        if (weight == 0) revert InsufficientVotingPower();

        hasVoted[proposalId][msg.sender][daoId] = true;

        DAOVote storage vote = proposal.daoVotes[daoId];
        if (support == 0) {
            vote.againstVotes += weight;
        } else if (support == 1) {
            vote.forVotes += weight;
        } else {
            vote.abstainVotes += weight;
        }

        emit VoteCast(proposalId, daoId, msg.sender, support, weight);
    }

    /**
     * @notice Receive tally from bridge
     */
    function receiveTally(
        bytes32 proposalId,
        bytes32 daoId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        bytes calldata /* attestation */
    ) external onlyRole(BRIDGE_ROLE) {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == bytes32(0)) revert ProposalNotFound();

        DAOVote storage vote = proposal.daoVotes[daoId];
        vote.forVotes = forVotes;
        vote.againstVotes = againstVotes;
        vote.abstainVotes = abstainVotes;
        vote.tallied = true;

        DAO storage dao = daos[daoId];
        uint256 totalVotes = forVotes + againstVotes + abstainVotes;
        uint256 totalSupply = governanceToken.getPastTotalSupply(proposal.snapshotBlock);

        bool quorumReached = totalVotes * BASIS_POINTS >= totalSupply * dao.quorumBasisPoints;
        bool thresholdReached = forVotes * BASIS_POINTS >= totalVotes * dao.thresholdBasisPoints;

        vote.passed = quorumReached && thresholdReached;

        emit TallyReceived(proposalId, daoId, vote.passed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Finalize proposal after voting ends
     */
    function finalizeProposal(bytes32 proposalId) external {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == bytes32(0)) revert ProposalNotFound();
        if (block.number <= proposal.endBlock) revert ProposalNotActive();
        if (proposal.state != ProposalState.Pending && proposal.state != ProposalState.Active) {
            revert InvalidState();
        }

        uint256 passedCount = 0;
        for (uint256 i = 0; i < proposal.targetDAOs.length; i++) {
            DAOVote storage vote = proposal.daoVotes[proposal.targetDAOs[i]];
            if (!vote.tallied) revert InvalidState();
            if (vote.passed) passedCount++;
        }

        if (proposal.isConstitutional) {
            if (passedCount < constitutionalApprovalCount) {
                proposal.state = ProposalState.Defeated;
                return;
            }
            if (!proposal.daoVotes[strategyDAOId].passed) {
                proposal.state = ProposalState.Defeated;
                return;
            }
        } else {
            if (passedCount != proposal.targetDAOs.length) {
                proposal.state = ProposalState.Defeated;
                return;
            }
        }

        proposal.state = ProposalState.Succeeded;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getDAO(bytes32 id) external view returns (DAO memory) {
        return daos[id];
    }

    function getDAOCount() external view returns (uint256) {
        return daoIds.length;
    }

    function getCriticalDAOCount() external view returns (uint256) {
        return criticalDaoIds.length;
    }

    function getCriticalDAOs() external view returns (bytes32[] memory) {
        return criticalDaoIds;
    }

    function getProposalState(bytes32 proposalId) external view returns (ProposalState) {
        return _proposals[proposalId].state;
    }

    function getDelegate(address delegator, bytes32 daoId) external view returns (address) {
        return _delegations[delegator].daoDelegate[daoId];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function updateDAO(
        bytes32 id,
        uint16 quorum,
        uint16 threshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!daos[id].active) revert DAONotFound();
        daos[id].quorumBasisPoints = quorum;
        daos[id].thresholdBasisPoints = threshold;
        emit DAOUpdated(id, quorum, threshold);
    }

    function setVotingBridge(address _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (votingBridge != address(0)) {
            _revokeRole(BRIDGE_ROLE, votingBridge);
        }
        votingBridge = _bridge;
        if (_bridge != address(0)) {
            _grantRole(BRIDGE_ROLE, _bridge);
        }
    }

    function setPaused(bool _paused) external onlyRole(COUNCIL_ROLE) {
        paused = _paused;
    }

    function setProposalThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proposalThreshold = _threshold;
    }
}
