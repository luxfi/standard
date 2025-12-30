// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IVotingTypes} from "./IVotingTypes.sol";

/**
 * @title IStrategy
 * @author Lux Industries Inc
 * @notice Core voting strategy contract for the Lux governance system
 * @dev Manages voting logic for proposals. Handles vote counting, quorum,
 * and determines whether proposals pass or fail.
 *
 * Key features:
 * - Fixed voting period duration
 * - Quorum threshold (minimum participation)
 * - Basis threshold (minimum approval percentage)
 * - Multiple voting configurations for different token types
 * - Multiple proposer adapters for access control
 * - Light Account support for gasless voting (ERC-4337)
 * - Freeze voter authorization for emergency governance
 *
 * Voting mechanics:
 * - Supports YES, NO, and ABSTAIN votes
 * - Quorum: YES + ABSTAIN >= threshold
 * - Basis: YES / (YES + NO) > required percentage
 */
interface IStrategy {
    // --- Errors ---

    error InvalidProposerAdapter();
    error NoVotingConfigs();
    error NoProposerAdapters();
    error InvalidBasisNumerator();
    error InvalidStrategyAdmin();
    error ProposalNotActive();
    error NoVotingWeight(uint256 configIndex);
    error InvalidVoteType();
    error ProposalNotInitialized();
    error InvalidVotingConfig(uint256 configIndex);
    error InvalidAddress();

    // --- Structs ---

    /**
     * @notice Voting state for a proposal
     * @param votingStartTimestamp When voting begins
     * @param votingEndTimestamp When voting ends
     * @param votingStartBlock Block number for snapshots
     * @param yesVotes Total YES vote weight
     * @param noVotes Total NO vote weight
     * @param abstainVotes Total ABSTAIN vote weight
     */
    struct ProposalVotingDetails {
        uint48 votingStartTimestamp;
        uint48 votingEndTimestamp;
        uint32 votingStartBlock;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 abstainVotes;
    }

    // --- Enums ---

    /**
     * @notice Vote types
     * @dev NO counts toward basis, YES counts toward quorum+basis, ABSTAIN only quorum
     */
    enum VoteType {
        NO,
        YES,
        ABSTAIN
    }

    // --- Events ---

    event Voted(
        address indexed voter,
        uint32 indexed proposalId,
        VoteType voteType,
        uint256 totalWeightCastedInTx
    );

    event ProposalInitialized(
        uint32 indexed proposalId,
        uint48 votingStartTimestamp,
        uint48 votingEndTimestamp,
        uint32 votingStartBlock
    );

    event FreezeVoterAuthorizationChanged(
        address indexed freezeVoterContract,
        bool isAuthorized
    );

    event VotingPeriodEnded(uint32 indexed proposalId);

    // --- Initializer Functions ---

    /**
     * @notice Initialize strategy with core voting parameters (step 1)
     * @param votingPeriod_ Duration in seconds for voting
     * @param quorumThreshold_ Minimum YES+ABSTAIN weight for quorum
     * @param basisNumerator_ Approval percentage numerator (denominator is 1M)
     * @param proposerAdapters_ Proposer adapter addresses
     * @param lightAccountFactory_ Factory for Light Account (gasless voting)
     */
    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) external;

    /**
     * @notice Complete initialization with admin and configs (step 2)
     * @param strategyAdmin_ Admin address (typically the Governor)
     * @param votingConfigs_ Voting configurations
     */
    function initialize2(
        address strategyAdmin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) external;

    // --- View Functions ---

    function isProposer(
        address address_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) external view returns (bool);

    function isPassed(uint32 proposalId_) external view returns (bool);

    function getVotingTimestamps(
        uint32 proposalId_
    ) external view returns (uint48 startTime, uint48 endTime);

    function getVotingStartBlock(
        uint32 proposalId_
    ) external view returns (uint32);

    function votingConfigs() external view returns (IVotingTypes.VotingConfig[] memory);

    function isProposerAdapter(address proposerAdapter_) external view returns (bool);

    function strategyAdmin() external view returns (address);

    function votingPeriod() external view returns (uint32);

    function quorumThreshold() external view returns (uint256);

    function basisNumerator() external view returns (uint256);

    function proposalVotingDetails(
        uint32 proposalId_
    ) external view returns (ProposalVotingDetails memory);

    function votingConfig(
        uint256 configIndex_
    ) external view returns (IVotingTypes.VotingConfig memory);

    function proposerAdapters() external view returns (address[] memory);

    function isQuorumMet(uint32 proposalId_) external view returns (bool);

    function isBasisMet(uint32 proposalId_) external view returns (bool);

    function isAuthorizedFreezeVoter(
        address freezeVoterContract_
    ) external view returns (bool);

    function authorizedFreezeVoters() external view returns (address[] memory);

    function voteCastedAfterVotingPeriodEnded(
        uint32 proposalId_
    ) external view returns (bool);

    function validStrategyVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_
    ) external view returns (bool);

    // --- State-Changing Functions ---

    function initializeProposal(uint32 proposalId_) external;

    function castVote(
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_,
        uint256 lightAccountIndex_
    ) external;

    function addAuthorizedFreezeVoter(address freezeVoterContract_) external;

    function removeAuthorizedFreezeVoter(address freezeVoterContract_) external;
}
