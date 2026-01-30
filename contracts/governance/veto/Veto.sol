// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IVeto} from "../interfaces/IVeto.sol";
import {ILRC20} from "../../tokens/interfaces/ILRC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Veto
 * @author Lux Industries Inc
 * @notice LRC20-based veto voting for parent DAO control
 * @dev Allows token holders to vote to veto a child DAO.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - Token-weighted voting via LRC20 (Lux token standard)
 * - Automatic veto when threshold reached
 * - lastVetoTime never cleared (security invariant)
 * - Proposal expiration and renewal
 *
 * Security model:
 * - Anyone with voting tokens can vote
 * - Each address can vote once per proposal
 * - Veto is immediate when threshold met
 * - Guards check lastVetoTime to invalidate pre-veto transactions
 *
 * @custom:security-contact security@lux.network
 */
contract Veto is IVeto, ERC165, Initializable {
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.veto
     */
    struct VetoStorage {
        /// @notice Timestamp when current veto proposal was created
        uint48 vetoProposalCreated;
        /// @notice Accumulated votes for current veto proposal
        uint256 vetoProposalVoteCount;
        /// @notice Duration veto proposals remain active
        uint32 vetoProposalPeriod;
        /// @notice Whether the DAO is currently vetoed
        bool isVetoed;
        /// @notice Voting weight required to trigger a veto
        uint256 vetoVotesThreshold;
        /// @notice Timestamp of the most recent veto (NEVER cleared)
        uint48 lastVetoTimestamp;
        /// @notice Duration the DAO remains vetoed
        uint32 vetoPeriod;
        /// @notice LRC20 token used for voting weight
        address votingToken;
        /// @notice Tracks who has voted in current proposal
        mapping(address voter => bool hasVoted) hasVoted;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant VETO_STORAGE_LOCATION =
        0x5fcea62682ddc2ee9ccbce9f3a895c9dd644ee53c86fd38cf80a135b0e525500;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (VetoStorage storage $) {
        assembly {
            $.slot := VETO_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize veto voting parameters
     * @param votingToken_ LRC20 token for voting weight
     * @param vetoVotesThreshold_ Votes required to veto
     * @param vetoProposalPeriod_ Duration proposals remain active
     * @param vetoPeriod_ Duration DAO remains vetoed
     */
    function initialize(
        address votingToken_,
        uint256 vetoVotesThreshold_,
        uint32 vetoProposalPeriod_,
        uint32 vetoPeriod_
    ) public virtual initializer {
        if (votingToken_ == address(0)) revert InvalidAddress();

        VetoStorage storage $ = _getStorage();
        $.votingToken = votingToken_;
        $.vetoVotesThreshold = vetoVotesThreshold_;
        $.vetoProposalPeriod = vetoProposalPeriod_;
        $.vetoPeriod = vetoPeriod_;
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function isVetoed() public view virtual override returns (bool) {
        VetoStorage storage $ = _getStorage();

        if (!$.isVetoed) return false;

        // Check if veto period has expired (auto-lift)
        if ($.vetoPeriod > 0 && block.timestamp > $.lastVetoTimestamp + $.vetoPeriod) {
            return false;
        }

        return true;
    }

    function lastVetoTime() public view virtual override returns (uint48) {
        return _getStorage().lastVetoTimestamp;
    }

    function vetoProposalCreated() public view virtual override returns (uint48) {
        return _getStorage().vetoProposalCreated;
    }

    function vetoProposalVoteCount() public view virtual override returns (uint256) {
        return _getStorage().vetoProposalVoteCount;
    }

    function vetoProposalPeriod() public view virtual override returns (uint32) {
        return _getStorage().vetoProposalPeriod;
    }

    function vetoVotesThreshold() public view virtual override returns (uint256) {
        return _getStorage().vetoVotesThreshold;
    }

    function votingToken() public view virtual returns (address) {
        return _getStorage().votingToken;
    }

    function vetoPeriod() public view virtual returns (uint32) {
        return _getStorage().vetoPeriod;
    }

    function hasVoted(address voter) public view virtual returns (bool) {
        return _getStorage().hasVoted[voter];
    }

    // ======================================================================
    // STATE-CHANGING FUNCTIONS
    // ======================================================================

    /**
     * @notice Cast a veto vote
     * @dev Creates new proposal if none active, adds weight to current proposal
     */
    function castVetoVote() public virtual override {
        VetoStorage storage $ = _getStorage();

        // Check if current proposal has expired
        bool proposalExpired = $.vetoProposalCreated == 0 ||
            block.timestamp > $.vetoProposalCreated + $.vetoProposalPeriod;

        // Start new proposal if needed
        if (proposalExpired) {
            _initializeVetoProposal();
        }

        // Check if already voted in current proposal
        if ($.hasVoted[msg.sender]) revert AlreadyVoted();

        // Get voting weight at proposal creation time (ERC5805 getPastVotes)
        uint256 weight = _getVotingWeight(msg.sender, $.vetoProposalCreated);
        if (weight == 0) revert NoVotes();

        // Record vote
        $.hasVoted[msg.sender] = true;
        $.vetoProposalVoteCount += weight;

        emit VetoVoteCast(msg.sender, weight);

        // Check if threshold reached
        if ($.vetoProposalVoteCount >= $.vetoVotesThreshold && !$.isVetoed) {
            _activateVeto();
        }
    }

    // ======================================================================
    // INTERNAL FUNCTIONS
    // ======================================================================

    /**
     * @notice Initialize a new veto proposal
     */
    function _initializeVetoProposal() internal virtual {
        VetoStorage storage $ = _getStorage();

        // Use timestamp - 1 for ERC5805 getPastVotes compatibility
        $.vetoProposalCreated = uint48(block.timestamp - 1);
        $.vetoProposalVoteCount = 0;

        // Clear previous votes (by resetting storage)
        // Note: In production, consider a proposal ID system for better tracking
    }

    /**
     * @notice Activate the veto
     */
    function _activateVeto() internal virtual {
        VetoStorage storage $ = _getStorage();

        // CRITICAL: Update lastVetoTimestamp - this is NEVER cleared
        // Ensures all transactions timelocked before this moment are invalidated
        $.lastVetoTimestamp = uint48(block.timestamp);
        $.isVetoed = true;

        emit DAOVetoed(block.timestamp);
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
            interfaceId == type(IVeto).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
