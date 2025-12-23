// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IModuleFractalV1
} from "../../interfaces/dao/deployables/IModuleFractalV1.sol";
import {IVersion} from "../../interfaces/dao/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/dao/IDeploymentBlock.sol";
import {Transaction} from "../../interfaces/dao/Module.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {GuardableModule} from "../../base/GuardableModule.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title ModuleFractalV1
 * @author Lux Industriesn Inc
 * @notice Implementation of the Fractal execution module for parent-child DAO relationships
 * @dev This contract implements IModuleFractalV1, providing direct execution capabilities
 * for parent DAOs to control child DAOs.
 *
 * Implementation details:
 * - Minimal contract focused solely on execution functionality
 * - No internal state beyond ownership and Zodiac module configuration
 * - Implements UUPS (Universal Upgradeable Proxy Standard) pattern
 * - Upgrades are restricted to the parent DAO (owner)
 * - Storage layout must be preserved in future implementations
 * - Inherits from GuardableModule for Zodiac pattern integration
 * - Uses Ownable2Step for secure ownership transfers
 *
 * @custom:security-contact security@lux.network
 */
contract ModuleFractalV1 is
    IModuleFractalV1,
    IVersion,
    GuardableModule,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ERC165
{
    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IModuleFractalV1
     */
    function initialize(
        address owner_,
        address avatar_,
        address target_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(owner_, avatar_, target_));
        __UUPSUpgradeable_init();
        __Ownable_init(owner_);
        __DeploymentBlockInitializable_init();

        avatar = avatar_;
        target = target_;
        emit AvatarSet(address(0), avatar_);
        emit TargetSet(address(0), target_);
    }

    /**
     * @notice Alternative initializer following Zodiac module pattern
     * @dev Decodes packed initialization parameters and calls initialize
     * @param initializeParams_ ABI encoded parameters (owner, avatar, target)
     */
    function setUp(
        bytes memory initializeParams_
    ) public virtual override initializer {
        (address owner_, address avatar_, address target_) = abi.decode(
            initializeParams_,
            (address, address, address)
        );
        initialize(owner_, avatar_, target_);
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev Restricted to parent DAO (owner) for security
     */
    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
        // Intentionally empty - authorization logic handled by onlyOwner modifier
    }

    // ======================================================================
    // IModuleFractalV1
    // ======================================================================

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IModuleFractalV1
     * @dev Executes through the Zodiac module pattern's exec function
     */
    function execTx(
        Transaction calldata transaction_
    ) public virtual override onlyOwner {
        if (
            !exec(
                transaction_.to,
                transaction_.value,
                transaction_.data,
                transaction_.operation
            )
        ) revert TxFailed();
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
    // Ownable2StepUpgradeable
    // ======================================================================

    // --- State-Changing Functions ---

    /**
     * @inheritdoc Ownable2StepUpgradeable
     * @dev Overrides both Ownable2StepUpgradeable and OwnableUpgradeable to use
     * the two-step ownership transfer process
     */
    function transferOwnership(
        address newOwner_
    )
        public
        virtual
        override(Ownable2StepUpgradeable)
        onlyOwner
    {
        Ownable2StepUpgradeable.transferOwnership(newOwner_);
    }

    // --- Internal Functions ---

    /**
     * @inheritdoc Ownable2StepUpgradeable
     * @dev Overrides both Ownable2StepUpgradeable and OwnableUpgradeable to use
     * the two-step ownership transfer process
     */
    function _transferOwnership(
        address newOwner_
    ) internal virtual override(Ownable2StepUpgradeable) {
        Ownable2StepUpgradeable._transferOwnership(newOwner_);
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports IModuleFractalV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IModuleFractalV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
