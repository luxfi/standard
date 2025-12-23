// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IProposerAdapterERC20V1
} from "../../../interfaces/dao/deployables/IProposerAdapterERC20V1.sol";
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
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title ProposerAdapterERC20V1
 * @author Lux Industriesn Inc
 * @notice Implementation of proposer adapter using ERC20 voting power for eligibility
 * @dev This contract implements IProposerAdapterERC20V1, determining proposal creation
 * eligibility based on delegated voting power (not token balance).
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Non-upgradeable contract deployed per strategy
 * - Checks current voting power via token.getVotes()
 * - Requires delegation (users must delegate to themselves to use their tokens)
 * - No historical snapshots - uses current state
 * - Data parameter in isProposer() is ignored
 * - Zero threshold allows anyone to propose
 *
 * @custom:security-contact security@lux.network
 */
contract ProposerAdapterERC20V1 is
    IProposerAdapterERC20V1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for ProposerAdapterERC20V1 following EIP-7201
     * @dev Contains token reference and threshold configuration
     * @custom:storage-location erc7201:DAO.ProposerAdapterERC20.main
     */
    struct ProposerAdapterERC20Storage {
        /** @notice The IVotes token used for voting power checks */
        IVotes token;
        /** @notice Minimum voting power required to create proposals */
        uint256 proposerThreshold;
    }

    /**
     * @dev Storage slot for ProposerAdapterERC20Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.ProposerAdapterERC20.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant PROPOSER_ADAPTER_ERC20_STORAGE_LOCATION =
        0xd0ff3bfab69583661d8803345254b7701c2125007ad7e3ef64473e569aca5400;

    /**
     * @dev Returns the storage struct for ProposerAdapterERC20V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for ProposerAdapterERC20V1
     */
    function _getProposerAdapterERC20Storage()
        internal
        pure
        returns (ProposerAdapterERC20Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := PROPOSER_ADAPTER_ERC20_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IProposerAdapterERC20V1
     * @dev The token must implement IVotes interface for voting power queries.
     * A threshold of 0 allows anyone to propose.
     */
    function initialize(
        address token_,
        uint256 proposerThreshold_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(token_, proposerThreshold_));
        __DeploymentBlockInitializable_init();

        ProposerAdapterERC20Storage
            storage $ = _getProposerAdapterERC20Storage();
        $.token = IVotes(token_);
        $.proposerThreshold = proposerThreshold_;
    }

    // ======================================================================
    // IProposerAdapterERC20V1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IProposerAdapterERC20V1
     */
    function token() public view virtual override returns (address) {
        ProposerAdapterERC20Storage
            storage $ = _getProposerAdapterERC20Storage();
        return address($.token);
    }

    /**
     * @inheritdoc IProposerAdapterERC20V1
     */
    function proposerThreshold()
        public
        view
        virtual
        override
        returns (uint256)
    {
        ProposerAdapterERC20Storage
            storage $ = _getProposerAdapterERC20Storage();
        return $.proposerThreshold;
    }

    // ======================================================================
    // IProposerAdapterBaseV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IProposerAdapterBaseV1
     * @dev Uses token.getVotes() which returns the current voting power from delegation.
     * Note: This is delegated voting power, not token balance. Users must delegate to
     * themselves or have others delegate to them to gain voting power.
     * The data parameter is ignored for ERC20 adapters.
     */
    function isProposer(
        address proposer_,
        bytes calldata
    ) public view virtual override returns (bool) {
        ProposerAdapterERC20Storage
            storage $ = _getProposerAdapterERC20Storage();
        return $.token.getVotes(proposer_) >= $.proposerThreshold;
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
     * @dev Supports IProposerAdapterERC20V1, IProposerAdapterBaseV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IProposerAdapterERC20V1).interfaceId ||
            interfaceId_ == type(IProposerAdapterBaseV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
