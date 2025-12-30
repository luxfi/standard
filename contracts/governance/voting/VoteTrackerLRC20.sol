// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IVoteTracker} from "../interfaces/IVoteTracker.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title VoteTrackerLRC20
 * @author Lux Industries Inc
 * @notice Vote tracking for LRC20 token voting
 * @dev Tracks votes by address - one vote per address per proposal.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - Address-based tracking (no token IDs)
 * - Authorized caller pattern
 * - Gas-efficient storage
 *
 * @custom:security-contact security@lux.network
 */
contract VoteTrackerLRC20 is IVoteTracker, ERC165, Initializable {
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.votetracker.lrc20
     */
    struct VoteTrackerStorage {
        /// @notice Tracks whether an address has voted in a specific proposal
        mapping(uint256 proposalId => mapping(address voter => bool hasVoted)) votes;
        /// @notice Authorized callers that can record votes
        mapping(address caller => bool authorized) authorizedCallers;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant VOTE_TRACKER_STORAGE_LOCATION =
        0x7430435abb9cbac0ac3991781e3d1425d896b1f254c54102ffb46e29a11aa300;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (VoteTrackerStorage storage $) {
        assembly {
            $.slot := VOTE_TRACKER_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    modifier onlyAuthorized() {
        VoteTrackerStorage storage $ = _getStorage();
        if (!$.authorizedCallers[msg.sender]) revert UnauthorizedCaller(msg.sender);
        _;
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vote tracker
     * @param authorizedCallers_ Array of addresses authorized to record votes
     */
    function initialize(
        address[] calldata authorizedCallers_
    ) public virtual initializer {
        VoteTrackerStorage storage $ = _getStorage();

        for (uint256 i = 0; i < authorizedCallers_.length;) {
            $.authorizedCallers[authorizedCallers_[i]] = true;
            unchecked { ++i; }
        }
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function isAuthorizedCaller(address caller) public view virtual returns (bool) {
        return _getStorage().authorizedCallers[caller];
    }

    // ======================================================================
    // IVoteTracker
    // ======================================================================

    /**
     * @notice Check if address has voted for a proposal
     * @param proposalId The proposal ID
     * @param voter The voter address
     * @param voteData Ignored for LRC20
     * @return True if already voted
     */
    function hasVoted(
        uint256 proposalId,
        address voter,
        bytes calldata voteData
    ) external view virtual override returns (bool) {
        return _getStorage().votes[proposalId][voter];
    }

    /**
     * @notice Record a vote
     * @param proposalId The proposal ID
     * @param voter The voter address
     * @param voteData Ignored for LRC20
     */
    function recordVote(
        uint256 proposalId,
        address voter,
        bytes calldata voteData
    ) external virtual override onlyAuthorized {
        VoteTrackerStorage storage $ = _getStorage();

        if ($.votes[proposalId][voter]) {
            revert AlreadyVoted(proposalId, voter, voteData);
        }

        $.votes[proposalId][voter] = true;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IVoteTracker).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
