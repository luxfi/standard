// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

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
 * @title VoteTrackerERC721V1
 * @author Lux Industriesn Inc
 * @notice Implementation of vote tracking for ERC721 tokens
 * @dev This contract implements IVoteTrackerV1 for ERC721-based voting.
 * It tracks votes by token ID, preventing reuse of specific NFTs.
 *
 * Key features:
 * - Tracks specific NFT token IDs used in voting
 * - Prevents double-voting with same NFT
 * - Processes token ID arrays from vote data
 * - Allows same address to vote with different NFTs
 *
 * @custom:security-contact security@lux.network
 */
contract VoteTrackerERC721V1 is
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
     * @notice Main storage struct for VoteTrackerERC721V1 following EIP-7201
     * @dev Contains mappings for tracking token usage by context
     * @custom:storage-location erc7201:DAO.VoteTrackerERC721.main
     */
    struct VoteTrackerERC721Storage {
        /** @notice Tracks whether a token ID has been used in a specific context */
        mapping(uint256 contextId => mapping(uint256 tokenId => bool hasBeenUsed)) usedTokens;
        /** @notice Mapping of authorized caller contracts that can record votes */
        mapping(address caller => bool isAuthorized) authorizedCallers;
    }

    /**
     * @dev Storage slot for VoteTrackerERC721Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.VoteTrackerERC721.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant VOTE_TRACKER_ERC721_STORAGE_LOCATION =
        0x0aacbe25dc18db2711ceff752e73932ab7ea9e516d9a4adc492e5ad5d59d6100;

    /**
     * @dev Returns the storage struct for VoteTrackerERC721V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for VoteTrackerERC721V1
     */
    function _getVoteTrackerERC721Storage()
        internal
        pure
        returns (VoteTrackerERC721Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VOTE_TRACKER_ERC721_STORAGE_LOCATION
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

        VoteTrackerERC721Storage storage $ = _getVoteTrackerERC721Storage();
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
     * @dev For ERC721 tokens:
     * - Decodes token IDs from voteData_
     * - Checks if any of the token IDs have been used
     * - Returns true if ANY token has been used (partial voting not allowed)
     */
    function hasVoted(
        uint256 contextId_,
        address /* voter_ */,
        bytes calldata voteData_
    ) external view virtual override returns (bool) {
        VoteTrackerERC721Storage storage $ = _getVoteTrackerERC721Storage();

        // Decode token IDs from vote data
        uint256[] memory tokenIds = decodeVoteData(voteData_);

        // Check if any token has been used
        for (uint256 i = 0; i < tokenIds.length; ) {
            if ($.usedTokens[contextId_][tokenIds[i]]) {
                return true;
            }
            unchecked {
                ++i;
            }
        }

        return false;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IVoteTrackerV1
     * @dev For ERC721 tokens:
     * - Decodes token IDs from voteData_
     * - Marks each token ID as used
     * - Reverts if any token has already been used
     * @custom:throws AlreadyVoted if any token ID has been used
     */
    function recordVote(
        uint256 contextId_,
        address voter_,
        bytes calldata voteData_
    ) external virtual override onlyAuthorizedCaller {
        VoteTrackerERC721Storage storage $ = _getVoteTrackerERC721Storage();

        // Decode token IDs from vote data
        uint256[] memory tokenIds = decodeVoteData(voteData_);

        // Check and mark each token ID
        for (uint256 i = 0; i < tokenIds.length; ) {
            uint256 tokenId = tokenIds[i];

            if ($.usedTokens[contextId_][tokenId]) {
                revert AlreadyVoted(contextId_, voter_, voteData_);
            }

            $.usedTokens[contextId_][tokenId] = true;

            unchecked {
                ++i;
            }
        }
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
     * @notice Decodes vote data into token IDs
     * @dev Internal helper to decode the encoded token ID array
     * @param voteData_ The encoded token ID array
     * @return tokenIds The decoded array of token IDs
     */
    function decodeVoteData(
        bytes calldata voteData_
    ) internal pure virtual returns (uint256[] memory) {
        return abi.decode(voteData_, (uint256[]));
    }

    /**
     * @notice Checks if the caller is authorized to record votes
     * @dev Internal function used by the onlyAuthorizedCaller modifier
     * @param caller_ The address to check for authorization
     * @custom:throws UnauthorizedCaller if the caller is not authorized
     */
    function _checkAuthorization(address caller_) internal view virtual {
        VoteTrackerERC721Storage storage $ = _getVoteTrackerERC721Storage();
        if (!$.authorizedCallers[caller_]) {
            revert UnauthorizedCaller(caller_);
        }
    }
}
