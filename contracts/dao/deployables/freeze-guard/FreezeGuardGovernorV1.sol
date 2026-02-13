// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {
    IFreezeGuardGovernorV1
} from "../../interfaces/deployables/IFreezeGuardGovernorV1.sol";
import {IFreezable} from "../../interfaces/deployables/IFreezable.sol";
import {
    IFreezeGuardBaseV1
} from "../../interfaces/deployables/IFreezeGuardBaseV1.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {Enum} from "@gnosis.pm/safe-contracts/interfaces/Enum.sol";
import {IGuard} from "../../interfaces/IGuard.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @title FreezeGuardGovernorV1
 * @author Lux Industriesn Inc
 * @notice Implementation of freeze guard for Governor-based child DAOs
 * @dev This contract implements IFreezeGuardGovernorV1, providing transaction blocking
 * functionality when a child DAO is frozen by its parent DAO.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Implements UUPS upgradeable pattern with owner-restricted upgrades
 * - Attached as a guard to Governor module (not directly to Safe)
 * - Checks freeze status before every transaction execution
 * - Owner can update freeze voting contract reference
 * - No post-execution checks needed (empty checkAfterExecution)
 *
 * Security model:
 * - Only reads freeze status, doesn't control freeze voting
 * - Blocks ALL transactions when frozen (no exceptions)
 * - Owner is typically the child DAO itself for self-governance
 *
 * @custom:security-contact security@lux.network
 */
contract FreezeGuardGovernorV1 is
    IFreezeGuardGovernorV1,
    IVersion,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for FreezeGuardGovernorV1 following EIP-7201
     * @dev Contains reference to the freeze voting contract
     * @custom:storage-location erc7201:DAO.FreezeGuardGovernor.main
     */
    struct FreezeGuardGovernorStorage {
        /** @notice The Freezable contract that determines if DAO is frozen */
        IFreezable freezable;
    }

    /**
     * @dev Storage slot for FreezeGuardGovernorStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.FreezeGuardGovernor.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant FREEZE_GUARD_GOVERNOR_STORAGE_LOCATION =
        0x42f8f7e17893446d49739bff9f1513ff5cdb28566127f8e28b562c45b4b30f00;

    /**
     * @dev Returns the storage struct for FreezeGuardGovernorV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for FreezeGuardGovernorV1
     */
    function _getFreezeGuardGovernorStorage()
        internal
        pure
        returns (FreezeGuardGovernorStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := FREEZE_GUARD_GOVERNOR_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IFreezeGuardGovernorV1
     * @dev Initializes all inherited contracts and sets the freeze voting reference.
     * The owner is typically the child DAO's Safe for self-governance.
     */
    function initialize(
        address owner_,
        address freezeVoting_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(owner_, freezeVoting_));
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __DeploymentBlockInitializable_init();

        FreezeGuardGovernorStorage storage $ = _getFreezeGuardGovernorStorage();
        $.freezable = IFreezable(freezeVoting_);
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev Restricts upgrades to the owner (typically the parent DAO)
     */
    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
        // Intentionally empty - authorization logic handled by onlyOwner modifier
    }

    // ======================================================================
    // IFreezeGuardBaseV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IFreezeGuardBaseV1
     */
    function freezable() public view virtual override returns (address) {
        FreezeGuardGovernorStorage storage $ = _getFreezeGuardGovernorStorage();
        return address($.freezable);
    }

    // ======================================================================
    // IGuard
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IGuard
     * @dev Called before transaction execution. Reverts if the DAO is frozen.
     * All parameters are ignored - the only check is freeze status.
     * This ensures no transactions can be executed while the DAO is frozen.
     */
    function checkTransaction(
        address,
        uint256,
        bytes memory,
        Enum.Operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) public view virtual override {
        FreezeGuardGovernorStorage storage $ = _getFreezeGuardGovernorStorage();

        // Simple check: if frozen, block ALL transactions
        if ($.freezable.isFrozen()) revert DAOFrozen();
    }

    /**
     * @inheritdoc IGuard
     * @dev No post-execution checks needed. This guard only prevents execution when frozen.
     */
    function checkAfterExecution(bytes32, bool) public view virtual override {
        // solhint-disable-previous-line no-empty-blocks
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
     * @dev Supports IFreezeGuardGovernorV1, IFreezeGuardBaseV1, IGuard, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IFreezeGuardGovernorV1).interfaceId ||
            interfaceId_ == type(IFreezeGuardBaseV1).interfaceId ||
            interfaceId_ == type(IGuard).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
