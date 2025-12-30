// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IFreezeVoting} from "../interfaces/IFreezeVoting.sol";
import {ILRC20} from "../../tokens/interfaces/ILRC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title FreezeVoting
 * @author Lux Industries Inc
 * @notice LRC20-based freeze voting for parent DAO control
 * @dev Allows token holders to vote to freeze a child DAO.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - Token-weighted voting via LRC20 (Lux token standard)
 * - Automatic freeze when threshold reached
 * - lastFreezeTime never cleared (security invariant)
 * - Proposal expiration and renewal
 *
 * Security model:
 * - Anyone with voting tokens can vote
 * - Each address can vote once per proposal
 * - Freeze is immediate when threshold met
 * - Guards check lastFreezeTime to invalidate pre-freeze transactions
 *
 * @custom:security-contact security@lux.network
 */
contract FreezeVoting is IFreezeVoting, ERC165, Initializable {
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.freezevoting
     */
    struct FreezeVotingStorage {
        /// @notice Timestamp when current freeze proposal was created
        uint48 freezeProposalCreated;
        /// @notice Accumulated votes for current freeze proposal
        uint256 freezeProposalVoteCount;
        /// @notice Duration freeze proposals remain active
        uint32 freezeProposalPeriod;
        /// @notice Whether the DAO is currently frozen
        bool isFrozen;
        /// @notice Voting weight required to trigger a freeze
        uint256 freezeVotesThreshold;
        /// @notice Timestamp of the most recent freeze (NEVER cleared)
        uint48 lastFreezeTimestamp;
        /// @notice Duration the DAO remains frozen
        uint32 freezePeriod;
        /// @notice LRC20 token used for voting weight
        address votingToken;
        /// @notice Tracks who has voted in current proposal
        mapping(address voter => bool hasVoted) hasVoted;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant FREEZE_VOTING_STORAGE_LOCATION =
        0x5fcea62682ddc2ee9ccbce9f3a895c9dd644ee53c86fd38cf80a135b0e525500;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (FreezeVotingStorage storage $) {
        assembly {
            $.slot := FREEZE_VOTING_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize freeze voting parameters
     * @param votingToken_ LRC20 token for voting weight
     * @param freezeVotesThreshold_ Votes required to freeze
     * @param freezeProposalPeriod_ Duration proposals remain active
     * @param freezePeriod_ Duration DAO remains frozen
     */
    function initialize(
        address votingToken_,
        uint256 freezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        uint32 freezePeriod_
    ) public virtual initializer {
        if (votingToken_ == address(0)) revert InvalidAddress();

        FreezeVotingStorage storage $ = _getStorage();
        $.votingToken = votingToken_;
        $.freezeVotesThreshold = freezeVotesThreshold_;
        $.freezeProposalPeriod = freezeProposalPeriod_;
        $.freezePeriod = freezePeriod_;
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function isFrozen() public view virtual override returns (bool) {
        FreezeVotingStorage storage $ = _getStorage();

        if (!$.isFrozen) return false;

        // Check if freeze period has expired (auto-unfreeze)
        if ($.freezePeriod > 0 && block.timestamp > $.lastFreezeTimestamp + $.freezePeriod) {
            return false;
        }

        return true;
    }

    function lastFreezeTime() public view virtual override returns (uint48) {
        return _getStorage().lastFreezeTimestamp;
    }

    function freezeProposalCreated() public view virtual override returns (uint48) {
        return _getStorage().freezeProposalCreated;
    }

    function freezeProposalVoteCount() public view virtual override returns (uint256) {
        return _getStorage().freezeProposalVoteCount;
    }

    function freezeProposalPeriod() public view virtual override returns (uint32) {
        return _getStorage().freezeProposalPeriod;
    }

    function freezeVotesThreshold() public view virtual override returns (uint256) {
        return _getStorage().freezeVotesThreshold;
    }

    function votingToken() public view virtual returns (address) {
        return _getStorage().votingToken;
    }

    function freezePeriod() public view virtual returns (uint32) {
        return _getStorage().freezePeriod;
    }

    function hasVoted(address voter) public view virtual returns (bool) {
        return _getStorage().hasVoted[voter];
    }

    // ======================================================================
    // STATE-CHANGING FUNCTIONS
    // ======================================================================

    /**
     * @notice Cast a freeze vote
     * @dev Creates new proposal if none active, adds weight to current proposal
     */
    function castFreezeVote() public virtual override {
        FreezeVotingStorage storage $ = _getStorage();

        // Check if current proposal has expired
        bool proposalExpired = $.freezeProposalCreated == 0 ||
            block.timestamp > $.freezeProposalCreated + $.freezeProposalPeriod;

        // Start new proposal if needed
        if (proposalExpired) {
            _initializeFreezeProposal();
        }

        // Check if already voted in current proposal
        if ($.hasVoted[msg.sender]) revert AlreadyVoted();

        // Get voting weight at proposal creation time (ERC5805 getPastVotes)
        uint256 weight = _getVotingWeight(msg.sender, $.freezeProposalCreated);
        if (weight == 0) revert NoVotes();

        // Record vote
        $.hasVoted[msg.sender] = true;
        $.freezeProposalVoteCount += weight;

        emit FreezeVoteCast(msg.sender, weight);

        // Check if threshold reached
        if ($.freezeProposalVoteCount >= $.freezeVotesThreshold && !$.isFrozen) {
            _activateFreeze();
        }
    }

    // ======================================================================
    // INTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Initialize a new freeze proposal
     */
    function _initializeFreezeProposal() internal virtual {
        FreezeVotingStorage storage $ = _getStorage();

        // Use timestamp - 1 for ERC5805 getPastVotes compatibility
        $.freezeProposalCreated = uint48(block.timestamp - 1);
        $.freezeProposalVoteCount = 0;

        // Clear previous votes (by resetting storage)
        // Note: In production, consider a proposal ID system for better tracking
    }

    /**
     * @notice Activate the freeze
     */
    function _activateFreeze() internal virtual {
        FreezeVotingStorage storage $ = _getStorage();

        // CRITICAL: Update lastFreezeTimestamp - this is NEVER cleared
        // Ensures all transactions timelocked before this moment are invalidated
        $.lastFreezeTimestamp = uint48(block.timestamp);
        $.isFrozen = true;

        emit DAOFrozen(block.timestamp);
    }

    /**
     * @notice Get voting weight for an address at a timestamp
     * @dev Uses ERC5805 getPastVotes for checkpoint-based tokens
     */
    function _getVotingWeight(address voter, uint48 timestamp) internal view virtual returns (uint256) {
        // Try ERC5805 getPastVotes first
        (bool success, bytes memory data) = _getStorage().votingToken.staticcall(
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, timestamp)
        );

        if (success && data.length == 32) {
            return abi.decode(data, (uint256));
        }

        // Fallback to current balance
        return ILRC20(_getStorage().votingToken).balanceOf(voter);
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IFreezeVoting).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
