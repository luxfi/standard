// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    IVoteTrackerV1
} from "../../../interfaces/dao/deployables/IVoteTrackerV1.sol";
import {IVersion} from "../../../interfaces/dao/deployables/IVersion.sol";
import {
    IDeploymentBlock
} from "../../../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../../InitializerEventEmitter.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title VoteTrackerERC20V1
 * @author Lux Industriesn Inc
 * @notice Implementation of vote tracking for ERC20 tokens
 * @dev This contract implements IVoteTrackerV1 for ERC20-based voting.
 * It tracks votes by address, allowing one vote per address per context.
 *
 * Key features:
 * - Simple address-based tracking
 * - One vote per address per voting context
 * - Ignores voteData parameter (no token IDs to track)
 * - Gas-efficient storage pattern
 *
 * @custom:security-contact security@lux.network
 */
contract VoteTrackerERC20V1 is
    IVoteTrackerV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for VoteTrackerERC20V1 following EIP-7201
     * @dev Contains mappings for tracking votes by context and voter
     * @custom:storage-location erc7201:DAO.VoteTrackerERC20.main
     */
    struct VoteTrackerERC20Storage {
        /** @notice Tracks whether an address has voted in a specific context */
        mapping(uint256 contextId => mapping(address voter => bool hasVoted)) votes;
        /** @notice Mapping of authorized caller contracts that can record votes */
        mapping(address caller => bool isAuthorized) authorizedCallers;
    }

    /**
     * @dev Storage slot for VoteTrackerERC20Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.VoteTrackerERC20.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant VOTE_TRACKER_ERC20_STORAGE_LOCATION =
        0x7430435abb9cbac0ac3991781e3d1425d896b1f254c54102ffb46e29a11aa300;

    /**
     * @dev Returns the storage struct for VoteTrackerERC20V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for VoteTrackerERC20V1
     */
    function _getVoteTrackerERC20Storage()
        internal
        pure
        returns (VoteTrackerERC20Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VOTE_TRACKER_ERC20_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    /**
     * @notice Restricts function access to authorized strategy contracts
     * @dev This modifier ensures only authorized contracts can record votes.
     * The authorization check is implemented in the internal function to allow
     * for flexible authorization patterns (e.g., multiple strategies, freeze voting contracts)
     */
    modifier onlyAuthorizedCaller() virtual {
        _checkAuthorization(msg.sender);
        _;
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVoteTrackerV1
     */
    function initialize(
        address[] memory authorizedCallers_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(authorizedCallers_));
        __DeploymentBlockInitializable_init();

        VoteTrackerERC20Storage storage $ = _getVoteTrackerERC20Storage();
        for (uint256 i = 0; i < authorizedCallers_.length; ) {
            $.authorizedCallers[authorizedCallers_[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // IVoteTrackerV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVoteTrackerV1
     * @dev For ERC20 tokens:
     * - Ignores voteData_ parameter (no token IDs needed)
     * - Simply checks if the voter address has voted for this context
     */
    function hasVoted(
        uint256 contextId_,
        address voter_,
        bytes calldata /* voteData_ */
    ) external view virtual override returns (bool) {
        VoteTrackerERC20Storage storage $ = _getVoteTrackerERC20Storage();
        return $.votes[contextId_][voter_];
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IVoteTrackerV1
     * @dev For ERC20 tokens:
     * - Ignores voteData_ parameter (no token IDs needed)
     * - Records that the voter address has voted
     * - Reverts if already voted
     * @custom:throws AlreadyVoted if the address has already voted in this context
     */
    function recordVote(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external virtual override onlyAuthorizedCaller {
        VoteTrackerERC20Storage storage $ = _getVoteTrackerERC20Storage();

        if ($.votes[contextId_][voter_]) {
            revert AlreadyVoted(contextId_, voter_, voteData_);
        }

        $.votes[contextId_][voter_] = true;
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
     * @dev Supports IVoteTrackerV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IVoteTrackerV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Checks if the caller is authorized to record votes
     * @dev Internal function used by the onlyAuthorizedCaller modifier
     * @param caller_ The address to check for authorization
     * @custom:throws UnauthorizedCaller if the caller is not authorized
     */
    function _checkAuthorization(address caller_) internal view virtual {
        VoteTrackerERC20Storage storage $ = _getVoteTrackerERC20Storage();
        if (!$.authorizedCallers[caller_]) {
            revert UnauthorizedCaller(caller_);
        }
    }
}
