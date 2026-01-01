// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import "../FHE.sol";
import {TFHE} from "../threshold/TFHE.sol";
import {TFHEApp} from "../threshold/TFHEApp.sol";
import {IStrategy} from "../../governance/interfaces/IStrategy.sol";
import {IVotingTypes} from "../../governance/interfaces/IVotingTypes.sol";
import {IVotingWeight} from "../../governance/interfaces/IVotingWeight.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title BlendedConfidentialStrategy
 * @author Lux Industries Inc
 * @notice Hybrid voting strategy supporting both confidential and public vote sources
 * @dev Extends IStrategy with blended voting where:
 *      - Some vote sources are encrypted (confidential)
 *      - Some vote sources are public (transparent)
 *      - Final tally combines both with configurable weights
 *
 * Use cases:
 * 1. Tiered governance: DAO token votes public, team/foundation votes private
 * 2. Hybrid privacy: Critical proposals use encrypted voting, routine ones public
 * 3. Multi-source: xLUX (public), DLUX (public), NFT holders (private)
 *
 * Architecture:
 *   VotingConfig[].isConfidential → true: FHE encrypted, false: public counter
 *   Final result = blend(confidential_result, public_result)
 */
contract BlendedConfidentialStrategy is
    IStrategy,
    TFHEApp,
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    // ============================================================
    // TYPES
    // ============================================================

    /// @notice Extended voting config with privacy flag
    struct BlendedVotingConfig {
        address votingWeight;       // IVotingWeight implementation
        uint256 multiplier;         // Weight multiplier (1e18 = 1x)
        bool isConfidential;        // True = encrypted, False = public
        string description;         // Human-readable description
    }

    /// @notice Proposal voting state
    struct BlendedProposalVoting {
        uint48 votingStartTimestamp;
        uint48 votingEndTimestamp;
        uint32 votingStartBlock;

        // Confidential vote tallies (encrypted)
        euint256 confidentialYesVotes;
        euint256 confidentialNoVotes;
        euint256 confidentialAbstainVotes;

        // Public vote tallies (transparent)
        uint256 publicYesVotes;
        uint256 publicNoVotes;
        uint256 publicAbstainVotes;

        // Decrypted confidential results
        uint256 decryptedYesVotes;
        uint256 decryptedNoVotes;
        uint256 decryptedAbstainVotes;

        bool decryptionComplete;
        bool passed;
    }

    // ============================================================
    // STATE VARIABLES
    // ============================================================

    /// @notice Storage slot for main storage (EIP-7201)
    bytes32 internal constant STORAGE_LOCATION =
        0xb4c8b1c40e0c0c5e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0200;

    struct StrategyStorage {
        uint32 votingPeriod;
        uint256 quorumThreshold;
        uint256 basisNumerator;
        address strategyAdmin;
        address lightAccountFactory;
        address[] proposerAdapters;
        BlendedVotingConfig[] votingConfigs;
        mapping(uint32 proposalId => BlendedProposalVoting) proposalVoting;
        mapping(uint32 proposalId => mapping(address voter => bool hasVoted)) hasVoted;
        mapping(address => bool) isProposerAdapter;
        mapping(address => bool) isAuthorizedFreezeVoter;
        address[] authorizedFreezeVoters;
        mapping(uint256 requestId => uint32 proposalId) decryptionRequests;
        euint256 ZERO; // Cached encrypted zero
    }

    function _getStorage() internal pure returns (StrategyStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Basis denominator (1,000,000 = 100%)
    uint256 public constant BASIS_DENOMINATOR = 1_000_000;

    // ============================================================
    // EVENTS
    // ============================================================

    /// @notice Emitted when a vote is cast
    event BlendedVote(
        address indexed voter,
        uint32 indexed proposalId,
        VoteType voteType,
        uint256 publicWeight,
        bool hasConfidentialWeight
    );

    /// @notice Emitted when confidential votes are decrypted
    event ConfidentialVotesDecrypted(
        uint32 indexed proposalId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    );

    // ============================================================
    // CONSTRUCTOR
    // ============================================================

    constructor() {
        _disableInitializers();
    }

    // ============================================================
    // INITIALIZERS
    // ============================================================

    /// @inheritdoc IStrategy
    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) external override initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        if (basisNumerator_ > BASIS_DENOMINATOR) revert InvalidBasisNumerator();
        if (proposerAdapters_.length == 0) revert NoProposerAdapters();

        StrategyStorage storage $ = _getStorage();
        $.votingPeriod = votingPeriod_;
        $.quorumThreshold = quorumThreshold_;
        $.basisNumerator = basisNumerator_;
        $.lightAccountFactory = lightAccountFactory_;

        for (uint256 i; i < proposerAdapters_.length; ++i) {
            $.proposerAdapters.push(proposerAdapters_[i]);
            $.isProposerAdapter[proposerAdapters_[i]] = true;
        }

        // Cache encrypted zero
        $.ZERO = FHE.asEuint256(0);
        FHE.allowThis($.ZERO);
    }

    /// @inheritdoc IStrategy
    function initialize2(
        address strategyAdmin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) external override reinitializer(2) {
        if (strategyAdmin_ == address(0)) revert InvalidStrategyAdmin();
        if (votingConfigs_.length == 0) revert NoVotingConfigs();

        StrategyStorage storage $ = _getStorage();
        $.strategyAdmin = strategyAdmin_;

        // Note: Use addBlendedVotingConfig for extended configs
        for (uint256 i; i < votingConfigs_.length; ++i) {
            // Convert to blended config (default public)
            $.votingConfigs.push(BlendedVotingConfig({
                votingWeight: votingConfigs_[i].votingWeight,
                multiplier: 1e18,
                isConfidential: false,
                description: ""
            }));
        }
    }

    /**
     * @notice Add a blended voting configuration
     * @param config The blended voting config to add
     */
    function addBlendedVotingConfig(BlendedVotingConfig calldata config) external onlyOwner {
        _getStorage().votingConfigs.push(config);
    }

    /**
     * @notice Update a blended voting configuration
     * @param index Config index to update
     * @param config New configuration
     */
    function updateBlendedVotingConfig(uint256 index, BlendedVotingConfig calldata config) external onlyOwner {
        StrategyStorage storage $ = _getStorage();
        if (index >= $.votingConfigs.length) revert InvalidVotingConfig(index);
        $.votingConfigs[index] = config;
    }

    // ============================================================
    // UUPS
    // ============================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    /// @inheritdoc IStrategy
    function isProposer(
        address address_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) external view override returns (bool) {
        StrategyStorage storage $ = _getStorage();
        if (!$.isProposerAdapter[proposerAdapter_]) return false;
        (bool success, bytes memory result) = proposerAdapter_.staticcall(
            abi.encodeWithSignature("isProposer(address,bytes)", address_, proposerAdapterData_)
        );
        return success && abi.decode(result, (bool));
    }

    /// @inheritdoc IStrategy
    function isPassed(uint32 proposalId_) external view override returns (bool) {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];
        if (!pv.decryptionComplete) return false;
        return pv.passed;
    }

    /// @inheritdoc IStrategy
    function getVotingTimestamps(
        uint32 proposalId_
    ) external view override returns (uint48 startTime, uint48 endTime) {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];
        return (pv.votingStartTimestamp, pv.votingEndTimestamp);
    }

    /// @inheritdoc IStrategy
    function getVotingStartBlock(uint32 proposalId_) external view override returns (uint32) {
        return _getStorage().proposalVoting[proposalId_].votingStartBlock;
    }

    /// @inheritdoc IStrategy
    function votingConfigs() external view override returns (IVotingTypes.VotingConfig[] memory) {
        StrategyStorage storage $ = _getStorage();
        IVotingTypes.VotingConfig[] memory configs = new IVotingTypes.VotingConfig[]($.votingConfigs.length);
        for (uint256 i; i < $.votingConfigs.length; ++i) {
            configs[i] = IVotingTypes.VotingConfig({
                votingWeight: $.votingConfigs[i].votingWeight,
                voteTracker: address(0) // Blended strategy handles tracking internally
            });
        }
        return configs;
    }

    /**
     * @notice Get blended voting configurations
     * @return configs Array of blended configs
     */
    function blendedVotingConfigs() external view returns (BlendedVotingConfig[] memory) {
        return _getStorage().votingConfigs;
    }

    /**
     * @notice Get public vote tallies for a proposal
     * @param proposalId_ Proposal ID
     * @return yesVotes Public yes votes
     * @return noVotes Public no votes
     * @return abstainVotes Public abstain votes
     */
    function getPublicVotes(uint32 proposalId_) external view returns (
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) {
        BlendedProposalVoting storage pv = _getStorage().proposalVoting[proposalId_];
        return (pv.publicYesVotes, pv.publicNoVotes, pv.publicAbstainVotes);
    }

    /**
     * @notice Get total vote tallies (public + decrypted confidential)
     * @param proposalId_ Proposal ID
     * @return yesVotes Total yes votes
     * @return noVotes Total no votes
     * @return abstainVotes Total abstain votes
     */
    function getTotalVotes(uint32 proposalId_) external view returns (
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) {
        BlendedProposalVoting storage pv = _getStorage().proposalVoting[proposalId_];
        if (!pv.decryptionComplete) {
            // Only return public votes before decryption
            return (pv.publicYesVotes, pv.publicNoVotes, pv.publicAbstainVotes);
        }
        return (
            pv.publicYesVotes + pv.decryptedYesVotes,
            pv.publicNoVotes + pv.decryptedNoVotes,
            pv.publicAbstainVotes + pv.decryptedAbstainVotes
        );
    }

    /// @inheritdoc IStrategy
    function isProposerAdapter(address proposerAdapter_) external view override returns (bool) {
        return _getStorage().isProposerAdapter[proposerAdapter_];
    }

    /// @inheritdoc IStrategy
    function strategyAdmin() external view override returns (address) {
        return _getStorage().strategyAdmin;
    }

    /// @inheritdoc IStrategy
    function votingPeriod() external view override returns (uint32) {
        return _getStorage().votingPeriod;
    }

    /// @inheritdoc IStrategy
    function quorumThreshold() external view override returns (uint256) {
        return _getStorage().quorumThreshold;
    }

    /// @inheritdoc IStrategy
    function basisNumerator() external view override returns (uint256) {
        return _getStorage().basisNumerator;
    }

    /// @inheritdoc IStrategy
    function proposalVotingDetails(
        uint32 proposalId_
    ) external view override returns (ProposalVotingDetails memory) {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];

        uint256 yesTotal = pv.publicYesVotes + (pv.decryptionComplete ? pv.decryptedYesVotes : 0);
        uint256 noTotal = pv.publicNoVotes + (pv.decryptionComplete ? pv.decryptedNoVotes : 0);
        uint256 abstainTotal = pv.publicAbstainVotes + (pv.decryptionComplete ? pv.decryptedAbstainVotes : 0);

        return ProposalVotingDetails({
            votingStartTimestamp: pv.votingStartTimestamp,
            votingEndTimestamp: pv.votingEndTimestamp,
            votingStartBlock: pv.votingStartBlock,
            yesVotes: yesTotal,
            noVotes: noTotal,
            abstainVotes: abstainTotal
        });
    }

    /// @inheritdoc IStrategy
    function votingConfig(uint256 configIndex_) external view override returns (IVotingTypes.VotingConfig memory) {
        BlendedVotingConfig storage config = _getStorage().votingConfigs[configIndex_];
        return IVotingTypes.VotingConfig({
            votingWeight: config.votingWeight,
            voteTracker: address(0) // Blended strategy handles tracking internally
        });
    }

    /// @inheritdoc IStrategy
    function proposerAdapters() external view override returns (address[] memory) {
        return _getStorage().proposerAdapters;
    }

    /// @inheritdoc IStrategy
    function isQuorumMet(uint32 proposalId_) external view override returns (bool) {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];
        if (!pv.decryptionComplete) return false;

        uint256 totalYes = pv.publicYesVotes + pv.decryptedYesVotes;
        uint256 totalAbstain = pv.publicAbstainVotes + pv.decryptedAbstainVotes;
        return (totalYes + totalAbstain) >= $.quorumThreshold;
    }

    /// @inheritdoc IStrategy
    function isBasisMet(uint32 proposalId_) external view override returns (bool) {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];
        if (!pv.decryptionComplete) return false;

        uint256 totalYes = pv.publicYesVotes + pv.decryptedYesVotes;
        uint256 totalNo = pv.publicNoVotes + pv.decryptedNoVotes;
        uint256 totalVotes = totalYes + totalNo;
        if (totalVotes == 0) return false;

        return (totalYes * BASIS_DENOMINATOR) > (totalVotes * $.basisNumerator);
    }

    /// @inheritdoc IStrategy
    function isAuthorizedFreezeVoter(address freezeVoterContract_) external view override returns (bool) {
        return _getStorage().isAuthorizedFreezeVoter[freezeVoterContract_];
    }

    /// @inheritdoc IStrategy
    function authorizedFreezeVoters() external view override returns (address[] memory) {
        return _getStorage().authorizedFreezeVoters;
    }

    /// @inheritdoc IStrategy
    function voteCastedAfterVotingPeriodEnded(uint32) external pure override returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function validStrategyVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata
    ) external view override returns (bool) {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];

        if (block.timestamp < pv.votingStartTimestamp) return false;
        if (block.timestamp > pv.votingEndTimestamp) return false;
        if ($.hasVoted[proposalId_][voter_]) return false;
        if (voteType_ > uint8(VoteType.ABSTAIN)) return false;

        return true;
    }

    // ============================================================
    // STATE-CHANGING FUNCTIONS
    // ============================================================

    /// @inheritdoc IStrategy
    function initializeProposal(uint32 proposalId_) external override {
        StrategyStorage storage $ = _getStorage();
        if (msg.sender != $.strategyAdmin) revert InvalidStrategyAdmin();

        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];

        pv.votingStartTimestamp = uint48(block.timestamp);
        pv.votingEndTimestamp = uint48(block.timestamp + $.votingPeriod);
        pv.votingStartBlock = uint32(block.number);

        // Initialize encrypted vote counters
        pv.confidentialYesVotes = $.ZERO;
        pv.confidentialNoVotes = $.ZERO;
        pv.confidentialAbstainVotes = $.ZERO;

        FHE.allowThis(pv.confidentialYesVotes);
        FHE.allowThis(pv.confidentialNoVotes);
        FHE.allowThis(pv.confidentialAbstainVotes);

        // Public counters start at 0 by default

        emit ProposalInitialized(
            proposalId_,
            pv.votingStartTimestamp,
            pv.votingEndTimestamp,
            pv.votingStartBlock
        );
    }

    /// @inheritdoc IStrategy
    function castVote(
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_,
        uint256
    ) external override {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];

        // Validate vote
        if (block.timestamp < pv.votingStartTimestamp || pv.votingStartTimestamp == 0) {
            revert ProposalNotActive();
        }
        if (block.timestamp > pv.votingEndTimestamp) revert ProposalNotActive();
        if ($.hasVoted[proposalId_][msg.sender]) revert InvalidVoteType();
        if (voteType_ > uint8(VoteType.ABSTAIN)) revert InvalidVoteType();

        // Calculate voting weight from all configs, separated by privacy
        uint256 publicWeight;
        uint256 confidentialWeight;

        for (uint256 i; i < votingConfigsData_.length; ++i) {
            uint256 configIndex = votingConfigsData_[i].configIndex;
            if (configIndex >= $.votingConfigs.length) revert InvalidVotingConfig(configIndex);

            BlendedVotingConfig memory config = $.votingConfigs[configIndex];
            (uint256 weight, ) = IVotingWeight(config.votingWeight).calculateWeight(
                msg.sender,
                pv.votingStartBlock,
                votingConfigsData_[i].voteData
            );

            // Apply multiplier
            weight = (weight * config.multiplier) / 1e18;

            if (config.isConfidential) {
                confidentialWeight += weight;
            } else {
                publicWeight += weight;
            }
        }

        if (publicWeight == 0 && confidentialWeight == 0) revert NoVotingWeight(0);

        // Mark voted
        $.hasVoted[proposalId_][msg.sender] = true;

        // Add public votes
        if (publicWeight > 0) {
            if (VoteType(voteType_) == VoteType.YES) {
                pv.publicYesVotes += publicWeight;
            } else if (VoteType(voteType_) == VoteType.NO) {
                pv.publicNoVotes += publicWeight;
            } else {
                pv.publicAbstainVotes += publicWeight;
            }
        }

        // Add confidential votes (encrypted)
        if (confidentialWeight > 0) {
            euint256 encryptedWeight = FHE.asEuint256(confidentialWeight);

            if (VoteType(voteType_) == VoteType.YES) {
                pv.confidentialYesVotes = FHE.add(pv.confidentialYesVotes, encryptedWeight);
                FHE.allowThis(pv.confidentialYesVotes);
            } else if (VoteType(voteType_) == VoteType.NO) {
                pv.confidentialNoVotes = FHE.add(pv.confidentialNoVotes, encryptedWeight);
                FHE.allowThis(pv.confidentialNoVotes);
            } else {
                pv.confidentialAbstainVotes = FHE.add(pv.confidentialAbstainVotes, encryptedWeight);
                FHE.allowThis(pv.confidentialAbstainVotes);
            }
        }

        emit BlendedVote(
            msg.sender,
            proposalId_,
            VoteType(voteType_),
            publicWeight,
            confidentialWeight > 0
        );
    }

    /**
     * @notice Request decryption of confidential vote totals
     * @param proposalId_ The proposal ID
     */
    function requestVoteDecryption(uint32 proposalId_) external {
        StrategyStorage storage $ = _getStorage();
        BlendedProposalVoting storage pv = $.proposalVoting[proposalId_];

        if (block.timestamp <= pv.votingEndTimestamp) revert ProposalNotActive();
        if (pv.decryptionComplete) revert ProposalNotInitialized();

        // Request decryption of confidential votes
        uint256[] memory cts = new uint256[](3);
        cts[0] = TFHE.toUint256(pv.confidentialYesVotes);
        cts[1] = TFHE.toUint256(pv.confidentialNoVotes);
        cts[2] = TFHE.toUint256(pv.confidentialAbstainVotes);

        uint256 requestId = TFHE.decrypt(
            cts,
            this.callbackVoteDecryption.selector,
            0,
            block.timestamp + 1 days,
            false
        );

        $.decryptionRequests[requestId] = proposalId_;
        emit VotingPeriodEnded(proposalId_);
    }

    /**
     * @notice Callback from T-Chain with decrypted vote totals
     * @param requestId The decryption request ID
     * @param yesVotes Decrypted YES votes
     * @param noVotes Decrypted NO votes
     * @param abstainVotes Decrypted ABSTAIN votes
     */
    function callbackVoteDecryption(
        uint256 requestId,
        uint256 yesVotes,
        uint256 noVotes,
        uint256 abstainVotes
    ) external onlyGateway {
        StrategyStorage storage $ = _getStorage();
        uint32 proposalId = $.decryptionRequests[requestId];

        BlendedProposalVoting storage pv = $.proposalVoting[proposalId];
        pv.decryptedYesVotes = yesVotes;
        pv.decryptedNoVotes = noVotes;
        pv.decryptedAbstainVotes = abstainVotes;
        pv.decryptionComplete = true;

        // Calculate total votes (public + confidential)
        uint256 totalYes = pv.publicYesVotes + yesVotes;
        uint256 totalNo = pv.publicNoVotes + noVotes;
        uint256 totalAbstain = pv.publicAbstainVotes + abstainVotes;

        // Check quorum and basis
        bool quorumMet = (totalYes + totalAbstain) >= $.quorumThreshold;
        uint256 totalVotes = totalYes + totalNo;
        bool basisMet = totalVotes > 0 &&
            (totalYes * BASIS_DENOMINATOR) > (totalVotes * $.basisNumerator);

        pv.passed = quorumMet && basisMet;

        emit ConfidentialVotesDecrypted(proposalId, yesVotes, noVotes, abstainVotes);
        delete $.decryptionRequests[requestId];
    }

    /// @inheritdoc IStrategy
    function addAuthorizedFreezeVoter(address freezeVoterContract_) external override onlyOwner {
        StrategyStorage storage $ = _getStorage();
        if (freezeVoterContract_ == address(0)) revert InvalidAddress();
        $.isAuthorizedFreezeVoter[freezeVoterContract_] = true;
        $.authorizedFreezeVoters.push(freezeVoterContract_);
        emit FreezeVoterAuthorizationChanged(freezeVoterContract_, true);
    }

    /// @inheritdoc IStrategy
    function removeAuthorizedFreezeVoter(address freezeVoterContract_) external override onlyOwner {
        StrategyStorage storage $ = _getStorage();
        $.isAuthorizedFreezeVoter[freezeVoterContract_] = false;

        address[] storage voters = $.authorizedFreezeVoters;
        for (uint256 i; i < voters.length; ++i) {
            if (voters[i] == freezeVoterContract_) {
                voters[i] = voters[voters.length - 1];
                voters.pop();
                break;
            }
        }
        emit FreezeVoterAuthorizationChanged(freezeVoterContract_, false);
    }
}
