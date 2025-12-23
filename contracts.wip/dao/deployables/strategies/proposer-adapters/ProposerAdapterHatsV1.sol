// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    IProposerAdapterHatsV1
} from "../../../interfaces/dao/deployables/IProposerAdapterHatsV1.sol";
import {
    IProposerAdapterBaseV1
} from "../../../interfaces/dao/deployables/IProposerAdapterBaseV1.sol";
import {IHats} from "../../../interfaces/hats/IHats.sol";
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
 * @title ProposerAdapterHatsV1
 * @author Lux Industriesn Inc
 * @notice Implementation of proposer adapter using Hats Protocol roles for eligibility
 * @dev This contract implements IProposerAdapterHatsV1, determining proposal creation
 * eligibility based on Hats Protocol role ownership.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Non-upgradeable contract deployed per strategy
 * - Maintains whitelist of hat IDs authorized to propose
 * - Requires both: hat is whitelisted AND proposer wears it
 * - Data parameter must contain abi.encode(uint256 hatId)
 * - Checks current hat ownership (no historical snapshots)
 * - Empty whitelist means no one can propose
 *
 * @custom:security-contact security@lux.network
 */
contract ProposerAdapterHatsV1 is
    IProposerAdapterHatsV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for ProposerAdapterHatsV1 following EIP-7201
     * @dev Contains Hats contract reference and whitelist configuration
     * @custom:storage-location erc7201:DAO.ProposerAdapterHats.main
     */
    struct ProposerAdapterHatsStorage {
        /** @notice The Hats Protocol contract used for role verification */
        IHats hatsContract;
        /** @notice Array of hat IDs authorized to create proposals */
        uint256[] whitelistedHatIds;
        /** @notice Mapping for O(1) whitelist checks */
        mapping(uint256 hatId => bool isWhitelisted) hatIdIsWhitelisted;
    }

    /**
     * @dev Storage slot for ProposerAdapterHatsStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.ProposerAdapterHats.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant PROPOSER_ADAPTER_HATS_STORAGE_LOCATION =
        0xd7b60f4d6815f9154d4a3fad28e55995818cb5267ea0443225644719e6bb1900;

    /**
     * @dev Returns the storage struct for ProposerAdapterHatsV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for ProposerAdapterHatsV1
     */
    function _getProposerAdapterHatsStorage()
        internal
        pure
        returns (ProposerAdapterHatsStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := PROPOSER_ADAPTER_HATS_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IProposerAdapterHatsV1
     * @dev Stores both array and mapping for efficient access patterns.
     * Empty whitelist array is allowed but means no one can propose.
     */
    function initialize(
        address hatsContract_,
        uint256[] calldata whitelistedHatIds_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(hatsContract_, whitelistedHatIds_)
        );
        __DeploymentBlockInitializable_init();

        ProposerAdapterHatsStorage storage $ = _getProposerAdapterHatsStorage();
        $.hatsContract = IHats(hatsContract_);
        $.whitelistedHatIds = whitelistedHatIds_;
        for (uint256 i = 0; i < whitelistedHatIds_.length; ) {
            $.hatIdIsWhitelisted[whitelistedHatIds_[i]] = true;

            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // IProposerAdapterHatsV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IProposerAdapterHatsV1
     */
    function hatsContract() public view virtual override returns (address) {
        ProposerAdapterHatsStorage storage $ = _getProposerAdapterHatsStorage();
        return address($.hatsContract);
    }

    /**
     * @inheritdoc IProposerAdapterHatsV1
     */
    function whitelistedHatIds()
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        ProposerAdapterHatsStorage storage $ = _getProposerAdapterHatsStorage();
        return $.whitelistedHatIds;
    }

    /**
     * @inheritdoc IProposerAdapterHatsV1
     */
    function hatIdIsWhitelisted(
        uint256 hatId_
    ) public view virtual override returns (bool) {
        ProposerAdapterHatsStorage storage $ = _getProposerAdapterHatsStorage();
        return $.hatIdIsWhitelisted[hatId_];
    }

    // ======================================================================
    // IProposerAdapterBaseV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IProposerAdapterBaseV1
     * @dev Requires data to contain abi.encode(uint256 hatId).
     * Returns true only if both conditions are met:
     * 1. The hat ID is whitelisted in this adapter
     * 2. The proposer currently wears that hat
     */
    function isProposer(
        address proposer_,
        bytes calldata data_
    ) public view virtual override returns (bool) {
        uint256 hatId = abi.decode(data_, (uint256));

        ProposerAdapterHatsStorage storage $ = _getProposerAdapterHatsStorage();

        return
            $.hatIdIsWhitelisted[hatId] &&
            $.hatsContract.isWearerOfHat(proposer_, hatId);
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
     * @dev Supports IProposerAdapterHatsV1, IProposerAdapterBaseV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IProposerAdapterHatsV1).interfaceId ||
            interfaceId_ == type(IProposerAdapterBaseV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
