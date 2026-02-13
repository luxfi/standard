// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IVotingTypes} from "./IVotingTypes.sol";

/**
 * @title IStrategyV1
 * @notice Core voting strategy contract for the Governor governance system
 * @dev This contract manages the voting logic for proposals created through ModuleGovernorV1.
 * It handles vote counting, quorum and basis calculations, and determines whether proposals
 * pass or fail. The strategy uses modular voting configurations that combine weight
 * calculation strategies with vote tracking, enabling support for various token standards
 * (ERC20, ERC721, etc.).
 *
 * Key features:
 * - Fixed voting period duration applied to all proposals
 * - Quorum threshold (minimum participation required)
 * - Basis threshold (minimum approval percentage required)
 * - Multiple voting configurations for different token types
 * - Multiple proposer adapters for access control
 * - Light Account support for gasless voting
 * - Freeze voter authorization for emergency governance
 *
 * Voting mechanics:
 * - Supports YES, NO, and ABSTAIN votes
 * - Quorum calculation: YES + ABSTAIN votes must meet threshold
 * - Basis calculation: YES votes must exceed required percentage of YES + NO votes
 * - Voting constraints are configuration-specific (e.g., ERC20 configs typically allow one vote per address,
 *   while ERC721 configs allow one vote per NFT, enabling multiple votes from the same address)
 *
 * Integration with Governor:
 * - Governor calls initializeProposal() when a proposal is created
 * - Governor calls isPassed() to determine if a proposal can be executed
 * - Each proposal uses the strategy that was active when it was created
 */
interface IStrategyV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to use a proposer adapter that is not configured */
    error InvalidProposerAdapter();

    /** @notice Thrown when attempting to initialize with no voting configs */
    error NoVotingConfigs();

    /** @notice Thrown when attempting to initialize with no proposer adapters */
    error NoProposerAdapters();

    /** @notice Thrown when basis numerator is >= 1,000,000 (100%) or < 500,000 (50%) */
    error InvalidBasisNumerator();

    /** @notice Thrown when a function restricted to strategyAdmin is called by another address */
    error InvalidStrategyAdmin();

    /** @notice Thrown when attempting to vote on a proposal after its voting period has ended */
    error ProposalNotActive();

    /** @notice Thrown when a voting config returns zero voting weight for a voter */
    error NoVotingWeight(uint256 configIndex);

    /** @notice Thrown when an invalid vote type is provided (not 0=NO, 1=YES, 2=ABSTAIN) */
    error InvalidVoteType();

    /** @notice Thrown when accessing a proposal that hasn't been initialized */
    error ProposalNotInitialized();

    /** @notice Thrown when using a voting config index that is out of bounds */
    error InvalidVotingConfig(uint256 configIndex);

    /** @notice Thrown when attempting to add/remove address(0) as a freeze voter */
    error InvalidAddress();

    // --- Structs ---

    /**
     * @notice Stores voting state and tallies for a specific proposal
     * @param votingStartTimestamp Unix timestamp when voting begins
     * @param votingEndTimestamp Unix timestamp when voting ends (start + votingPeriod)
     * @param votingStartBlock Block number when voting begins (for snapshot purposes)
     * @param yesVotes Total weight of YES votes cast
     * @param noVotes Total weight of NO votes cast
     * @param abstainVotes Total weight of ABSTAIN votes cast
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
     * @notice Represents the type of vote being cast
     * @dev Vote types affect proposal outcomes differently:
     *
     * Values:
     * - NO: Vote against the proposal (counts toward basis calculation)
     * - YES: Vote in favor of the proposal (counts toward quorum and basis)
     * - ABSTAIN: Neither for nor against (counts toward quorum only)
     */
    enum VoteType {
        NO,
        YES,
        ABSTAIN
    }

    // --- Events ---

    /**
     * @notice Emitted when a vote is successfully cast
     * @param voter The address that cast the vote (or Light Account owner)
     * @param proposalId The proposal being voted on
     * @param voteType The type of vote cast (NO, YES, or ABSTAIN)
     * @param totalWeightCastedInTx Total voting weight used across all adapters in this transaction
     */
    event Voted(
        address indexed voter,
        uint32 indexed proposalId,
        VoteType voteType,
        uint256 totalWeightCastedInTx
    );

    /**
     * @notice Emitted when a proposal's voting period is initialized
     * @param proposalId The proposal being initialized
     * @param votingStartTimestamp When voting begins
     * @param votingEndTimestamp When voting ends
     * @param votingStartBlock Block number for voting snapshots
     */
    event ProposalInitialized(
        uint32 indexed proposalId,
        uint48 votingStartTimestamp,
        uint48 votingEndTimestamp,
        uint32 votingStartBlock
    );

    /**
     * @notice Emitted when a freeze voter contract is added or removed
     * @param freezeVoterContract The freeze voting contract address
     * @param isAuthorized Whether the contract is now authorized
     */
    event FreezeVoterAuthorizationChanged(
        address indexed freezeVoterContract,
        bool isAuthorized
    );

    /**
     * @notice Emitted when a vote is cast after the voting period has ended
     * @param proposalId The proposal that had its voting period end
     */
    event VotingPeriodEnded(uint32 indexed proposalId);

    // --- Initializer Functions ---

    /**
     * @notice Initializes the strategy with core voting parameters (part 1 of 2)
     * @dev Split initialization is required to resolve circular dependencies:
     * - Governor needs Strategy address during initialization
     * - Strategy needs Governor address (as strategyAdmin) and VotingConfig addresses
     * - VotingConfigs (weight strategies and vote trackers) need Strategy address during initialization
     *
     * This two-step process allows: 1) Deploy Strategy, 2) Deploy Governor with Strategy address,
     * 3) Deploy VotingConfigs with Strategy address, 4) Call initialize2 with Governor and configs.
     *
     * @param votingPeriod_ Duration in seconds for voting on each proposal
     * @param quorumThreshold_ Minimum total voting weight (YES + ABSTAIN) required for a proposal to pass
     * @param basisNumerator_ Numerator for basis calculation (denominator is 1,000,000).
     * Must be >= 500,000 (50%) and < 1,000,000 (100%)
     * @param proposerAdapters_ Array of adapter contracts that determine who can create proposals
     * @param lightAccountFactory_ Factory address for Light Account creation (ERC-4337 support)
     * @custom:throws NoProposerAdapters if proposerAdapters_ array is empty
     * @custom:throws InvalidBasisNumerator if basisNumerator_ is out of valid range
     */
    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) external;

    /**
     * @notice Completes initialization with admin and voting configurations (part 2 of 2)
     * @dev Must be called after initialize() to complete the setup. This second step
     * provides the addresses that couldn't be provided in step 1 due to circular dependencies.
     * @param strategyAdmin_ Address that can initialize proposals and manage freeze voters (typically Governor)
     * @param votingConfigs_ Array of voting configurations (weight strategy + vote tracker pairs)
     * @custom:throws NoVotingConfigs if votingConfigs_ array is empty
     */
    function initialize2(
        address strategyAdmin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) external;

    // --- View Functions ---

    /**
     * @notice Checks if an address is eligible to create proposals
     * @dev Queries the specified proposer adapter with the provided data
     * @param address_ The address to check
     * @param proposerAdapter_ The proposer adapter contract to query
     * @param proposerAdapterData_ Additional data for the adapter (adapter-specific)
     * @return isProposer True if the address can create proposals through this adapter
     * @custom:throws InvalidProposerAdapter if the adapter is not configured
     */
    function isProposer(
        address address_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) external view returns (bool isProposer);

    /**
     * @notice Determines if a proposal has passed all requirements
     * @dev A proposal passes if voting has ended, quorum is met, and basis is met
     * @param proposalId_ The proposal to check
     * @return isPassed True if the proposal has passed
     * @custom:throws ProposalNotInitialized if the proposal doesn't exist
     */
    function isPassed(uint32 proposalId_) external view returns (bool isPassed);

    /**
     * @notice Returns the voting period timestamps for a proposal
     * @param proposalId_ The proposal to query
     * @return startTime When voting begins (Unix timestamp)
     * @return endTime When voting ends (Unix timestamp)
     * @custom:throws ProposalNotInitialized if the proposal doesn't exist
     */
    function getVotingTimestamps(
        uint32 proposalId_
    ) external view returns (uint48 startTime, uint48 endTime);

    /**
     * @notice Returns the block number when voting started (for snapshot purposes)
     * @param proposalId_ The proposal to query
     * @return votingStartBlock The block number when voting began
     * @custom:throws ProposalNotInitialized if the proposal doesn't exist
     */
    function getVotingStartBlock(
        uint32 proposalId_
    ) external view returns (uint32 votingStartBlock);

    /**
     * @notice Returns all configured voting configurations
     * @return votingConfigs Array of voting configurations
     */
    function votingConfigs()
        external
        view
        returns (IVotingTypes.VotingConfig[] memory votingConfigs);

    /**
     * @notice Checks if an address is a configured proposer adapter
     * @param proposerAdapter_ The address to check
     * @return isProposerAdapter True if this is a configured proposer adapter
     */
    function isProposerAdapter(
        address proposerAdapter_
    ) external view returns (bool isProposerAdapter);

    /**
     * @notice Returns the strategy admin address
     * @dev The strategy admin can initialize proposals and manage freeze voters
     * @return strategyAdmin The admin address (typically the Governor module)
     */
    function strategyAdmin() external view returns (address strategyAdmin);

    /**
     * @notice Returns the voting period duration
     * @return votingPeriod Duration in seconds for each proposal's voting period
     */
    function votingPeriod() external view returns (uint32 votingPeriod);

    /**
     * @notice Returns the quorum threshold
     * @dev This is the minimum total weight of YES + ABSTAIN votes required
     * @return quorumThreshold The minimum voting weight for quorum
     */
    function quorumThreshold() external view returns (uint256 quorumThreshold);

    /**
     * @notice Returns the basis numerator
     * @dev Used with BASIS_DENOMINATOR (1,000,000) to calculate required approval percentage
     * @return basisNumerator The numerator for basis calculations
     */
    function basisNumerator() external view returns (uint256 basisNumerator);

    /**
     * @notice Returns all voting details for a proposal
     * @param proposalId_ The proposal to query
     * @return proposalVotingDetails Complete voting state including timestamps and vote tallies
     */
    function proposalVotingDetails(
        uint32 proposalId_
    )
        external
        view
        returns (ProposalVotingDetails memory proposalVotingDetails);

    /**
     * @notice Returns a specific voting configuration
     * @param configIndex_ The index of the voting config to retrieve
     * @return votingConfig The voting configuration at the specified index
     */
    function votingConfig(
        uint256 configIndex_
    ) external view returns (IVotingTypes.VotingConfig memory votingConfig);

    /**
     * @notice Returns all configured proposer adapter addresses
     * @return proposerAdapters Array of proposer adapter contract addresses
     */
    function proposerAdapters()
        external
        view
        returns (address[] memory proposerAdapters);

    /**
     * @notice Checks if a proposal has met the quorum requirement
     * @dev Quorum is met when YES + ABSTAIN votes >= quorumThreshold
     * @param proposalId_ The proposal to check
     * @return isQuorumMet True if quorum threshold is reached
     * @custom:throws ProposalNotInitialized if the proposal doesn't exist
     */
    function isQuorumMet(
        uint32 proposalId_
    ) external view returns (bool isQuorumMet);

    /**
     * @notice Checks if a proposal has met the basis requirement
     * @dev Basis is met when YES / (YES + NO) > basisNumerator / BASIS_DENOMINATOR
     * @param proposalId_ The proposal to check
     * @return isBasisMet True if the approval percentage exceeds the required basis
     * @custom:throws ProposalNotInitialized if the proposal doesn't exist
     */
    function isBasisMet(
        uint32 proposalId_
    ) external view returns (bool isBasisMet);

    /**
     * @notice Checks if an address is authorized to participate in freeze voting
     * @param freezeVoterContract_ The freeze voting contract to check
     * @return isAuthorizedFreezeVoter True if authorized for freeze voting
     */
    function isAuthorizedFreezeVoter(
        address freezeVoterContract_
    ) external view returns (bool isAuthorizedFreezeVoter);

    /**
     * @notice Returns all authorized freeze voter contract addresses
     * @return authorizedFreezeVoters Array of authorized freeze voting contracts
     */
    function authorizedFreezeVoters()
        external
        view
        returns (address[] memory authorizedFreezeVoters);

    /**
     * @notice Checks if a vote was cast after the voting period ended
     * @dev Used to track late votes for informational purposes
     * @param proposalId_ The proposal to check
     * @return voteCastedAfterVotingPeriodEnded True if a late vote was attempted
     */
    function voteCastedAfterVotingPeriodEnded(
        uint32 proposalId_
    ) external view returns (bool voteCastedAfterVotingPeriodEnded);

    /**
     * @notice Validates if a vote configuration would be valid without casting it
     * @dev Useful for UI validation before submitting transactions
     * @param voter_ The address that would cast the vote
     * @param proposalId_ The proposal to vote on
     * @param voteType_ The type of vote (0=NO, 1=YES, 2=ABSTAIN)
     * @param votingConfigsData_ Array of voting configs and their data
     * @return isValid True if the vote configuration is valid
     */
    function validStrategyVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_
    ) external view returns (bool isValid);

    // --- State-Changing Functions ---

    /**
     * @notice Initializes voting parameters for a new proposal
     * @dev Only callable by the strategy admin (typically Governor module).
     * Sets the voting start/end times and start block. Can be called multiple
     * times for the same proposal to reset voting.
     * @param proposalId_ The proposal to initialize
     * @custom:access Restricted to strategyAdmin
     * @custom:emits ProposalInitialized with voting period details
     */
    function initializeProposal(uint32 proposalId_) external;

    /**
     * @notice Casts a vote on an active proposal
     * @dev Aggregates voting weight from multiple voting configurations in a single transaction.
     * Supports Light Account voting through account abstraction.
     * Each configuration enforces its own voting constraints (e.g., ERC20 configs may limit
     * one vote per address, while ERC721 configs allow one vote per NFT).
     * The same address can call castVote multiple times if using different voting
     * credentials (e.g., different NFTs) that the configurations consider valid.
     * @param proposalId_ The proposal to vote on
     * @param voteType_ Type of vote: 0=NO, 1=YES, 2=ABSTAIN
     * @param votingConfigsData_ Array of voting configs to use with their specific data
     * @param lightAccountIndex_ Index for Light Account resolution (0 for direct voting)
     * @custom:throws ProposalNotInitialized if proposal doesn't exist
     * @custom:throws ProposalNotActive if voting period has ended
     * @custom:throws InvalidVoteType if voteType_ > 2
     * @custom:throws InvalidVotingConfig if config index is out of bounds
     * @custom:throws NoVotingWeight if config returns zero weight
     * @custom:emits Voted with voter address and total weight used
     * @custom:emits VotingPeriodEnded if voting after period (before reverting)
     */
    function castVote(
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_,
        uint256 lightAccountIndex_
    ) external;

    /**
     * @notice Adds a freeze voting contract to the authorized list
     * @dev Only callable by strategy admin. Freeze voters can participate in
     * emergency freeze voting through the strategy's voting adapters.
     * @param freezeVoterContract_ The freeze voting contract to authorize
     * @custom:access Restricted to strategyAdmin
     * @custom:throws InvalidAddress if freezeVoterContract_ is address(0)
     * @custom:emits FreezeVoterAuthorizationChanged with isAuthorized=true
     */
    function addAuthorizedFreezeVoter(address freezeVoterContract_) external;

    /**
     * @notice Removes a freeze voting contract from the authorized list
     * @dev Only callable by strategy admin. Uses swap-and-pop for array removal.
     * @param freezeVoterContract_ The freeze voting contract to remove
     * @custom:access Restricted to strategyAdmin
     * @custom:throws InvalidAddress if freezeVoterContract_ is address(0)
     * @custom:emits FreezeVoterAuthorizationChanged with isAuthorized=false
     */
    function removeAuthorizedFreezeVoter(address freezeVoterContract_) external;
}
