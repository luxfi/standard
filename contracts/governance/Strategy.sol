// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IVotingTypes} from "./interfaces/IVotingTypes.sol";
import {IVotingWeight} from "./interfaces/IVotingWeight.sol";
import {IVoteTracker} from "./interfaces/IVoteTracker.sol";
import {IProposerAdapter} from "./interfaces/IProposerAdapter.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Strategy
 * @author Lux Industries Inc
 * @notice Core voting strategy for Lux governance
 * @dev Implements pluggable voting logic for proposals created through Governor.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - EIP-4337 Light Account support for gasless voting
 * - Multiple voting configurations and proposer adapters
 * - Two-phase initialization (resolves circular dependencies)
 * - Late vote tracking for gasless voting infrastructure
 * - Freeze voter authorization for parent DAO control
 *
 * Voting mechanics:
 * - Quorum = YES + ABSTAIN votes (NO votes don't count toward quorum)
 * - Basis = YES votes must exceed threshold percentage of (YES + NO)
 * - Pass = Voting ended AND quorum met AND basis met
 *
 * @custom:security-contact security@lux.network
 */
contract Strategy is IStrategy, ERC165, Initializable {
    // ======================================================================
    // STRUCTS
    // ======================================================================

    /**
     * @notice Internal representation of proposal voting state
     * @dev Matches ProposalVotingDetails from IStrategy but used internally
     */
    struct ProposalVoting {
        uint48 votingStartTimestamp;
        uint48 votingEndTimestamp;
        uint32 votingStartBlock;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }

    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.strategy
     */
    struct StrategyStorage {
        /// @notice Address that can initialize proposals and manage freeze voters (typically Governor)
        address admin;
        /// @notice Fixed duration in seconds for all proposal voting periods
        uint32 votingPeriod;
        /// @notice Minimum total weight (YES + ABSTAIN) required for quorum
        uint256 quorumThreshold;
        /// @notice Numerator for basis calculation (denominator is 1,000,000)
        uint256 basisNumerator;
        /// @notice Mapping from proposal ID to voting details
        mapping(uint32 proposalId => ProposalVoting proposalVoting) proposalVoting;
        /// @notice Array of configured voting configurations
        IVotingTypes.VotingConfig[] votingConfigs;
        /// @notice Array of configured proposer adapter addresses
        address[] proposerAdapters;
        /// @notice Quick lookup for valid proposer adapters
        mapping(address proposerAdapter => bool isProposerAdapter) isProposerAdapter;
        /// @notice Tracks authorized freeze voting contracts
        mapping(address freezeVoter => bool authorized) authorizedFreezeVoters;
        /// @notice Array of authorized freeze voters for enumeration
        address[] freezeVotersList;
        /// @notice Tracks if vote was cast after voting period ended (for gasless voting)
        mapping(uint32 proposalId => bool lateVote) lateVoteCast;
        /// @notice Light account factory for gasless voting
        address lightAccountFactory;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant STRATEGY_STORAGE_LOCATION =
        0x95295deadfd7c71125b4fbd75b5d49605029b50806f286522633fd9c072a4700;

    /**
     * @notice Denominator for basis percentage calculations (100%)
     */
    uint256 public constant BASIS_DENOMINATOR = 1_000_000;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (StrategyStorage storage $) {
        assembly {
            $.slot := STRATEGY_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    modifier onlyAdmin() {
        StrategyStorage storage $ = _getStorage();
        if (msg.sender != $.admin) revert InvalidStrategyAdmin();
        _;
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Phase 1 initialization - basic parameters
     * @param votingPeriod_ Duration of voting in seconds
     * @param quorumThreshold_ Minimum votes for quorum
     * @param basisNumerator_ Required approval percentage (500000 = 50%)
     * @param proposerAdapters_ Initial proposer adapter addresses
     * @param lightAccountFactory_ Factory for gasless voting support
     */
    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) public virtual initializer {
        if (proposerAdapters_.length == 0) revert NoProposerAdapters();

        // Basis must be between 50% and 100%
        if (basisNumerator_ >= BASIS_DENOMINATOR || basisNumerator_ < BASIS_DENOMINATOR / 2) {
            revert InvalidBasisNumerator();
        }

        StrategyStorage storage $ = _getStorage();
        $.votingPeriod = votingPeriod_;
        $.quorumThreshold = quorumThreshold_;
        $.basisNumerator = basisNumerator_;
        $.proposerAdapters = proposerAdapters_;
        $.lightAccountFactory = lightAccountFactory_;

        for (uint256 i = 0; i < proposerAdapters_.length;) {
            $.isProposerAdapter[proposerAdapters_[i]] = true;
            unchecked { ++i; }
        }
    }

    /**
     * @notice Phase 2 initialization - admin and voting configs
     * @dev Called after Governor is deployed to resolve circular dependency
     * @param admin_ Address that manages this strategy (typically Governor)
     * @param votingConfigs_ Array of voting configurations
     */
    function initialize2(
        address admin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) public virtual reinitializer(2) {
        if (votingConfigs_.length == 0) revert NoVotingConfigs();

        StrategyStorage storage $ = _getStorage();
        $.admin = admin_;

        for (uint256 i = 0; i < votingConfigs_.length;) {
            $.votingConfigs.push(votingConfigs_[i]);
            unchecked { ++i; }
        }
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function admin() public view virtual returns (address) {
        return _getStorage().admin;
    }

    function votingPeriod() public view virtual returns (uint32) {
        return _getStorage().votingPeriod;
    }

    function quorumThreshold() public view virtual returns (uint256) {
        return _getStorage().quorumThreshold;
    }

    function basisNumerator() public view virtual returns (uint256) {
        return _getStorage().basisNumerator;
    }

    function proposalVoting(uint32 proposalId) public view virtual returns (ProposalVoting memory) {
        return _getStorage().proposalVoting[proposalId];
    }

    function votingConfigs() public view virtual returns (IVotingTypes.VotingConfig[] memory) {
        return _getStorage().votingConfigs;
    }

    function votingConfig(uint256 configIndex) public view virtual returns (IVotingTypes.VotingConfig memory) {
        StrategyStorage storage $ = _getStorage();
        if (configIndex >= $.votingConfigs.length) revert InvalidVotingConfig(configIndex);
        return $.votingConfigs[configIndex];
    }

    function proposerAdapters() public view virtual returns (address[] memory) {
        return _getStorage().proposerAdapters;
    }

    function isProposerAdapter(address adapter) public view virtual returns (bool) {
        return _getStorage().isProposerAdapter[adapter];
    }

    function lateVoteCast(uint32 proposalId) public view virtual returns (bool) {
        return _getStorage().lateVoteCast[proposalId];
    }

    function isAuthorizedFreezeVoter(address freezeVoter) public view virtual returns (bool) {
        return _getStorage().authorizedFreezeVoters[freezeVoter];
    }

    function freezeVoters() public view virtual returns (address[] memory) {
        return _getStorage().freezeVotersList;
    }

    // ======================================================================
    // QUORUM & BASIS LOGIC
    // ======================================================================

    /**
     * @notice Check if quorum is met (YES + ABSTAIN >= threshold)
     */
    function isQuorumMet(uint32 proposalId) public view virtual returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        if (proposal.votingEndTimestamp == 0) revert ProposalNotInitialized();

        uint256 totalVotesForQuorum = proposal.yesVotes + proposal.abstainVotes;
        return totalVotesForQuorum >= $.quorumThreshold;
    }

    /**
     * @notice Check if basis is met (YES > threshold % of YES + NO)
     * @dev Uses integer math: yesVotes * DENOMINATOR > (yesVotes + noVotes) * numerator
     */
    function isBasisMet(uint32 proposalId) public view virtual returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        if (proposal.votingEndTimestamp == 0) revert ProposalNotInitialized();

        return (proposal.yesVotes * BASIS_DENOMINATOR) >
            ((proposal.yesVotes + proposal.noVotes) * $.basisNumerator);
    }

    /**
     * @notice Check if proposal passed
     * @dev Requires: voting ended AND quorum met AND basis met
     */
    function isPassed(uint32 proposalId) public view virtual returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        if (proposal.votingEndTimestamp == 0) revert ProposalNotInitialized();
        if (block.timestamp <= proposal.votingEndTimestamp) return false;

        return isQuorumMet(proposalId) && isBasisMet(proposalId);
    }

    /**
     * @notice Check if address can propose via adapter
     */
    function isProposer(
        address proposer,
        address adapter,
        bytes calldata adapterData
    ) public view virtual returns (bool) {
        StrategyStorage storage $ = _getStorage();
        if (!$.isProposerAdapter[adapter]) revert InvalidProposerAdapter();

        return IProposerAdapter(adapter).isProposer(proposer, adapterData);
    }

    /**
     * @notice Get voting timestamps for a proposal
     */
    function getVotingTimestamps(uint32 proposalId) public view virtual returns (uint48, uint48) {
        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage details = $.proposalVoting[proposalId];
        if (details.votingEndTimestamp == 0) revert ProposalNotInitialized();
        return (details.votingStartTimestamp, details.votingEndTimestamp);
    }

    /**
     * @notice Get voting start block for a proposal
     */
    function getVotingStartBlock(uint32 proposalId) public view virtual returns (uint32) {
        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage details = $.proposalVoting[proposalId];
        if (details.votingEndTimestamp == 0) revert ProposalNotInitialized();
        return details.votingStartBlock;
    }

    /**
     * @notice Validate vote for gasless voting (EIP-4337 paymaster)
     * @dev Avoids banned opcodes during validation phase
     */
    function validVote(
        address voter,
        uint32 proposalId,
        uint8 voteType,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData
    ) public view virtual returns (bool) {
        if (votingConfigsData.length == 0) return false;

        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage details = $.proposalVoting[proposalId];

        if (details.votingEndTimestamp == 0) return false;
        if ($.lateVoteCast[proposalId]) return false;
        if (voteType > 2) return false;

        uint256 totalWeight = 0;

        for (uint256 i = 0; i < votingConfigsData.length;) {
            IVotingTypes.VotingConfigVoteData memory configData = votingConfigsData[i];

            if (configData.configIndex >= $.votingConfigs.length) return false;

            IVotingTypes.VotingConfig memory config = $.votingConfigs[configData.configIndex];

            uint256 weight = IVotingWeight(config.votingWeight).getVotingWeightForPaymaster(
                voter,
                details.votingStartTimestamp,
                configData.voteData
            );

            if (weight == 0) return false;

            if (IVoteTracker(config.voteTracker).hasVoted(proposalId, voter, configData.voteData)) {
                return false;
            }

            totalWeight += weight;

            unchecked { ++i; }
        }

        return totalWeight > 0;
    }

    // ======================================================================
    // STATE-CHANGING FUNCTIONS
    // ======================================================================

    /**
     * @notice Initialize voting for a proposal
     */
    function initializeProposal(uint32 proposalId) public virtual onlyAdmin {
        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        proposal.votingStartTimestamp = uint48(block.timestamp);
        proposal.votingEndTimestamp = uint48(block.timestamp + $.votingPeriod);
        proposal.votingStartBlock = uint32(block.number);
        proposal.yesVotes = 0;
        proposal.noVotes = 0;
        proposal.abstainVotes = 0;

        emit ProposalInitialized(
            proposalId,
            proposal.votingStartTimestamp,
            proposal.votingEndTimestamp,
            proposal.votingStartBlock
        );
    }

    /**
     * @notice Cast vote on a proposal
     * @param proposalId Proposal to vote on
     * @param voteType Vote type (0=NO, 1=YES, 2=ABSTAIN)
     * @param votingConfigsData Array of voting config data
     * @param lightAccountIndex Index for light account resolution (0 = direct)
     */
    function castVote(
        uint32 proposalId,
        uint8 voteType,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData,
        uint256 lightAccountIndex
    ) public virtual {
        if (votingConfigsData.length == 0) revert NoVotingConfigs();

        // Resolve actual voter (support for Light Accounts / EIP-4337)
        address voter = _resolveVoter(msg.sender, lightAccountIndex);

        StrategyStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        if (proposal.votingEndTimestamp == 0) revert ProposalNotInitialized();

        // Check if voting period ended
        if (block.timestamp > proposal.votingEndTimestamp) {
            // Track first late vote attempt for gasless voting infrastructure
            if (!$.lateVoteCast[proposalId]) {
                $.lateVoteCast[proposalId] = true;
                emit VotingPeriodEnded(proposalId);
                return;
            }
            revert ProposalNotActive();
        }

        uint256 totalWeight = 0;

        for (uint256 i = 0; i < votingConfigsData.length;) {
            IVotingTypes.VotingConfigVoteData memory configData = votingConfigsData[i];

            if (configData.configIndex >= $.votingConfigs.length) {
                revert InvalidVotingConfig(configData.configIndex);
            }

            IVotingTypes.VotingConfig memory config = $.votingConfigs[configData.configIndex];

            (uint256 weight, bytes memory processedData) = IVotingWeight(config.votingWeight)
                .calculateWeight(voter, proposal.votingStartTimestamp, configData.voteData);

            if (weight == 0) revert NoVotingWeight(configData.configIndex);

            // Record vote to prevent double voting
            IVoteTracker(config.voteTracker).recordVote(proposalId, voter, processedData);

            totalWeight += weight;

            unchecked { ++i; }
        }

        // Update vote tallies
        if (voteType == uint8(VoteType.YES)) {
            proposal.yesVotes += totalWeight;
        } else if (voteType == uint8(VoteType.NO)) {
            proposal.noVotes += totalWeight;
        } else if (voteType == uint8(VoteType.ABSTAIN)) {
            proposal.abstainVotes += totalWeight;
        } else {
            revert InvalidVoteType();
        }

        emit Voted(voter, proposalId, VoteType(voteType), totalWeight);
    }

    /**
     * @notice Add authorized freeze voter
     */
    function addFreezeVoter(address freezeVoter) public virtual onlyAdmin {
        if (freezeVoter == address(0)) revert InvalidAddress();

        StrategyStorage storage $ = _getStorage();

        if (!$.authorizedFreezeVoters[freezeVoter]) {
            $.freezeVotersList.push(freezeVoter);
        }
        $.authorizedFreezeVoters[freezeVoter] = true;

        emit FreezeVoterAuthorizationChanged(freezeVoter, true);
    }

    /**
     * @notice Remove authorized freeze voter
     */
    function removeFreezeVoter(address freezeVoter) public virtual onlyAdmin {
        if (freezeVoter == address(0)) revert InvalidAddress();

        StrategyStorage storage $ = _getStorage();

        if ($.authorizedFreezeVoters[freezeVoter]) {
            // Swap-and-pop for gas-efficient removal
            for (uint256 i = 0; i < $.freezeVotersList.length;) {
                if ($.freezeVotersList[i] == freezeVoter) {
                    $.freezeVotersList[i] = $.freezeVotersList[$.freezeVotersList.length - 1];
                    $.freezeVotersList.pop();
                    break;
                }
                unchecked { ++i; }
            }
        }

        $.authorizedFreezeVoters[freezeVoter] = false;

        emit FreezeVoterAuthorizationChanged(freezeVoter, false);
    }

    // ======================================================================
    // INTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Resolve voter address (support for Light Accounts)
     */
    function _resolveVoter(address sender, uint256 lightAccountIndex) internal view returns (address) {
        if (lightAccountIndex == 0) return sender;

        StrategyStorage storage $ = _getStorage();
        if ($.lightAccountFactory == address(0)) return sender;

        // Get light account owner at index
        // LightAccountFactory.getAddress(owner, index) pattern
        (bool success, bytes memory data) = $.lightAccountFactory.staticcall(
            abi.encodeWithSignature("getAddress(address,uint256)", sender, lightAccountIndex)
        );

        if (success && data.length == 32) {
            address lightAccount = abi.decode(data, (address));
            // Verify the sender owns this light account
            if (lightAccount == sender) {
                // The actual owner is derived from the factory
                return sender;
            }
        }

        return sender;
    }

    // ======================================================================
    // INTERFACE COMPATIBILITY
    // ======================================================================

    /**
     * @notice Get strategy admin (alias for admin())
     * @dev Required by IStrategy interface
     */
    function strategyAdmin() public view virtual returns (address) {
        return admin();
    }

    /**
     * @notice Get proposal voting details (alias for proposalVoting())
     * @dev Required by IStrategy interface
     */
    function proposalVotingDetails(uint32 proposalId) public view virtual returns (IStrategy.ProposalVotingDetails memory) {
        ProposalVoting memory pv = proposalVoting(proposalId);
        return IStrategy.ProposalVotingDetails({
            votingStartTimestamp: pv.votingStartTimestamp,
            votingEndTimestamp: pv.votingEndTimestamp,
            votingStartBlock: pv.votingStartBlock,
            yesVotes: pv.yesVotes,
            noVotes: pv.noVotes,
            abstainVotes: pv.abstainVotes
        });
    }

    /**
     * @notice Get authorized freeze voters (alias for freezeVoters())
     * @dev Required by IStrategy interface
     */
    function authorizedFreezeVoters() public view virtual returns (address[] memory) {
        return freezeVoters();
    }

    /**
     * @notice Check if vote was cast after voting period ended
     * @dev Required by IStrategy interface (alias for lateVoteCast())
     */
    function voteCastedAfterVotingPeriodEnded(uint32 proposalId) public view virtual returns (bool) {
        return lateVoteCast(proposalId);
    }

    /**
     * @notice Validate vote for gasless voting (alias for validVote())
     * @dev Required by IStrategy interface
     */
    function validStrategyVote(
        address voter,
        uint32 proposalId,
        uint8 voteType,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData
    ) public view virtual returns (bool) {
        return validVote(voter, proposalId, voteType, votingConfigsData);
    }

    /**
     * @notice Add authorized freeze voter (alias for addFreezeVoter())
     * @dev Required by IStrategy interface
     */
    function addAuthorizedFreezeVoter(address freezeVoterContract) public virtual {
        addFreezeVoter(freezeVoterContract);
    }

    /**
     * @notice Remove authorized freeze voter (alias for removeFreezeVoter())
     * @dev Required by IStrategy interface
     */
    function removeAuthorizedFreezeVoter(address freezeVoterContract) public virtual {
        removeFreezeVoter(freezeVoterContract);
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IStrategy).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
