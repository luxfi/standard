// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IFreezeVotingStandaloneV1
} from "../../interfaces/deployables/IFreezeVotingStandaloneV1.sol";
import {IFreezable} from "../../interfaces/deployables/IFreezable.sol";
import {
    IVotingTypes
} from "../../interfaces/deployables/IVotingTypes.sol";
import {
    IVotingWeightV1
} from "../../interfaces/deployables/IVotingWeightV1.sol";
import {
    IVoteTrackerV1
} from "../../interfaces/deployables/IVoteTrackerV1.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {
    ILightAccountValidator
} from "../../interfaces/deployables/ILightAccountValidator.sol";
import {
    IFreezeVotingBase
} from "../../interfaces/deployables/IFreezeVotingBase.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {FreezeVotingBase} from "./FreezeVotingBase.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title FreezeVotingStandaloneV1
 * @author Lux Industriesn Inc
 * @notice Implementation of standalone freeze voting for multisig Safes
 * @dev This contract implements IFreezeVotingStandaloneV1, enabling token holders
 * to freeze and unfreeze a multisig Safe without requiring parent/child DAO structure.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Inherits base functionality from FreezeVotingBase but overrides key behavior
 * - Implements permanent freezing (no auto-unfreeze after time period)
 * - Automatically unfreezes when unfreeze votes reach the threshold
 * - Manages its own list of VotingConfigs (weightStrategy + voteTracker pairs)
 * - No longer needs to implement IStrategyV1 interface
 *
 * Key differences from parent/child freeze voting:
 * - Owned by the Safe itself, not a parent DAO
 * - Permanent freeze state until explicit unfreeze vote
 * - All pre-freeze transactions are invalidated by the guard
 *
 * Security model:
 * - VotingConfig changes require timelocked Safe transactions
 * - Unfreeze happens automatically when voting reaches threshold
 * - Owner validation ensures only Safe can manage configs
 *
 * @custom:security-contact security@lux.network
 */
contract FreezeVotingStandaloneV1 is
    IFreezeVotingStandaloneV1,
    IVersion,
    FreezeVotingBase,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for FreezeVotingStandaloneV1 following EIP-7201
     * @dev Contains all state specific to standalone freeze voting
     * @custom:storage-location erc7201:DAO.FreezeVotingStandalone.main
     */
    struct FreezeVotingStandaloneStorage {
        /** @notice Array of all configured voting configs */
        IVotingTypes.VotingConfig[] votingConfigs;
        /** @notice Voting weight required to unfreeze the DAO */
        uint256 unfreezeVotesThreshold;
        /** @notice Duration in seconds that unfreeze proposals remain active */
        uint32 unfreezeProposalPeriod;
        /** @notice Timestamp when the unfreeze proposal was created */
        uint48 unfreezeProposalCreated;
        /** @notice Accumulated votes for the unfreeze proposal */
        uint256 unfreezeProposalVoteCount;
    }

    /**
     * @dev Storage slot for FreezeVotingStandaloneStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.FreezeVotingStandalone.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant FREEZE_VOTING_STANDALONE_STORAGE_LOCATION =
        0x594954084daa378f6dac672b6cff1af2fa563a4db2a7dd9c13a2232741e74500;

    /**
     * @dev Returns the storage struct for FreezeVotingStandaloneV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for FreezeVotingStandaloneV1
     */
    function _getFreezeVotingStandaloneStorage()
        internal
        pure
        returns (FreezeVotingStandaloneStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := FREEZE_VOTING_STANDALONE_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     * @dev First initialization step that sets up base parameters.
     * Voting configs must be set via initialize2.
     */
    function initialize(
        uint256 freezeVotesThreshold_,
        uint256 unfreezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        uint32 unfreezeProposalPeriod_,
        address lightAccountFactory_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(
                freezeVotesThreshold_,
                unfreezeVotesThreshold_,
                freezeProposalPeriod_,
                unfreezeProposalPeriod_,
                lightAccountFactory_
            )
        );
        __FreezeVotingBase_init(
            freezeProposalPeriod_,
            freezeVotesThreshold_,
            lightAccountFactory_
        );
        __DeploymentBlockInitializable_init();

        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();
        $.unfreezeVotesThreshold = unfreezeVotesThreshold_;
        $.unfreezeProposalPeriod = unfreezeProposalPeriod_;
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     * @dev Can only be called once when votingConfigs is empty.
     * Used for circular dependency resolution during deployment.
     */
    function initialize2(
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) public virtual override reinitializer(2) {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();

        // Set voting configs
        for (uint256 i = 0; i < votingConfigs_.length; ) {
            $.votingConfigs.push(votingConfigs_[i]);

            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // IFreezeVotingStandaloneV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function getVotingConfigs()
        public
        view
        virtual
        override
        returns (IVotingTypes.VotingConfig[] memory)
    {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();
        return $.votingConfigs;
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function votingConfig(
        uint256 index
    ) public view virtual override returns (IVotingTypes.VotingConfig memory) {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();
        if (index >= $.votingConfigs.length) {
            revert InvalidVotingConfig(index);
        }
        return $.votingConfigs[index];
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function unfreezeVotesThreshold()
        public
        view
        virtual
        override
        returns (uint256)
    {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();
        return $.unfreezeVotesThreshold;
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function unfreezeProposalPeriod()
        public
        view
        virtual
        override
        returns (uint32)
    {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();
        return $.unfreezeProposalPeriod;
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function getUnfreezeProposalVotes()
        public
        view
        virtual
        override
        returns (uint256)
    {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();
        return $.unfreezeProposalVoteCount;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function castFreezeVote(
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_,
        uint256 lightAccountIndex_
    ) public virtual override {
        // Check if already frozen
        if (isFrozen()) revert AlreadyFrozen();

        // Resolve voter address (handles light account)
        address voter = potentialLightAccountResolvedOwner(
            msg.sender,
            lightAccountIndex_
        );

        // Check if proposal is expired and create new one if needed
        FreezeVotingBaseStorage storage $base = _getFreezeVotingBaseStorage();
        if (
            block.timestamp >
            $base.freezeProposalCreated + $base.freezeProposalPeriod
        ) {
            _initializeFreezeVote();
            emit FreezeProposalCreated(uint48(block.timestamp), voter);
        }

        // Calculate total weight from all configs
        uint256 totalWeight = _getVotes(voter, votingConfigsToUse_);

        // Record the vote and handle freeze activation if threshold is reached
        _recordFreezeVote(voter, totalWeight);
    }

    /**
     * @inheritdoc IFreezeVotingStandaloneV1
     */
    function castUnfreezeVote(
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse_,
        uint256 lightAccountIndex_
    ) public virtual override {
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();

        // Check if frozen
        if (!isFrozen()) revert NotFrozen();

        // Resolve voter address
        address voter = potentialLightAccountResolvedOwner(
            msg.sender,
            lightAccountIndex_
        );

        // Check if proposal is expired and create new one if needed
        if (
            $.unfreezeProposalCreated != 0 &&
            block.timestamp >
            $.unfreezeProposalCreated + $.unfreezeProposalPeriod
        ) {
            // Reset expired proposal
            // Use previous timestamp to ensure ERC5805 getPastVotes works
            $.unfreezeProposalCreated = uint48(block.timestamp - 1);
            $.unfreezeProposalVoteCount = 0;
        }

        // Initialize new proposal if needed
        if ($.unfreezeProposalCreated == 0) {
            // Use previous timestamp to ensure ERC5805 getPastVotes works
            $.unfreezeProposalCreated = uint48(block.timestamp - 1);
            emit UnfreezeProposalCreated(uint48(block.timestamp - 1), voter);
        }

        // Calculate weight from configs
        uint256 totalWeight = _getUnfreezeVotes(
            voter,
            $.unfreezeProposalCreated,
            votingConfigsToUse_
        );

        // Record the vote and handle unfreeze activation if threshold is reached
        _recordUnfreezeVote(voter, totalWeight);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

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
     * @dev Supports IFreezeVotingStandaloneV1, IFreezeVotingBase, IFreezable, ILightAccountValidator, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IFreezeVotingStandaloneV1).interfaceId ||
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
     * @notice Aggregates voting weight from multiple voting configs for freeze votes
     * @dev Validates each config and records freeze votes
     * @param voter The resolved voter address
     * @param votingConfigsToUse Array of voting configs and their data
     * @return totalWeight Total voting weight accumulated
     */
    function _getVotes(
        address voter,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse
    ) internal virtual returns (uint256) {
        FreezeVotingBaseStorage storage $base = _getFreezeVotingBaseStorage();
        return
            _aggregateVotes(
                voter,
                $base.freezeProposalCreated,
                $base.freezeProposalCreated, // Use same timestamp as context ID for freeze votes
                votingConfigsToUse
            );
    }

    /**
     * @notice Aggregates voting weight from multiple voting configs for unfreeze votes
     * @dev Similar to _getVotes but for unfreeze proposals
     * @param voter The resolved voter address
     * @param proposalCreatedAt When the unfreeze proposal was created
     * @param votingConfigsToUse Array of voting configs and their data
     * @return totalWeight Total voting weight accumulated
     */
    function _getUnfreezeVotes(
        address voter,
        uint48 proposalCreatedAt,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse
    ) internal virtual returns (uint256) {
        // We add a large offset to avoid collision with freeze vote timestamps
        uint256 unfreezeContextId = uint256(proposalCreatedAt) + (1 << 128);
        return
            _aggregateVotes(
                voter,
                proposalCreatedAt,
                unfreezeContextId,
                votingConfigsToUse
            );
    }

    /**
     * @notice Common logic for aggregating votes from multiple voting configs
     * @dev Validates configs, calculates weights, and records votes
     * @param voter The resolved voter address
     * @param timestamp The timestamp to use for weight calculation
     * @param contextId The context ID to use for vote tracking
     * @param votingConfigsToUse Array of voting configs and their data
     * @return totalWeight Total voting weight accumulated
     */
    function _aggregateVotes(
        address voter,
        uint48 timestamp,
        uint256 contextId,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsToUse
    ) private returns (uint256) {
        uint256 totalWeight = 0;
        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();

        for (uint256 i = 0; i < votingConfigsToUse.length; ) {
            IVotingTypes.VotingConfigVoteData
                memory configData = votingConfigsToUse[i];

            // Validate config index
            if (configData.configIndex >= $.votingConfigs.length) {
                revert InvalidVotingConfig(configData.configIndex);
            }

            IVotingTypes.VotingConfig memory config = $.votingConfigs[
                configData.configIndex
            ];

            // Calculate voting weight at the specified timestamp
            (uint256 weight, bytes memory processedData) = IVotingWeightV1(
                config.votingWeight
            ).calculateWeight(voter, timestamp, configData.voteData);

            // Check if already voted with this config
            if (
                IVoteTrackerV1(config.voteTracker).hasVoted(
                    contextId,
                    voter,
                    processedData
                )
            ) {
                // Skip if already voted with this config
                unchecked {
                    ++i;
                }
                continue;
            }

            // Record the vote
            IVoteTrackerV1(config.voteTracker).recordVote(
                contextId,
                voter,
                processedData
            );

            totalWeight += weight;

            unchecked {
                ++i;
            }
        }

        return totalWeight;
    }

    /**
     * @notice Records an unfreeze vote and activates unfreeze if threshold is reached
     * @dev Called internally after validating the vote.
     * Automatically triggers unfreeze when threshold is reached.
     * @param voter_ The address casting the vote
     * @param weightCasted_ The voting weight to add
     * @custom:throws NoVotes if weight is zero
     */
    function _recordUnfreezeVote(
        address voter_,
        uint256 weightCasted_
    ) internal virtual {
        // Validate non-zero voting weight
        if (weightCasted_ == 0) revert NoVotes();

        FreezeVotingStandaloneStorage
            storage $ = _getFreezeVotingStandaloneStorage();

        // Add votes to the current proposal
        $.unfreezeProposalVoteCount += weightCasted_;

        // Emit event for transparency
        emit UnfreezeVoteCast(voter_, weightCasted_);

        // Check if threshold is reached and activate unfreeze immediately
        if ($.unfreezeProposalVoteCount >= $.unfreezeVotesThreshold) {
            // Process the unfreeze
            FreezeVotingBaseStorage
                storage $base = _getFreezeVotingBaseStorage();
            $base.isFrozen = false;
            // CRITICAL: DO NOT clear lastFreezeTimestamp - this ensures the security invariant
            // that all transactions timelocked before the most recent freeze remain invalid

            // Reset unfreeze proposal for next time
            $.unfreezeProposalCreated = 0;
            $.unfreezeProposalVoteCount = 0;

            emit DAOUnfrozen(uint48(block.timestamp));
        }
    }
}
