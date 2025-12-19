// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IFreezeVotingBase
} from "../../interfaces/dao/deployables/IFreezeVotingBase.sol";
import {IFreezable} from "../../interfaces/dao/deployables/IFreezable.sol";
import {
    LightAccountValidator
} from "../account-abstraction/LightAccountValidator.sol";

/**
 * @title FreezeVotingBase
 * @author Lux Industriesn Inc
 * @notice Abstract base implementation for freeze voting mechanisms
 * @dev This abstract contract implements IFreezeVotingBase, providing core freeze
 * voting functionality that concrete implementations can extend.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Inherits LightAccountValidator for gasless voting support
 * - Abstract - requires concrete implementations for specific voting logic
 * - Tracks freeze proposals with automatic expiration
 * - Implements threshold-based freeze activation
 * - Auto-unfreezes after freeze period expires
 *
 * Freeze mechanics:
 * - Votes accumulate towards threshold within proposal period
 * - Freeze activates immediately when threshold reached
 * - Concrete implementations define unfreeze behavior
 *
 * @custom:security-contact security@lux.network
 */
abstract contract FreezeVotingBase is
    IFreezeVotingBase,
    IFreezable,
    LightAccountValidator
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for FreezeVotingBase following EIP-7201
     * @dev Contains all freeze voting state and configuration
     * @custom:storage-location erc7201:DAO.FreezeVotingBase.main
     */
    struct FreezeVotingBaseStorage {
        /** @notice Timestamp when current freeze proposal was created */
        uint48 freezeProposalCreated;
        /** @notice Accumulated votes for current freeze proposal */
        uint256 freezeProposalVoteCount;
        /** @notice Duration freeze proposals remain active */
        uint32 freezeProposalPeriod;
        /** @notice Whether the DAO is currently frozen */
        bool isFrozen;
        /** @notice Voting weight required to trigger a freeze */
        uint256 freezeVotesThreshold;
        /** @notice Timestamp of the most recent freeze (NEVER cleared, even on unfreeze) */
        uint48 lastFreezeTimestamp;
    }

    /**
     * @dev Storage slot for FreezeVotingBaseStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.FreezeVotingBase.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant FREEZE_VOTING_BASE_STORAGE_LOCATION =
        0x5fcea62682ddc2ee9ccbce9f3a895c9dd644ee53c86fd38cf80a135b0e525500;

    /**
     * @dev Returns the storage struct for FreezeVotingBase
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for FreezeVotingBase
     */
    function _getFreezeVotingBaseStorage()
        internal
        pure
        returns (FreezeVotingBaseStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := FREEZE_VOTING_BASE_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Internal initializer for base freeze voting functionality
     * @dev Called by concrete implementations during initialization.
     * Sets up light account support and freeze parameters.
     * @param freezeProposalPeriod_ Duration freeze proposals remain active
     * @param freezeVotesThreshold_ Voting weight required to trigger freeze
     * @param lightAccountFactory_ Factory for gasless voting support
     */
    function __FreezeVotingBase_init(
        // solhint-disable-previous-line func-name-mixedcase
        uint32 freezeProposalPeriod_,
        uint256 freezeVotesThreshold_,
        address lightAccountFactory_
    ) internal onlyInitializing {
        // Initialize inherited contracts
        __LightAccountValidator_init(lightAccountFactory_);

        // Set freeze voting parameters
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        $.freezeVotesThreshold = freezeVotesThreshold_;
        $.freezeProposalPeriod = freezeProposalPeriod_;
    }

    // ======================================================================
    // IFreezable
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IFreezable
     * @dev Returns true if the DAO has been frozen (permanent until explicitly unfrozen)
     */
    function isFrozen() public view virtual override returns (bool) {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        return $.isFrozen;
    }

    /**
     * @inheritdoc IFreezable
     * @dev CRITICAL SECURITY FUNCTION: Returns the most recent freeze timestamp.
     * This timestamp is NEVER cleared, even after unfreeze or auto-expiry.
     * Used by guards to permanently invalidate all transactions timelocked before this time.
     */
    function lastFreezeTime() public view virtual override returns (uint48) {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        return $.lastFreezeTimestamp;
    }

    // ======================================================================
    // IFreezeVotingBase
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IFreezeVotingBase
     */
    function freezeProposalCreated()
        public
        view
        virtual
        override
        returns (uint48)
    {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        return $.freezeProposalCreated;
    }

    /**
     * @inheritdoc IFreezeVotingBase
     */
    function freezeProposalVoteCount()
        public
        view
        virtual
        override
        returns (uint256)
    {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        return $.freezeProposalVoteCount;
    }

    /**
     * @inheritdoc IFreezeVotingBase
     */
    function freezeProposalPeriod()
        public
        view
        virtual
        override
        returns (uint32)
    {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        return $.freezeProposalPeriod;
    }

    /**
     * @inheritdoc IFreezeVotingBase
     */
    function freezeVotesThreshold()
        public
        view
        virtual
        override
        returns (uint256)
    {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        return $.freezeVotesThreshold;
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Creates a new freeze proposal or resets an expired one
     * @dev Called internally when the first vote is cast on a new proposal.
     * Resets vote count for the new proposal.
     */
    function _initializeFreezeVote() internal virtual {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();

        // Start new freeze proposal
        // Use previous timestamp to ensure ERC5805 getPastVotes works
        $.freezeProposalCreated = uint48(block.timestamp - 1); // Mark creation time
        $.freezeProposalVoteCount = 0; // Reset vote count
        $.isFrozen = false; // Ensure not frozen at start
    }

    /**
     * @notice Records a freeze vote and activates freeze if threshold is reached
     * @dev Called by concrete implementations after validating the vote.
     * Automatically triggers freeze when threshold is reached.
     * @param voter_ The address casting the vote
     * @param weightCasted_ The voting weight to add
     * @custom:throws NoVotes if weight is zero
     */
    function _recordFreezeVote(
        address voter_,
        uint256 weightCasted_
    ) internal virtual {
        // Validate non-zero voting weight
        if (weightCasted_ == 0) revert NoVotes();

        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();

        // Add votes to the current proposal
        $.freezeProposalVoteCount += weightCasted_;

        // Check if threshold is reached and activate freeze immediately
        if (
            $.freezeProposalVoteCount >= $.freezeVotesThreshold && !$.isFrozen
        ) {
            // CRITICAL: Update lastFreezeTimestamp to enforce security invariant
            // This timestamp is NEVER cleared and ensures all transactions
            // timelocked before this moment are permanently invalidated
            $.lastFreezeTimestamp = uint48(block.timestamp);

            $.isFrozen = true;
            emit DAOFrozen(block.timestamp);
        }

        // Emit event for transparency
        emit FreezeVoteCast(voter_, weightCasted_);
    }
}
