// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {ICharter} from "./interfaces/ICharter.sol";
import {IVotingTypes} from "./interfaces/IVotingTypes.sol";
import {IVotingWeight} from "./interfaces/IVotingWeight.sol";
import {IVoteTracker} from "./interfaces/IVoteTracker.sol";
import {IProposerAdapter} from "./interfaces/IProposerAdapter.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Charter
 * @author Lux Industries Inc
 * @notice Core voting charter for Lux governance
 * @dev Implements pluggable voting logic for proposals created through Council.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - EIP-4337 Light Account support for gasless voting
 * - Multiple voting configurations and proposer adapters
 * - Two-phase initialization (resolves circular dependencies)
 * - Late vote tracking for gasless voting infrastructure
 * - Veto voter authorization for parent DAO control
 *
 * Voting mechanics:
 * - Quorum = YES + ABSTAIN votes (NO votes don't count toward quorum)
 * - Basis = YES votes must exceed threshold percentage of (YES + NO)
 * - Pass = Voting ended AND quorum met AND basis met
 *
 * @custom:security-contact security@lux.network
 */
contract Charter is ICharter, ERC165, Initializable {
    // ======================================================================
    // STRUCTS
    // ======================================================================

    /**
     * @notice Internal representation of proposal voting state
     * @dev Matches ProposalVotingDetails from ICharter but used internally
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
     * @custom:storage-location erc7201:lux.governance.charter
     */
    struct CharterStorage {
        /// @notice Address that can initialize proposals and manage veto voters (typically Council)
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
        /// @notice Tracks authorized veto voting contracts
        mapping(address vetoVoter => bool authorized) authorizedVetoVoters;
        /// @notice Array of authorized veto voters for enumeration
        address[] vetoVotersList;
        /// @notice Tracks if vote was cast after voting period ended (for gasless voting)
        mapping(uint32 proposalId => bool lateVote) lateVoteCast;
        /// @notice Light account factory for gasless voting
        address lightAccountFactory;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant CHARTER_STORAGE_LOCATION =
        0x95295deadfd7c71125b4fbd75b5d49605029b50806f286522633fd9c072a4700;

    /**
     * @notice Denominator for basis percentage calculations (100%)
     */
    uint256 public constant BASIS_DENOMINATOR = 1_000_000;

    /**
     * @notice Minimum voting delay in blocks before voting starts
     * @dev Prevents flash loan governance attacks (C-01, C-02)
     */
    uint256 public constant MIN_VOTING_DELAY_BLOCKS = 1;

    /**
     * @notice Minimum voting delay in seconds before voting starts
     * @dev Prevents flash loan governance attacks - ensures snapshot is in past block
     */
    uint256 public constant MIN_VOTING_DELAY_SECONDS = 12;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (CharterStorage storage $) {
        assembly {
            $.slot := CHARTER_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    modifier onlyAdmin() {
        CharterStorage storage $ = _getStorage();
        if (msg.sender != $.admin) revert InvalidCharterAdmin();
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

        CharterStorage storage $ = _getStorage();
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
     * @dev Called after Council is deployed to resolve circular dependency
     * @param admin_ Address that manages this charter (typically Council)
     * @param votingConfigs_ Array of voting configurations
     */
    function initialize2(
        address admin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) public virtual reinitializer(2) {
        if (votingConfigs_.length == 0) revert NoVotingConfigs();

        CharterStorage storage $ = _getStorage();
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
        CharterStorage storage $ = _getStorage();
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

    function isAuthorizedVetoVoter(address vetoVoter) public view virtual returns (bool) {
        return _getStorage().authorizedVetoVoters[vetoVoter];
    }

    function vetoVoters() public view virtual returns (address[] memory) {
        return _getStorage().vetoVotersList;
    }

    // ======================================================================
    // QUORUM & BASIS LOGIC
    // ======================================================================

    /**
     * @notice Check if quorum is met (YES + ABSTAIN >= threshold)
     */
    function isQuorumMet(uint32 proposalId) public view virtual returns (bool) {
        CharterStorage storage $ = _getStorage();
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
        CharterStorage storage $ = _getStorage();
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
        CharterStorage storage $ = _getStorage();
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
        CharterStorage storage $ = _getStorage();
        if (!$.isProposerAdapter[adapter]) revert InvalidProposerAdapter();

        return IProposerAdapter(adapter).isProposer(proposer, adapterData);
    }

    /**
     * @notice Get voting timestamps for a proposal
     */
    function getVotingTimestamps(uint32 proposalId) public view virtual returns (uint48, uint48) {
        CharterStorage storage $ = _getStorage();
        ProposalVoting storage details = $.proposalVoting[proposalId];
        if (details.votingEndTimestamp == 0) revert ProposalNotInitialized();
        return (details.votingStartTimestamp, details.votingEndTimestamp);
    }

    /**
     * @notice Get voting start block for a proposal
     */
    function getVotingStartBlock(uint32 proposalId) public view virtual returns (uint32) {
        CharterStorage storage $ = _getStorage();
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

        CharterStorage storage $ = _getStorage();
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
     * @dev C-01/C-02 fix: Voting starts after MIN_VOTING_DELAY to prevent flash loan attacks
     */
    function initializeProposal(uint32 proposalId) public virtual onlyAdmin {
        CharterStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        // C-01/C-02 fix: Add minimum voting delay to prevent flash loan attacks
        // Voting starts in the future, ensuring snapshot block is in the past
        proposal.votingStartTimestamp = uint48(block.timestamp + MIN_VOTING_DELAY_SECONDS);
        proposal.votingEndTimestamp = uint48(block.timestamp + MIN_VOTING_DELAY_SECONDS + $.votingPeriod);
        proposal.votingStartBlock = uint32(block.number + MIN_VOTING_DELAY_BLOCKS);
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

        CharterStorage storage $ = _getStorage();
        ProposalVoting storage proposal = $.proposalVoting[proposalId];

        if (proposal.votingEndTimestamp == 0) revert ProposalNotInitialized();

        // C-01/C-02 fix: Check if voting has started (prevents same-block voting)
        if (block.timestamp < proposal.votingStartTimestamp) revert ProposalNotActive();

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
     * @notice Add authorized veto voter
     */
    function addVetoVoter(address vetoVoter) public virtual onlyAdmin {
        if (vetoVoter == address(0)) revert InvalidAddress();

        CharterStorage storage $ = _getStorage();

        if (!$.authorizedVetoVoters[vetoVoter]) {
            $.vetoVotersList.push(vetoVoter);
        }
        $.authorizedVetoVoters[vetoVoter] = true;

        emit VetoVoterAuthorizationChanged(vetoVoter, true);
    }

    /**
     * @notice Remove authorized veto voter
     */
    function removeVetoVoter(address vetoVoter) public virtual onlyAdmin {
        if (vetoVoter == address(0)) revert InvalidAddress();

        CharterStorage storage $ = _getStorage();

        if ($.authorizedVetoVoters[vetoVoter]) {
            // Swap-and-pop for gas-efficient removal
            for (uint256 i = 0; i < $.vetoVotersList.length;) {
                if ($.vetoVotersList[i] == vetoVoter) {
                    $.vetoVotersList[i] = $.vetoVotersList[$.vetoVotersList.length - 1];
                    $.vetoVotersList.pop();
                    break;
                }
                unchecked { ++i; }
            }
        }

        $.authorizedVetoVoters[vetoVoter] = false;

        emit VetoVoterAuthorizationChanged(vetoVoter, false);
    }

    // ======================================================================
    // INTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Resolve voter address (support for Light Accounts)
     * @dev H-01 fix: Properly verify light account ownership
     * The sender is expected to be the light account, and we resolve to the actual owner
     */
    function _resolveVoter(address sender, uint256 lightAccountIndex) internal view returns (address) {
        if (lightAccountIndex == 0) return sender;

        CharterStorage storage $ = _getStorage();
        if ($.lightAccountFactory == address(0)) return sender;

        // H-01 fix: The sender should be a light account calling on behalf of an owner
        // We need to verify the sender IS the light account at the given index for some owner
        // Then return that owner as the actual voter

        // Try to get the owner of the light account (sender)
        (bool ownerSuccess, bytes memory ownerData) = sender.staticcall(
            abi.encodeWithSignature("owner()")
        );

        if (ownerSuccess && ownerData.length == 32) {
            address owner = abi.decode(ownerData, (address));

            // Verify: factory.getAddress(owner, index) == sender
            (bool factorySuccess, bytes memory factoryData) = $.lightAccountFactory.staticcall(
                abi.encodeWithSignature("getAddress(address,uint256)", owner, lightAccountIndex)
            );

            if (factorySuccess && factoryData.length == 32) {
                address expectedLightAccount = abi.decode(factoryData, (address));
                // Verify sender is indeed the light account for this owner at this index
                if (expectedLightAccount == sender) {
                    return owner;
                }
            }
        }

        return sender;
    }

    // ======================================================================
    // INTERFACE COMPATIBILITY
    // ======================================================================

    /**
     * @notice Get charter admin (alias for admin())
     * @dev Required by ICharter interface
     */
    function charterAdmin() public view virtual returns (address) {
        return admin();
    }

    /**
     * @notice Get proposal voting details (alias for proposalVoting())
     * @dev Required by ICharter interface
     */
    function proposalVotingDetails(uint32 proposalId) public view virtual returns (ICharter.ProposalVotingDetails memory) {
        ProposalVoting memory pv = proposalVoting(proposalId);
        return ICharter.ProposalVotingDetails({
            votingStartTimestamp: pv.votingStartTimestamp,
            votingEndTimestamp: pv.votingEndTimestamp,
            votingStartBlock: pv.votingStartBlock,
            yesVotes: pv.yesVotes,
            noVotes: pv.noVotes,
            abstainVotes: pv.abstainVotes
        });
    }

    /**
     * @notice Get authorized veto voters (alias for vetoVoters())
     * @dev Required by ICharter interface
     */
    function authorizedVetoVoters() public view virtual returns (address[] memory) {
        return vetoVoters();
    }

    /**
     * @notice Check if vote was cast after voting period ended
     * @dev Required by ICharter interface (alias for lateVoteCast())
     */
    function voteCastedAfterVotingPeriodEnded(uint32 proposalId) public view virtual returns (bool) {
        return lateVoteCast(proposalId);
    }

    /**
     * @notice Validate vote for gasless voting (alias for validVote())
     * @dev Required by ICharter interface
     */
    function validCharterVote(
        address voter,
        uint32 proposalId,
        uint8 voteType,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData
    ) public view virtual returns (bool) {
        return validVote(voter, proposalId, voteType, votingConfigsData);
    }

    /**
     * @notice Add authorized veto voter (alias for addVetoVoter())
     * @dev Required by ICharter interface
     */
    function addAuthorizedVetoVoter(address vetoVoterContract) public virtual {
        addVetoVoter(vetoVoterContract);
    }

    /**
     * @notice Remove authorized veto voter (alias for removeVetoVoter())
     * @dev Required by ICharter interface
     */
    function removeAuthorizedVetoVoter(address vetoVoterContract) public virtual {
        removeVetoVoter(vetoVoterContract);
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(ICharter).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
