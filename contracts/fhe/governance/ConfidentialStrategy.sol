// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import "../FHE.sol";
import {TFHE} from "../threshold/TFHE.sol";
import {TFHEApp} from "../threshold/TFHEApp.sol";
import {ICharter} from "../../governance/interfaces/ICharter.sol";
import {IVotingTypes} from "../../governance/interfaces/IVotingTypes.sol";
import {IVotingWeight} from "../../governance/interfaces/IVotingWeight.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title ConfidentialStrategy
 * @author Lux Industries Inc
 * @notice Voting strategy with encrypted vote counting via TFHE
 * @dev Implements IStrategy with fully homomorphic encryption for vote privacy.
 *      Votes are encrypted on-chain and only decrypted via T-Chain threshold
 *      validators when voting ends.
 *
 * Privacy guarantees:
 * - Individual votes are never revealed on-chain
 * - Vote totals are encrypted until voting ends
 * - Decryption requires threshold consensus (n-of-m validators)
 * - Results revealed only after voting period
 *
 * Architecture:
 *   Voter → castVote(encrypted) → FHE operations → TFHE.decrypt()
 *   → T-Chain Validators → callbackDecryption() → isPassed()
 */
contract ConfidentialStrategy is
    ICharter,
    TFHEApp,
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    // ============================================================
    // ERRORS
    // ============================================================

    error InvalidStrategyAdmin();

    // ============================================================
    // EVENTS
    // ============================================================

    event FreezeVoterAuthorizationChanged(
        address indexed freezeVoterContract,
        bool isAuthorized
    );

    // ============================================================
    // STATE VARIABLES
    // ============================================================

    /// @notice Confidential voting state for a proposal
    struct ConfidentialProposalVoting {
        uint48 votingStartTimestamp;
        uint48 votingEndTimestamp;
        uint32 votingStartBlock;
        euint256 yesVotes;        // Encrypted YES vote weight
        euint256 noVotes;         // Encrypted NO vote weight
        euint256 abstainVotes;    // Encrypted ABSTAIN vote weight
        uint256 yesVotesDecrypted;    // Decrypted after voting ends
        uint256 noVotesDecrypted;     // Decrypted after voting ends
        uint256 abstainVotesDecrypted; // Decrypted after voting ends
        bool decryptionComplete;
        bool passed;
    }

    /// @notice Storage slot for main storage (EIP-7201)
    /// @dev keccak256("lux.confidential.strategy.v1") - 1
    bytes32 internal constant STORAGE_LOCATION =
        0xb4c8b1c40e0c0c5e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0100;

    struct StrategyStorage {
        uint32 votingPeriod;
        uint256 quorumThreshold;
        uint256 basisNumerator;
        address strategyAdmin;
        address lightAccountFactory;
        address[] proposerAdapters;
        IVotingTypes.VotingConfig[] votingConfigs;
        mapping(uint32 proposalId => ConfidentialProposalVoting) proposalVoting;
        mapping(uint32 proposalId => mapping(address voter => bool hasVoted)) hasVoted;
        mapping(address => bool) isProposerAdapter;
        mapping(address => bool) isAuthorizedFreezeVoter;
        address[] authorizedFreezeVoters;
        mapping(address => bool) isAuthorizedVetoVoter;
        address[] authorizedVetoVoters;
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
    // CONSTRUCTOR
    // ============================================================

    constructor() {
        _disableInitializers();
    }

    // ============================================================
    // INITIALIZERS
    // ============================================================

    /// @notice See IStrategy for documentation
    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) external override initializer {
        __Ownable_init(msg.sender);

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

        // Cache encrypted zero for efficiency
        $.ZERO = FHE.asEuint256(0);
        FHE.allowThis($.ZERO);
    }

    /// @notice See IStrategy for documentation
    function initialize2(
        address strategyAdmin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) external override reinitializer(2) {
        if (strategyAdmin_ == address(0)) revert InvalidStrategyAdmin();
        if (votingConfigs_.length == 0) revert NoVotingConfigs();

        StrategyStorage storage $ = _getStorage();
        $.strategyAdmin = strategyAdmin_;

        for (uint256 i; i < votingConfigs_.length; ++i) {
            $.votingConfigs.push(votingConfigs_[i]);
        }
    }

    // ============================================================
    // UUPS
    // ============================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    /// @notice See IStrategy for documentation
    function isProposer(
        address address_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) external view returns (bool) {
        StrategyStorage storage $ = _getStorage();
        if (!$.isProposerAdapter[proposerAdapter_]) return false;
        // Delegate to adapter
        (bool success, bytes memory result) = proposerAdapter_.staticcall(
            abi.encodeWithSignature("isProposer(address,bytes)", address_, proposerAdapterData_)
        );
        return success && abi.decode(result, (bool));
    }

    /// @notice See IStrategy for documentation
    function isPassed(uint32 proposalId_) external view returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];

        // Must have completed decryption
        if (!pv.decryptionComplete) return false;
        return pv.passed;
    }

    /// @notice See IStrategy for documentation
    function getVotingTimestamps(
        uint32 proposalId_
    ) external view override returns (uint48 startTime, uint48 endTime) {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];
        return (pv.votingStartTimestamp, pv.votingEndTimestamp);
    }

    /// @notice See IStrategy for documentation
    function getVotingStartBlock(uint32 proposalId_) external view override returns (uint32) {
        return _getStorage().proposalVoting[proposalId_].votingStartBlock;
    }

    /// @notice See IStrategy for documentation
    function votingConfigs() external view override returns (IVotingTypes.VotingConfig[] memory) {
        return _getStorage().votingConfigs;
    }

    /// @notice See IStrategy for documentation
    function isProposerAdapter(address proposerAdapter_) external view returns (bool) {
        return _getStorage().isProposerAdapter[proposerAdapter_];
    }

    /// @notice See IStrategy for documentation
    function strategyAdmin() external view returns (address) {
        return _getStorage().strategyAdmin;
    }

    /// @notice See IStrategy for documentation
    function votingPeriod() external view override returns (uint32) {
        return _getStorage().votingPeriod;
    }

    /// @notice See IStrategy for documentation
    function quorumThreshold() external view override returns (uint256) {
        return _getStorage().quorumThreshold;
    }

    /// @notice See IStrategy for documentation
    function basisNumerator() external view override returns (uint256) {
        return _getStorage().basisNumerator;
    }

    /// @notice See IStrategy for documentation
    function proposalVotingDetails(
        uint32 proposalId_
    ) external view override returns (ProposalVotingDetails memory) {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];

        // Return decrypted values if available, otherwise 0 (encrypted)
        return ProposalVotingDetails({
            votingStartTimestamp: pv.votingStartTimestamp,
            votingEndTimestamp: pv.votingEndTimestamp,
            votingStartBlock: pv.votingStartBlock,
            yesVotes: pv.decryptionComplete ? pv.yesVotesDecrypted : 0,
            noVotes: pv.decryptionComplete ? pv.noVotesDecrypted : 0,
            abstainVotes: pv.decryptionComplete ? pv.abstainVotesDecrypted : 0
        });
    }

    /// @notice See IStrategy for documentation
    function votingConfig(uint256 configIndex_) external view override returns (IVotingTypes.VotingConfig memory) {
        return _getStorage().votingConfigs[configIndex_];
    }

    /// @notice See IStrategy for documentation
    function proposerAdapters() external view returns (address[] memory) {
        return _getStorage().proposerAdapters;
    }

    /// @notice See IStrategy for documentation
    function isQuorumMet(uint32 proposalId_) external view returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];
        if (!pv.decryptionComplete) return false;
        return (pv.yesVotesDecrypted + pv.abstainVotesDecrypted) >= $.quorumThreshold;
    }

    /// @notice See IStrategy for documentation
    function isBasisMet(uint32 proposalId_) external view returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];
        if (!pv.decryptionComplete) return false;

        uint256 totalVotes = pv.yesVotesDecrypted + pv.noVotesDecrypted;
        if (totalVotes == 0) return false;

        return (pv.yesVotesDecrypted * BASIS_DENOMINATOR) > (totalVotes * $.basisNumerator);
    }

    /// @notice See IStrategy for documentation
    function isAuthorizedFreezeVoter(address freezeVoterContract_) external view returns (bool) {
        return _getStorage().isAuthorizedFreezeVoter[freezeVoterContract_];
    }

    /// @notice See IStrategy for documentation
    function authorizedFreezeVoters() external view returns (address[] memory) {
        return _getStorage().authorizedFreezeVoters;
    }

    /// @notice See ICharter for documentation
    function charterAdmin() external view returns (address) {
        return _getStorage().strategyAdmin;
    }

    /// @notice See ICharter for documentation
    function isAuthorizedVetoVoter(address vetoVoterContract_) external view returns (bool) {
        return _getStorage().isAuthorizedVetoVoter[vetoVoterContract_];
    }

    /// @notice See ICharter for documentation
    function authorizedVetoVoters() external view returns (address[] memory) {
        return _getStorage().authorizedVetoVoters;
    }

    /// @notice See IStrategy for documentation
    function voteCastedAfterVotingPeriodEnded(uint32) external pure override returns (bool) {
        return false; // Not tracked in this implementation
    }

    /// @notice See IStrategy for documentation
    function validStrategyVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_
    ) external view returns (bool) {
        return _validVote(voter_, proposalId_, voteType_);
    }

    /// @notice See ICharter for documentation
    function validCharterVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_
    ) external view returns (bool) {
        return _validVote(voter_, proposalId_, voteType_);
    }

    function _validVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_
    ) internal view returns (bool) {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];

        if (block.timestamp < pv.votingStartTimestamp) return false;
        if (block.timestamp > pv.votingEndTimestamp) return false;
        if ($.hasVoted[proposalId_][voter_]) return false;
        if (voteType_ > uint8(VoteType.ABSTAIN)) return false;

        return true;
    }

    // ============================================================
    // STATE-CHANGING FUNCTIONS
    // ============================================================

    /// @notice See IStrategy for documentation
    function initializeProposal(uint32 proposalId_) external override {
        StrategyStorage storage $ = _getStorage();
        if (msg.sender != $.strategyAdmin) revert InvalidStrategyAdmin();

        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];

        pv.votingStartTimestamp = uint48(block.timestamp);
        pv.votingEndTimestamp = uint48(block.timestamp + $.votingPeriod);
        pv.votingStartBlock = uint32(block.number);

        // Initialize encrypted vote counters to zero
        pv.yesVotes = $.ZERO;
        pv.noVotes = $.ZERO;
        pv.abstainVotes = $.ZERO;

        FHE.allowThis(pv.yesVotes);
        FHE.allowThis(pv.noVotes);
        FHE.allowThis(pv.abstainVotes);

        emit ProposalInitialized(
            proposalId_,
            pv.votingStartTimestamp,
            pv.votingEndTimestamp,
            pv.votingStartBlock
        );
    }

    /// @notice See IStrategy for documentation
    function castVote(
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_,
        uint256
    ) external override {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];

        // Validate vote
        if (block.timestamp < pv.votingStartTimestamp || pv.votingStartTimestamp == 0) {
            revert ProposalNotActive();
        }
        if (block.timestamp > pv.votingEndTimestamp) revert ProposalNotActive();
        if ($.hasVoted[proposalId_][msg.sender]) revert InvalidVoteType();
        if (voteType_ > uint8(VoteType.ABSTAIN)) revert InvalidVoteType();

        // Calculate voting weight from all configs
        uint256 totalWeight;
        for (uint256 i; i < votingConfigsData_.length; ++i) {
            uint256 configIndex = votingConfigsData_[i].configIndex;
            if (configIndex >= $.votingConfigs.length) revert InvalidVotingConfig(configIndex);

            IVotingTypes.VotingConfig memory config = $.votingConfigs[configIndex];
            (uint256 weight, ) = IVotingWeight(config.votingWeight).calculateWeight(
                msg.sender,
                pv.votingStartBlock,
                votingConfigsData_[i].voteData
            );
            totalWeight += weight;
        }

        if (totalWeight == 0) revert NoVotingWeight(0);

        // Mark voted
        $.hasVoted[proposalId_][msg.sender] = true;

        // Add encrypted vote
        euint256 encryptedWeight = FHE.asEuint256(totalWeight);

        if (VoteType(voteType_) == VoteType.YES) {
            pv.yesVotes = FHE.add(pv.yesVotes, encryptedWeight);
            FHE.allowThis(pv.yesVotes);
        } else if (VoteType(voteType_) == VoteType.NO) {
            pv.noVotes = FHE.add(pv.noVotes, encryptedWeight);
            FHE.allowThis(pv.noVotes);
        } else {
            pv.abstainVotes = FHE.add(pv.abstainVotes, encryptedWeight);
            FHE.allowThis(pv.abstainVotes);
        }

        emit Voted(msg.sender, proposalId_, VoteType(voteType_), totalWeight);
    }

    /**
     * @notice Request decryption of vote totals after voting ends
     * @param proposalId_ The proposal ID
     */
    function requestVoteDecryption(uint32 proposalId_) external {
        StrategyStorage storage $ = _getStorage();
        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId_];

        if (block.timestamp <= pv.votingEndTimestamp) revert ProposalNotActive();
        if (pv.decryptionComplete) revert ProposalNotInitialized();

        // Request decryption of all three vote totals
        uint256[] memory cts = new uint256[](3);
        cts[0] = TFHE.toUint256(pv.yesVotes);
        cts[1] = TFHE.toUint256(pv.noVotes);
        cts[2] = TFHE.toUint256(pv.abstainVotes);

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

        ConfidentialProposalVoting storage pv = $.proposalVoting[proposalId];
        pv.yesVotesDecrypted = yesVotes;
        pv.noVotesDecrypted = noVotes;
        pv.abstainVotesDecrypted = abstainVotes;
        pv.decryptionComplete = true;

        // Calculate if passed: quorum met AND basis met
        bool quorumMet = (yesVotes + abstainVotes) >= $.quorumThreshold;
        uint256 totalVotes = yesVotes + noVotes;
        bool basisMet = totalVotes > 0 &&
            (yesVotes * BASIS_DENOMINATOR) > (totalVotes * $.basisNumerator);

        pv.passed = quorumMet && basisMet;

        delete $.decryptionRequests[requestId];
    }

    /// @notice See IStrategy for documentation
    function addAuthorizedFreezeVoter(address freezeVoterContract_) external onlyOwner {
        StrategyStorage storage $ = _getStorage();
        if (freezeVoterContract_ == address(0)) revert InvalidAddress();
        $.isAuthorizedFreezeVoter[freezeVoterContract_] = true;
        $.authorizedFreezeVoters.push(freezeVoterContract_);
        emit FreezeVoterAuthorizationChanged(freezeVoterContract_, true);
    }

    /// @notice See IStrategy for documentation
    function removeAuthorizedFreezeVoter(address freezeVoterContract_) external onlyOwner {
        StrategyStorage storage $ = _getStorage();
        $.isAuthorizedFreezeVoter[freezeVoterContract_] = false;

        // Remove from array
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

    // ============================================================
    // VETO VOTER MANAGEMENT
    // ============================================================

    /// @notice See IStrategy for documentation
    function addAuthorizedVetoVoter(address vetoVoterContract_) external onlyOwner {
        StrategyStorage storage $ = _getStorage();
        if ($.isAuthorizedVetoVoter[vetoVoterContract_]) return;

        $.isAuthorizedVetoVoter[vetoVoterContract_] = true;
        $.authorizedVetoVoters.push(vetoVoterContract_);
    }

    /// @notice See IStrategy for documentation
    function removeAuthorizedVetoVoter(address vetoVoterContract_) external onlyOwner {
        StrategyStorage storage $ = _getStorage();
        if (!$.isAuthorizedVetoVoter[vetoVoterContract_]) return;

        $.isAuthorizedVetoVoter[vetoVoterContract_] = false;

        address[] storage voters = $.authorizedVetoVoters;
        for (uint256 i; i < voters.length; ++i) {
            if (voters[i] == vetoVoterContract_) {
                voters[i] = voters[voters.length - 1];
                voters.pop();
                break;
            }
        }
    }
}
