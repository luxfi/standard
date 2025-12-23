// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    IVotingWeightV1
} from "../../../interfaces/dao/deployables/IVotingWeightV1.sol";
import {
    IVotingWeightERC721V1
} from "../../../interfaces/dao/deployables/IVotingWeightERC721V1.sol";
import {IVersion} from "../../../interfaces/dao/deployables/IVersion.sol";
import {
    IDeploymentBlock
} from "../../../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../../InitializerEventEmitter.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title VotingWeightERC721V1
 * @author Lux Industriesn Inc
 * @notice Implementation of voting weight calculation for ERC721 tokens
 * @dev This contract implements IVotingWeightV1 for ERC721 NFTs.
 * It calculates voting weight based on NFT ownership, validating that the
 * voter owns the specified token IDs at the time of voting.
 *
 * Key features:
 * - Validates current ownership of NFTs (no snapshots)
 * - Processes token ID arrays from vote data
 * - Prevents duplicate token IDs in single vote
 * - Returns validated token IDs as processedData
 *
 * @custom:security-contact security@lux.network
 */
contract VotingWeightERC721V1 is
    IVotingWeightERC721V1,
    IVotingWeightV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for VotingWeightERC721V1 following EIP-7201
     * @dev Contains token configuration for weight calculation
     * @custom:storage-location erc7201:DAO.VotingWeightERC721.main
     */
    struct VotingWeightERC721Storage {
        /** @notice The ERC721 token used for voting weight calculation */
        IERC721 token;
        /** @notice Weight granted by each NFT */
        uint256 weightPerToken;
    }

    /**
     * @dev Storage slot for VotingWeightERC721Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.VotingWeightERC721.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant VOTING_WEIGHT_ERC721_STORAGE_LOCATION =
        0x56fbed155c21af80dffb4c0c51838be7c0e6f972361cd81ec3bba62e4e9bee00;

    /**
     * @dev Returns the storage struct for VotingWeightERC721V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for VotingWeightERC721V1
     */
    function _getVotingWeightERC721Storage()
        internal
        pure
        returns (VotingWeightERC721Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VOTING_WEIGHT_ERC721_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVotingWeightERC721V1
     */
    function initialize(
        address token_,
        uint256 weightPerToken_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(token_, weightPerToken_));
        __DeploymentBlockInitializable_init();

        VotingWeightERC721Storage storage $ = _getVotingWeightERC721Storage();
        $.token = IERC721(token_);
        $.weightPerToken = weightPerToken_;
    }

    // ======================================================================
    // IVotingWeightERC721V1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVotingWeightERC721V1
     */
    function token() public view virtual override returns (address) {
        VotingWeightERC721Storage storage $ = _getVotingWeightERC721Storage();
        return address($.token);
    }

    /**
     * @inheritdoc IVotingWeightERC721V1
     */
    function weightPerToken() public view virtual override returns (uint256) {
        VotingWeightERC721Storage storage $ = _getVotingWeightERC721Storage();
        return $.weightPerToken;
    }

    // ======================================================================
    // IVotingWeightV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVotingWeightV1
     * @dev For ERC721 tokens:
     * - Decodes token IDs from voteData_
     * - Validates current ownership of each NFT
     * - Prevents duplicate token IDs
     * - Returns total weight and validated token IDs
     * @custom:throws NoTokenIds if voteData contains no token IDs
     * @custom:throws DuplicateTokenId if a token ID appears twice
     * @custom:throws NotTokenOwner if voter doesn't own a token
     */
    function calculateWeight(
        address voter_,
        uint256 /* timestamp_ */,
        bytes calldata voteData_
    ) external view virtual override returns (uint256, bytes memory) {
        VotingWeightERC721Storage storage $ = _getVotingWeightERC721Storage();

        // Decode token IDs from vote data
        uint256[] memory tokenIds = abi.decode(voteData_, (uint256[]));

        if (tokenIds.length == 0) revert NoTokenIds();

        // Track used token IDs to prevent duplicates
        // Using a simple array check for gas efficiency with small arrays
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Check for duplicates
            for (uint256 j = 0; j < i; j++) {
                if (tokenIds[j] == tokenId) {
                    revert DuplicateTokenId(tokenId);
                }
            }

            // Validate ownership
            address owner = $.token.ownerOf(tokenId);
            if (owner != voter_) {
                revert NotTokenOwner(tokenId, owner);
            }
        }

        // Calculate total weight
        // Return validated token IDs as processed data
        return (tokenIds.length * $.weightPerToken, abi.encode(tokenIds));
    }

    /**
     * @inheritdoc IVotingWeightV1
     * @dev For ERC721 tokens, this function performs the same validation as calculateWeight
     * since NFT ownership checks don't involve banned opcodes. The function exists to
     * maintain interface compatibility and support the gasless voting flow.
     * Unlike ERC20 tokens, ERC721 ownership validation doesn't require historical lookups
     * or checkpoint iteration, so this implementation can be identical to calculateWeight
     * minus the processedData return value.
     */
    function getVotingWeightForPaymaster(
        address voter_,
        uint256 /* timestamp_ */,
        bytes calldata voteData_
    ) external view virtual override returns (uint256) {
        VotingWeightERC721Storage storage $ = _getVotingWeightERC721Storage();

        // Decode token IDs from vote data
        uint256[] memory tokenIds = abi.decode(voteData_, (uint256[]));

        // Return 0 if no tokens provided
        if (tokenIds.length == 0) {
            return 0;
        }

        // Track unique token IDs to prevent duplicates
        for (uint256 i = 0; i < tokenIds.length; ) {
            // Check current ownership
            if ($.token.ownerOf(tokenIds[i]) != voter_) {
                return 0; // Not the owner
            }

            // Check for duplicates
            for (uint256 j = i + 1; j < tokenIds.length; ) {
                if (tokenIds[i] == tokenIds[j]) {
                    return 0; // Duplicate found
                }
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Calculate total weight
        return tokenIds.length * $.weightPerToken;
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
     * @dev Supports IVotingWeightV1, IVotingWeightERC721V1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IVotingWeightERC721V1).interfaceId ||
            interfaceId_ == type(IVotingWeightV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
