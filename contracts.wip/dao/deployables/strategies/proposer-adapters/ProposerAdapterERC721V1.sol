// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    IProposerAdapterERC721V1
} from "../../../interfaces/dao/deployables/IProposerAdapterERC721V1.sol";
import {
    IProposerAdapterBaseV1
} from "../../../interfaces/dao/deployables/IProposerAdapterBaseV1.sol";
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
 * @title ProposerAdapterERC721V1
 * @author Lux Industriesn Inc
 * @notice Implementation of proposer adapter using NFT ownership for eligibility
 * @dev This contract implements IProposerAdapterERC721V1, determining proposal creation
 * eligibility based on the number of NFTs owned from a specific collection.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Non-upgradeable contract deployed per strategy
 * - Checks current NFT balance via token.balanceOf()
 * - No historical snapshots - uses current ownership state
 * - Data parameter in isProposer() is ignored
 * - Zero threshold allows anyone to propose
 * - Works with any standard ERC721 contract
 *
 * @custom:security-contact security@lux.network
 */
contract ProposerAdapterERC721V1 is
    IProposerAdapterERC721V1,
    DeploymentBlockInitializable,
    IVersion,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for ProposerAdapterERC721V1 following EIP-7201
     * @dev Contains NFT contract reference and threshold configuration
     * @custom:storage-location erc7201:DAO.ProposerAdapterERC721.main
     */
    struct ProposerAdapterERC721Storage {
        /** @notice The ERC721 NFT contract used for ownership checks */
        IERC721 token;
        /** @notice Minimum number of NFTs required to create proposals */
        uint256 proposerThreshold;
    }

    /**
     * @dev Storage slot for ProposerAdapterERC721Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.ProposerAdapterERC721.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant PROPOSER_ADAPTER_ERC721_STORAGE_LOCATION =
        0x0b4a4f2e6b9f1f19c9af2582923f8bb9e1448a7f32ed0b86e2f369daa5840600;

    /**
     * @dev Returns the storage struct for ProposerAdapterERC721V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for ProposerAdapterERC721V1
     */
    function _getProposerAdapterERC721Storage()
        internal
        pure
        returns (ProposerAdapterERC721Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := PROPOSER_ADAPTER_ERC721_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IProposerAdapterERC721V1
     * @dev The token can be any standard ERC721 contract.
     * A threshold of 0 allows anyone to propose.
     */
    function initialize(
        address token_,
        uint256 proposerThreshold_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(token_, proposerThreshold_));
        __DeploymentBlockInitializable_init();

        ProposerAdapterERC721Storage
            storage $ = _getProposerAdapterERC721Storage();
        $.token = IERC721(token_);
        $.proposerThreshold = proposerThreshold_;
    }

    // ======================================================================
    // IProposerAdapterERC721V1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IProposerAdapterERC721V1
     */
    function token() public view virtual override returns (address) {
        ProposerAdapterERC721Storage
            storage $ = _getProposerAdapterERC721Storage();
        return address($.token);
    }

    /**
     * @inheritdoc IProposerAdapterERC721V1
     */
    function proposerThreshold()
        public
        view
        virtual
        override
        returns (uint256)
    {
        ProposerAdapterERC721Storage
            storage $ = _getProposerAdapterERC721Storage();
        return $.proposerThreshold;
    }

    // ======================================================================
    // IProposerAdapterBaseV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IProposerAdapterBaseV1
     * @dev Uses token.balanceOf() to count NFTs owned by the proposer.
     * The data parameter is ignored for ERC721 adapters.
     */
    function isProposer(
        address proposer_,
        bytes calldata
    ) public view virtual override returns (bool) {
        ProposerAdapterERC721Storage
            storage $ = _getProposerAdapterERC721Storage();
        return $.token.balanceOf(proposer_) >= $.proposerThreshold;
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
     * @dev Supports IProposerAdapterERC721V1, IProposerAdapterBaseV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IProposerAdapterERC721V1).interfaceId ||
            interfaceId_ == type(IProposerAdapterBaseV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
