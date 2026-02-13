// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IFreezeVotingGovernorV1
} from "../../interfaces/deployables/IFreezeVotingGovernorV1.sol";
import {
    IVotingTypes
} from "../../interfaces/deployables/IVotingTypes.sol";
import {
    IFreezeVotingBase
} from "../../interfaces/deployables/IFreezeVotingBase.sol";
import {IFreezable} from "../../interfaces/deployables/IFreezable.sol";
import {
    IModuleGovernorV1
} from "../../interfaces/deployables/IModuleGovernorV1.sol";
import {
    IVotingWeightV1
} from "../../interfaces/deployables/IVotingWeightV1.sol";
import {
    IVoteTrackerV1
} from "../../interfaces/deployables/IVoteTrackerV1.sol";
import {IStrategyV1} from "../../interfaces/deployables/IStrategyV1.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {
    ILightAccountValidator
} from "../../interfaces/deployables/ILightAccountValidator.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {FreezeVotingBase} from "./FreezeVotingBase.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title FreezeVotingGovernorV1
 * @author Lux Industriesn Inc
 * @notice Implementation of freeze voting for Governor-based parent DAOs
 * @dev This contract implements IFreezeVotingGovernorV1, enabling token holders
 * of an Governor-based parent DAO to vote to freeze a child DAO.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Inherits base freeze voting logic from FreezeVotingBase
 * - Integrates with parent's Governor module for strategy/adapter validation
 * - Automatically creates new freeze proposals when needed
 * - Supports multiple voting configurations in single transaction
 * - Light Account support for gasless voting
 *
 * Freeze proposal lifecycle:
 * - First voter automatically creates proposal if none active
 * - Captures parent's current strategy at proposal creation
 * - Aggregates votes from multiple voting configurations
 * - Freezes immediately when threshold reached
 * - Proposals expire after freezeProposalPeriod
 *
 * Security model:
 * - Only voting adapters from parent's strategy are allowed
 * - Parent DAO (owner) retains unfreeze capability
 * - Strategy locked at proposal creation prevents manipulation
 *
 * @custom:security-contact security@lux.network
 */
contract FreezeVotingGovernorV1 is
    IFreezeVotingGovernorV1,
    IVersion,
    FreezeVotingBase,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    Ownable2StepUpgradeable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for FreezeVotingGovernorV1 following EIP-7201
     * @dev Contains parent DAO reference and current freeze proposal strategy
     * @custom:storage-location erc7201:DAO.FreezeVotingGovernor.main
     */
    struct FreezeVotingGovernorStorage {
        /** @notice The parent DAO's Governor module for strategy validation */
        IModuleGovernorV1 parentGovernor;
        /** @notice Strategy contract snapshot for current freeze proposal */
        address freezeProposalStrategy;
    }

    /**
     * @dev Storage slot for FreezeVotingGovernorStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.FreezeVotingGovernor.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant FREEZE_VOTING_GOVERNOR_STORAGE_LOCATION =
        0x9d1b207d938f3e5b6e54413a914efe44171cda038c387334c00ec1729143ba00;

    /**
     * @dev Returns the storage struct for FreezeVotingGovernorV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for FreezeVotingGovernorV1
     */
    function _getFreezeVotingGovernorStorage()
        internal
        pure
        returns (FreezeVotingGovernorStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := FREEZE_VOTING_GOVERNOR_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IFreezeVotingGovernorV1
     * @dev Initializes base freeze voting functionality and sets parent Governor reference.
     * The parent Governor module is used to validate voting adapters.
     */
    function initialize(
        address owner_,
        uint256 freezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        address parentGovernor_,
        address lightAccountFactory_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(
                owner_,
                freezeVotesThreshold_,
                freezeProposalPeriod_,
                parentGovernor_,
                lightAccountFactory_
            )
        );
        __FreezeVotingBase_init(
            freezeProposalPeriod_,
            freezeVotesThreshold_,
            lightAccountFactory_
        );
        __Ownable_init(owner_);
        __DeploymentBlockInitializable_init();

        FreezeVotingGovernorStorage storage $ = _getFreezeVotingGovernorStorage();
        $.parentGovernor = IModuleGovernorV1(parentGovernor_);
    }

    // ======================================================================
    // IFreezeVotingGovernorV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IFreezeVotingGovernorV1
     */
    function parentGovernor() public view virtual override returns (address) {
        FreezeVotingGovernorStorage storage $ = _getFreezeVotingGovernorStorage();
        return address($.parentGovernor);
    }

    /**
     * @inheritdoc IFreezeVotingGovernorV1
     */
    function freezeProposalStrategy()
        public
        view
        virtual
        override
        returns (address)
    {
        FreezeVotingGovernorStorage storage $ = _getFreezeVotingGovernorStorage();
        return $.freezeProposalStrategy;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IFreezeVotingGovernorV1
     * @dev Implements the freeze voting logic with automatic proposal creation:
     * 1. Resolves voter address (handles Light Account voting)
     * 2. Creates new proposal if none active or expired
     * 3. Captures parent's current strategy on proposal creation
     * 4. Aggregates votes from all specified adapters
     * 5. Records vote and potentially triggers freeze
     */
    function castFreezeVote(
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_,
        uint256 lightAccountIndex_
    ) public virtual override {
        // Step 1: Resolve the actual voter (handles Light Account case)
        address resolvedVoter = potentialLightAccountResolvedOwner(
            msg.sender,
            lightAccountIndex_
        );

        FreezeVotingBaseStorage storage $base = _getFreezeVotingBaseStorage();
        FreezeVotingGovernorStorage storage $ = _getFreezeVotingGovernorStorage();

        // Step 2: Check if we need to create a new freeze proposal
        // This happens when no proposal exists or current one expired
        if (
            block.timestamp >
            $base.freezeProposalCreated + $base.freezeProposalPeriod
        ) {
            // Initialize new freeze proposal state
            _initializeFreezeVote();

            // Capture parent's current strategy to prevent manipulation
            // This ensures all votes use the same strategy configuration
            $.freezeProposalStrategy = $.parentGovernor.strategy();

            // Emit event for transparency
            emit FreezeProposalCreated(resolvedVoter, $.freezeProposalStrategy);
        }

        // Step 3: Calculate total voting weight from all adapters
        // and record the vote (potentially triggering freeze)
        _recordFreezeVote(
            resolvedVoter,
            _aggregateFreezeVotes(resolvedVoter, votingConfigsToUse_)
        );
    }

    /**
     * @inheritdoc IFreezeVotingGovernorV1
     */
    function unfreeze() public virtual override onlyOwner {
        FreezeVotingBaseStorage storage $base = _getFreezeVotingBaseStorage();
        FreezeVotingGovernorStorage storage $ = _getFreezeVotingGovernorStorage();

        // Reset all freeze state
        $base.isFrozen = false;
        $base.freezeProposalCreated = 0;
        $base.freezeProposalVoteCount = 0;

        // Clear the strategy snapshot to ensure fresh capture next time
        $.freezeProposalStrategy = address(0);
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

    /**
     * @inheritdoc ERC165
     * @dev Supports IFreezeVotingGovernorV1, IFreezeVotingBase, IFreezable, ILightAccountValidator, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IFreezeVotingGovernorV1).interfaceId ||
            interfaceId_ == type(IFreezeVotingBase).interfaceId ||
            interfaceId_ == type(IFreezable).interfaceId ||
            interfaceId_ == type(ILightAccountValidator).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Aggregates voting weight from multiple voting configurations
     * @dev Validates each config against the freeze proposal strategy before recording votes.
     * Uses the strategy snapshot to prevent manipulation during voting.
     * @param voter_ The resolved voter address
     * @param votingConfigsToUse_ Array of voting configs and their data
     * @return userVotes Total voting weight accumulated from all configs
     * @custom:throws InvalidVotingConfig if config index is out of bounds
     * @custom:throws NoVotingWeight if any config returns zero voting weight (includes config index and user input)
     */
    function _aggregateFreezeVotes(
        address voter_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_
    ) internal virtual returns (uint256) {
        uint256 userVotes = 0;

        FreezeVotingBaseStorage storage $base = _getFreezeVotingBaseStorage();
        FreezeVotingGovernorStorage storage $ = _getFreezeVotingGovernorStorage();
        IStrategyV1 strategy = IStrategyV1($.freezeProposalStrategy);

        // Process each voting config
        for (uint256 i = 0; i < votingConfigsToUse_.length; ) {
            IVotingTypes.VotingConfigVoteData
                memory configData = votingConfigsToUse_[i];

            // Validate config index
            if (configData.configIndex >= strategy.votingConfigs().length) {
                revert InvalidVotingConfig(configData.configIndex);
            }

            IVotingTypes.VotingConfig memory config = strategy.votingConfig(
                configData.configIndex
            );

            // Calculate voting weight at freeze proposal creation time
            (uint256 weight, bytes memory processedData) = IVotingWeightV1(
                config.votingWeight
            ).calculateWeight(
                    voter_,
                    $base.freezeProposalCreated,
                    configData.voteData
                );

            // Check for zero weight
            if (weight == 0) {
                revert NoVotingWeight(
                    configData.configIndex,
                    configData.voteData
                );
            }

            // Record the freeze vote
            IVoteTrackerV1(config.voteTracker).recordVote(
                $base.freezeProposalCreated,
                voter_,
                processedData
            );

            // Emit per-config event
            emit FreezeVoteRecorded(
                voter_,
                $base.freezeProposalCreated,
                weight,
                processedData
            );

            userVotes += weight;

            unchecked {
                ++i;
            }
        }

        return userVotes;
    }
}
