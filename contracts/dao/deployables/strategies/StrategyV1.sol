// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IStrategyV1} from "../../interfaces/deployables/IStrategyV1.sol";
import {
    IVotingTypes
} from "../../interfaces/deployables/IVotingTypes.sol";
import {
    IVotingWeightV1
} from "../../interfaces/deployables/IVotingWeightV1.sol";
import {
    IVoteTrackerV1
} from "../../interfaces/deployables/IVoteTrackerV1.sol";
import {
    IProposerAdapterBaseV1
} from "../../interfaces/deployables/IProposerAdapterBaseV1.sol";
import {
    ILightAccountValidator
} from "../../interfaces/deployables/ILightAccountValidator.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {
    LightAccountValidator
} from "../account-abstraction/LightAccountValidator.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title StrategyV1
 * @author Lux Industriesn Inc
 * @notice Implementation of the core voting strategy for Governor governance
 * @dev This contract implements IStrategyV1, providing the voting logic and rules
 * for proposals created through ModuleGovernorV1.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for future upgradeability
 * - Non-upgradeable contract deployed per DAO
 * - Integrates Light Account support for gasless voting
 * - Supports multiple voting configurations and proposer adapters
 * - Implements two-phase initialization to resolve circular dependencies
 * - Tracks late vote attempts for informational purposes for gasless voting support
 * - Uses swap-and-pop pattern for array removals
 *
 * @custom:security-contact security@lux.network
 */
contract StrategyV1 is
    IStrategyV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    LightAccountValidator,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for StrategyV1 following EIP-7201
     * @dev Contains all voting configuration and proposal state
     * @custom:storage-location erc7201:DAO.Strategy.main
     */
    struct StrategyStorage {
        /** @notice Address that can initialize proposals and manage freeze voters (typically Governor) */
        address strategyAdmin;
        /** @notice Fixed duration in seconds for all proposal voting periods */
        uint32 votingPeriod;
        /** @notice Minimum total weight (YES + ABSTAIN) required for quorum */
        uint256 quorumThreshold;
        /** @notice Numerator for basis calculation (denominator is 1,000,000) */
        uint256 basisNumerator;
        /** @notice Mapping from proposal ID to voting details and tallies */
        mapping(uint32 proposalId => ProposalVotingDetails proposalVotingDetails) proposalVotingDetails;
        /** @notice Array of configured voting configurations */
        IVotingTypes.VotingConfig[] votingConfigs;
        /** @notice Array of configured proposer adapter addresses */
        address[] proposerAdapters;
        /** @notice Quick lookup for valid proposer adapters */
        mapping(address proposerAdapter => bool isProposerAdapter) isProposerAdapter;
        /** @notice Tracks authorized freeze voting contracts */
        mapping(address freezeVoterContract => bool isAuthorizedFreezeVoter) authorizedFreezeVotersMapping;
        /** @notice Array of authorized freeze voter addresses for enumeration */
        address[] authorizedFreezeVotersArray;
        /** @notice Tracks if someone tried to vote after voting period ended */
        mapping(uint32 proposalId => bool voteCastedAfterVotingPeriodEnded) voteCastedAfterVotingPeriodEnded;
    }

    /**
     * @dev Storage slot for StrategyStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.Strategy.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant STRATEGY_STORAGE_LOCATION =
        0x95295deadfd7c71125b4fbd75b5d49605029b50806f286522633fd9c072a4700;

    /**
     * @dev Returns the storage struct for StrategyV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for StrategyV1
     */
    function _getStrategyStorage()
        internal
        pure
        returns (StrategyStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := STRATEGY_STORAGE_LOCATION
        }
    }

    /**
     * @notice Denominator for basis percentage calculations (represents 100%)
     * @dev Used with basisNumerator to calculate required approval percentage
     */
    uint256 public constant BASIS_DENOMINATOR = 1_000_000;

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    /**
     * @notice Restricts function access to the strategy admin
     * @dev The strategy admin is typically the Governor module that manages this strategy
     * @custom:throws InvalidStrategyAdmin if msg.sender is not the strategy admin
     */
    modifier onlyStrategyAdmin() {
        StrategyStorage storage $ = _getStrategyStorage();
        if (msg.sender != $.strategyAdmin) revert InvalidStrategyAdmin();
        _;
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) public virtual override initializer {
        // Validate at least one proposer adapter is provided
        if (proposerAdapters_.length == 0) {
            revert NoProposerAdapters();
        }

        // Validate basis numerator is within acceptable range
        // Must be at least 50% (500,000) and less than 100% (1,000,000)
        if (
            basisNumerator_ >= BASIS_DENOMINATOR ||
            basisNumerator_ < BASIS_DENOMINATOR / 2
        ) revert InvalidBasisNumerator();

        // Initialize parent contracts
        __LightAccountValidator_init(lightAccountFactory_);
        __DeploymentBlockInitializable_init();
        __InitializerEventEmitter_init(
            abi.encode(
                votingPeriod_,
                quorumThreshold_,
                basisNumerator_,
                proposerAdapters_,
                lightAccountFactory_
            )
        );

        // Store voting configuration
        StrategyStorage storage $ = _getStrategyStorage();
        $.votingPeriod = votingPeriod_;
        $.quorumThreshold = quorumThreshold_;
        $.basisNumerator = basisNumerator_;
        $.proposerAdapters = proposerAdapters_;

        // Mark all provided adapters as valid proposer adapters
        for (uint256 i = 0; i < proposerAdapters_.length; ) {
            $.isProposerAdapter[proposerAdapters_[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function initialize2(
        address strategyAdmin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) public virtual override reinitializer(2) {
        // Validate at least one voting config is provided
        if (votingConfigs_.length == 0) {
            revert NoVotingConfigs();
        }

        StrategyStorage storage $ = _getStrategyStorage();

        // Set the strategy admin (typically the Governor module that will manage this strategy)
        $.strategyAdmin = strategyAdmin_;

        // Store the array of voting configurations
        for (uint256 i = 0; i < votingConfigs_.length; ) {
            $.votingConfigs.push(votingConfigs_[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // IStrategyV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IStrategyV1
     */
    function strategyAdmin() public view virtual override returns (address) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.strategyAdmin;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function votingPeriod() public view virtual override returns (uint32) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.votingPeriod;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function quorumThreshold() public view virtual override returns (uint256) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.quorumThreshold;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function basisNumerator() public view virtual override returns (uint256) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.basisNumerator;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function proposalVotingDetails(
        uint32 proposalId
    ) public view virtual override returns (ProposalVotingDetails memory) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.proposalVotingDetails[proposalId];
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function votingConfigs()
        public
        view
        virtual
        override
        returns (IVotingTypes.VotingConfig[] memory)
    {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.votingConfigs;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function votingConfig(
        uint256 configIndex_
    ) public view virtual override returns (IVotingTypes.VotingConfig memory) {
        StrategyStorage storage $ = _getStrategyStorage();
        if (configIndex_ >= $.votingConfigs.length) {
            revert InvalidVotingConfig(configIndex_);
        }
        return $.votingConfigs[configIndex_];
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function isProposerAdapter(
        address proposerAdapter_
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.isProposerAdapter[proposerAdapter_];
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function proposerAdapters()
        public
        view
        virtual
        override
        returns (address[] memory)
    {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.proposerAdapters;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function voteCastedAfterVotingPeriodEnded(
        uint32 proposalId_
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.voteCastedAfterVotingPeriodEnded[proposalId_];
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Calculates quorum based on YES + ABSTAIN votes. NO votes do not contribute to quorum.
     */
    function isQuorumMet(
        uint32 proposalId_
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage proposal = $.proposalVotingDetails[
            proposalId_
        ];

        if (proposal.votingEndTimestamp == 0) {
            revert ProposalNotInitialized();
        }

        uint256 totalVotesForQuorum = proposal.yesVotes + proposal.abstainVotes;
        return totalVotesForQuorum >= $.quorumThreshold;
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Uses integer multiplication to avoid division precision loss.
     * Formula: yesVotes * BASIS_DENOMINATOR > (yesVotes + noVotes) * basisNumerator
     */
    function isBasisMet(
        uint32 _proposalId
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage proposal = $.proposalVotingDetails[
            _proposalId
        ];

        if (proposal.votingEndTimestamp == 0) {
            revert ProposalNotInitialized();
        }

        return
            (proposal.yesVotes * BASIS_DENOMINATOR) >
            ((proposal.yesVotes + proposal.noVotes) * $.basisNumerator);
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev A proposal must meet all three conditions to pass:
     * 1. Voting period has ended (current timestamp > votingEndTimestamp)
     * 2. Quorum is met (YES + ABSTAIN votes >= quorumThreshold)
     * 3. Basis is met (YES votes exceed required percentage of YES + NO votes)
     */
    function isPassed(
        uint32 _proposalId
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage proposal = $.proposalVotingDetails[
            _proposalId
        ];

        if (proposal.votingEndTimestamp == 0) {
            revert ProposalNotInitialized();
        }

        if (block.timestamp <= proposal.votingEndTimestamp) {
            return false;
        }

        return isQuorumMet(_proposalId) && isBasisMet(_proposalId);
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Delegates the eligibility check to the specified proposer adapter
     */
    function isProposer(
        address address_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        if (!$.isProposerAdapter[proposerAdapter_]) {
            revert InvalidProposerAdapter();
        }

        return
            IProposerAdapterBaseV1(proposerAdapter_).isProposer(
                address_,
                proposerAdapterData_
            );
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function getVotingTimestamps(
        uint32 proposalId_
    ) public view virtual override returns (uint48, uint48) {
        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage details = $.proposalVotingDetails[
            proposalId_
        ];
        if (details.votingEndTimestamp == 0) revert ProposalNotInitialized();
        return (details.votingStartTimestamp, details.votingEndTimestamp);
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function getVotingStartBlock(
        uint32 proposalId_
    ) public view virtual override returns (uint32) {
        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage details = $.proposalVotingDetails[
            proposalId_
        ];
        if (details.votingEndTimestamp == 0) revert ProposalNotInitialized();
        return details.votingStartBlock;
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function isAuthorizedFreezeVoter(
        address freezeVoterContract_
    ) public view virtual override returns (bool) {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.authorizedFreezeVotersMapping[freezeVoterContract_];
    }

    /**
     * @inheritdoc IStrategyV1
     */
    function authorizedFreezeVoters()
        public
        view
        virtual
        override
        returns (address[] memory)
    {
        StrategyStorage storage $ = _getStrategyStorage();
        return $.authorizedFreezeVotersArray;
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Validates whether a vote configuration is eligible for gas sponsorship through ERC-4337 paymaster.
     * This function is specifically designed for the gasless voting flow where:
     * 1. User signs a vote operation off-chain
     * 2. ERC-4337 bundler submits it through a Light Account
     * 3. DAOPaymasterV1 calls its validator
     * 4. Validator calls this function to determine if the vote should be sponsored
     *
     * IMPORTANT: This function uses getVotingWeightForPaymaster() instead of calculateWeight()
     * to avoid ERC-4337 banned opcodes (block.timestamp, block.number) during validation phase.
     *
     * Validation checks:
     * - Proposal exists and is still active
     * - Vote type is valid (NO=0, YES=1, ABSTAIN=2)
     * - All voting configs are valid
     * - Voter has voting weight > 0
     * - Voter hasn't already voted with these configs
     */
    function validStrategyVote(
        address voter_,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_
    ) public view virtual override returns (bool) {
        // Early return if no voting configs provided
        if (votingConfigsData_.length == 0) {
            return false;
        }

        StrategyStorage storage $ = _getStrategyStorage();

        // Step 1: Verify proposal exists by checking for initialized voting details
        ProposalVotingDetails storage details = $.proposalVotingDetails[
            proposalId_
        ];

        // Proposal doesn't exist if voting end timestamp is zero
        if (details.votingEndTimestamp == 0) {
            return false;
        }

        // Step 2: Check if someone already tried voting after the period ended
        // This is tracked for informational purposes to support gasless voting
        if ($.voteCastedAfterVotingPeriodEnded[proposalId_]) {
            return false;
        }

        // Step 3: Validate vote type is within valid enum range
        // VoteType enum: NO=0, YES=1, ABSTAIN=2
        if (voteType_ > 2) {
            return false;
        }

        uint256 totalVotingWeight = 0;

        // Step 4: Iterate through each voting config to validate and sum voting weights
        for (uint256 i = 0; i < votingConfigsData_.length; ) {
            IVotingTypes.VotingConfigVoteData
                memory configData = votingConfigsData_[i];

            // Verify the config index is valid
            if (configData.configIndex >= $.votingConfigs.length) {
                return false;
            }

            IVotingTypes.VotingConfig memory config = $.votingConfigs[
                configData.configIndex
            ];

            // Calculate voting weight using paymaster-safe method
            // This avoids banned opcodes during ERC-4337 validation phase
            uint256 votingWeight = IVotingWeightV1(config.votingWeight)
                .getVotingWeightForPaymaster(
                    voter_,
                    details.votingStartTimestamp,
                    configData.voteData
                );

            if (votingWeight == 0) {
                return false;
            }

            // Check if already voted with this config
            if (
                IVoteTrackerV1(config.voteTracker).hasVoted(
                    proposalId_,
                    voter_,
                    configData.voteData
                )
            ) {
                return false;
            }

            // Accumulate voting weight from all configs
            totalVotingWeight += votingWeight;

            unchecked {
                ++i;
            }
        }

        // Step 5: Ensure the voter has at least some voting power
        return totalVotingWeight > 0;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IStrategyV1
     * @dev Sets voting timestamps based on current block time and configured voting period.
     * Resets all vote counts to zero, allowing proposals to be re-initialized if needed.
     */
    function initializeProposal(
        uint32 proposalId_
    ) public virtual override onlyStrategyAdmin {
        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage proposal = $.proposalVotingDetails[
            proposalId_
        ];
        proposal.votingStartTimestamp = uint48(block.timestamp);
        proposal.votingEndTimestamp = uint48(block.timestamp + $.votingPeriod);
        proposal.votingStartBlock = uint32(block.number);
        proposal.yesVotes = 0;
        proposal.noVotes = 0;
        proposal.abstainVotes = 0;

        emit ProposalInitialized(
            proposalId_,
            proposal.votingStartTimestamp,
            proposal.votingEndTimestamp,
            proposal.votingStartBlock
        );
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Implementation notes:
     * - Resolves Light Account ownership for gasless voting support
     * - Tracks late vote attempts for the first occurrence per proposal
     * - Aggregates weights from all voting configs before updating vote tallies
     * - Each voting config enforces its own vote recording logic and constraints
     */
    function castVote(
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_,
        uint256 lightAccountIndex_
    ) public virtual override {
        // Validate at least one voting config is provided
        if (votingConfigsData_.length == 0) {
            revert NoVotingConfigs();
        }

        // Step 1: Resolve the actual voter address (support for Light Accounts/ERC-4337)
        // If lightAccountIndex_ > 0, this resolves to the Light Account owner
        address resolvedVoter = potentialLightAccountResolvedOwner(
            msg.sender,
            lightAccountIndex_
        );

        StrategyStorage storage $ = _getStrategyStorage();
        ProposalVotingDetails storage proposal = $.proposalVotingDetails[
            proposalId_
        ];

        // Step 2: Verify the proposal has been initialized
        if (proposal.votingEndTimestamp == 0) {
            revert ProposalNotInitialized();
        }

        // Step 3: Check if voting period has ended
        if (block.timestamp > proposal.votingEndTimestamp) {
            // Track the first late vote attempt for informational purposes
            // This helps with gasless voting infrastructure
            if (!$.voteCastedAfterVotingPeriodEnded[proposalId_]) {
                $.voteCastedAfterVotingPeriodEnded[proposalId_] = true;
                emit VotingPeriodEnded(proposalId_);
                return; // Exit gracefully on first late attempt
            }
            revert ProposalNotActive();
        }

        // Step 4: Process votes through each config and accumulate voting weights
        uint256 totalWeightForThisVoteTransaction = 0;

        for (uint256 i = 0; i < votingConfigsData_.length; ) {
            IVotingTypes.VotingConfigVoteData
                memory configData = votingConfigsData_[i];

            // Verify the config index is valid
            if (configData.configIndex >= $.votingConfigs.length) {
                revert InvalidVotingConfig(configData.configIndex);
            }

            IVotingTypes.VotingConfig memory config = $.votingConfigs[
                configData.configIndex
            ];

            // Calculate voting weight and get processed data
            (
                uint256 votingWeight,
                bytes memory processedData
            ) = IVotingWeightV1(config.votingWeight).calculateWeight(
                    resolvedVoter,
                    proposal.votingStartTimestamp,
                    configData.voteData
                );

            // Ensure valid voting weight
            if (votingWeight == 0) {
                revert NoVotingWeight(configData.configIndex);
            }

            // Record the vote to prevent double voting
            IVoteTrackerV1(config.voteTracker).recordVote(
                proposalId_,
                resolvedVoter,
                processedData
            );

            totalWeightForThisVoteTransaction += votingWeight;

            unchecked {
                ++i;
            }
        }

        // Step 5: Update vote tallies based on vote type
        if (voteType_ == uint8(VoteType.YES)) {
            proposal.yesVotes += totalWeightForThisVoteTransaction;
        } else if (voteType_ == uint8(VoteType.NO)) {
            proposal.noVotes += totalWeightForThisVoteTransaction;
        } else if (voteType_ == uint8(VoteType.ABSTAIN)) {
            proposal.abstainVotes += totalWeightForThisVoteTransaction;
        } else {
            revert InvalidVoteType();
        }

        // Step 6: Emit voting event with aggregated weight
        emit Voted(
            resolvedVoter,
            proposalId_,
            VoteType(voteType_),
            totalWeightForThisVoteTransaction
        );
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Maintains both a mapping for O(1) lookups and an array for enumeration.
     * Prevents duplicates in the array while allowing re-authorization.
     */
    function addAuthorizedFreezeVoter(
        address freezeVoterContract_
    ) public virtual override onlyStrategyAdmin {
        if (freezeVoterContract_ == address(0)) revert InvalidAddress();

        StrategyStorage storage $ = _getStrategyStorage();

        if (!$.authorizedFreezeVotersMapping[freezeVoterContract_]) {
            $.authorizedFreezeVotersArray.push(freezeVoterContract_);
        }
        $.authorizedFreezeVotersMapping[freezeVoterContract_] = true;

        emit FreezeVoterAuthorizationChanged(freezeVoterContract_, true);
    }

    /**
     * @inheritdoc IStrategyV1
     * @dev Uses swap-and-pop pattern for gas-efficient array removal.
     * Sets mapping to false regardless of whether the address was previously authorized.
     */
    function removeAuthorizedFreezeVoter(
        address freezeVoterContract_
    ) public virtual override onlyStrategyAdmin {
        if (freezeVoterContract_ == address(0)) revert InvalidAddress();

        StrategyStorage storage $ = _getStrategyStorage();

        if ($.authorizedFreezeVotersMapping[freezeVoterContract_]) {
            for (uint256 i = 0; i < $.authorizedFreezeVotersArray.length; ) {
                if ($.authorizedFreezeVotersArray[i] == freezeVoterContract_) {
                    $.authorizedFreezeVotersArray[i] = $
                        .authorizedFreezeVotersArray[
                            $.authorizedFreezeVotersArray.length - 1
                        ];
                    $.authorizedFreezeVotersArray.pop();
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }

        $.authorizedFreezeVotersMapping[freezeVoterContract_] = false;

        emit FreezeVoterAuthorizationChanged(freezeVoterContract_, false);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports IStrategyV1, ILightAccountValidator, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IStrategyV1).interfaceId ||
            interfaceId_ == type(ILightAccountValidator).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
