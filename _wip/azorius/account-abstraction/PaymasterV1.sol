// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IPaymasterV1
} from "../../interfaces/dao/deployables/IPaymasterV1.sol";
import {
    IFunctionValidator
} from "../../interfaces/dao/services/IFunctionValidator.sol";
import {
    ILightAccountValidator
} from "../../interfaces/dao/deployables/ILightAccountValidator.sol";
import {IVersion} from "../../interfaces/dao/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/dao/IDeploymentBlock.sol";
import {
    IBasePaymaster
} from "../../interfaces/dao/deployables/IBasePaymaster.sol";
import {BasePaymaster} from "./BasePaymaster.sol";
import {LightAccountValidator} from "./LightAccountValidator.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation,
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title PaymasterV1
 * @author Lux Industriesn Inc
 * @notice Implementation of ERC-4337 paymaster for gasless transactions
 * @dev This contract implements IPaymasterV1, providing gas sponsorship
 * for Light Account operations in the DAO Protocol.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Implements UUPS upgradeable pattern with owner-restricted upgrades
 * - Inherits BasePaymaster for core paymaster functionality
 * - Inherits LightAccountValidator for Light Account validation
 * - Uses function validators for operation authorization
 *
 * Key responsibilities:
 * - Sponsor gas fees for whitelisted operations
 * - Validate operations through external validator contracts
 * - Manage per-function validation configuration
 * - Support Light Account operations for gasless UX
 *
 * Security model:
 * - Owner controls validator configuration
 * - Each function selector can have its own validator
 * - Validators determine which operations to sponsor
 * - Only valid operations receive gas sponsorship
 *
 * @custom:security-contact security@lux.network
 */
contract PaymasterV1 is
    IPaymasterV1,
    IVersion,
    BasePaymaster,
    LightAccountValidator,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for DAOPaymasterV1 following EIP-7201
     * @dev Contains validator configuration for function-level access control
     * @custom:storage-location erc7201:DAO.DAOPaymaster.main
     */
    struct DAOPaymasterStorage {
        /** @notice Maps target contract and function selector to validator address */
        mapping(address target => mapping(bytes4 selector => address validator)) functionValidators;
    }

    /**
     * @dev Storage slot for DAOPaymasterStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.DAOPaymaster.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant DAO_PAYMASTER_STORAGE_LOCATION =
        0x9864cc6d2ebb52de6c6d593dbda2be2b4542b9f136a6d2b6285312464a440f00;

    /**
     * @dev Returns the storage struct for DAOPaymasterV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for DAOPaymasterV1
     */
    function _getDAOPaymasterStorage()
        internal
        pure
        returns (DAOPaymasterStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := DAO_PAYMASTER_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IPaymasterV1
     * @dev Initializes all inherited contracts and sets up the paymaster
     * for ERC-4337 operations with Light Account support.
     */
    function initialize(
        address owner_,
        address entryPoint_,
        address lightAccountFactory_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(owner_, entryPoint_, lightAccountFactory_)
        );
        __BasePaymaster_init(owner_, IEntryPoint(entryPoint_));
        __LightAccountValidator_init(lightAccountFactory_);
        __DeploymentBlockInitializable_init();
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev Restricts upgrades to the owner
     */
    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
        // Intentionally empty - authorization logic handled by onlyOwner modifier
    }

    // ======================================================================
    // IDAOPaymasterV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IPaymasterV1
     */
    function getFunctionValidator(
        address target_,
        bytes4 selector_
    ) public view virtual override returns (address) {
        DAOPaymasterStorage storage $ = _getDAOPaymasterStorage();
        return $.functionValidators[target_][selector_];
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IPaymasterV1
     * @dev Validates that the validator implements IFunctionValidator interface
     * before setting. This ensures only compatible validators can be configured.
     */
    function setFunctionValidator(
        address target_,
        bytes4 selector_,
        address validator_
    ) public virtual override onlyOwner {
        // Check 1: Validator cannot be zero address
        if (validator_ == address(0)) revert InvalidValidator();

        // Check 2: Validator must implement IFunctionValidator interface
        if (
            !IERC165(validator_).supportsInterface(
                type(IFunctionValidator).interfaceId
            )
        ) {
            revert InvalidValidator();
        }

        // Set the validator for the target function
        DAOPaymasterStorage storage $ = _getDAOPaymasterStorage();
        $.functionValidators[target_][selector_] = validator_;

        // Emit event for transparency
        emit FunctionValidatorSet(target_, selector_, validator_);
    }

    /**
     * @inheritdoc IPaymasterV1
     */
    function removeFunctionValidator(
        address target_,
        bytes4 selector_
    ) public virtual override onlyOwner {
        DAOPaymasterStorage storage $ = _getDAOPaymasterStorage();
        $.functionValidators[target_][selector_] = address(0);

        emit FunctionValidatorRemoved(target_, selector_);
    }

    // ======================================================================
    // BasePaymaster
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc BasePaymaster
     * @dev Validates user operations by checking with the configured function validator.
     * Extracts the target contract and function selector from the user operation,
     * then delegates validation to the appropriate validator contract.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp_,
        bytes32,
        uint256
    ) internal view virtual override returns (bytes memory, uint256) {
        // Step 1: Extract operation details from the user operation
        (
            address lightAccountOwner,
            address target,
            bytes memory innerCallData
        ) = _validateUserOp(userOp_);

        // Step 2: Extract function selector from calldata
        bytes4 selector = bytes4(innerCallData);

        DAOPaymasterStorage storage $ = _getDAOPaymasterStorage();

        // Step 3: Check if function has a validator configured
        address validator = $.functionValidators[target][selector];
        if (validator == address(0)) {
            revert NoValidatorSet(target, selector);
        }

        // Step 4: Delegate validation to the configured validator
        bool isValid = IFunctionValidator(validator).validateOperation(
            userOp_.sender,
            lightAccountOwner,
            target,
            innerCallData
        );

        // Step 5: Revert if validation fails
        if (!isValid) {
            revert ValidationFailed(target, selector);
        }

        // Return empty context and validation success (0)
        return (bytes(""), 0);
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
        override(Ownable2StepUpgradeable, OwnableUpgradeable)
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
    ) internal virtual override(Ownable2StepUpgradeable, OwnableUpgradeable) {
        Ownable2StepUpgradeable._transferOwnership(newOwner_);
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
     * @dev Supports IDAOPaymasterV1, IBasePaymaster, ILightAccountValidator, IPaymaster, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IPaymasterV1).interfaceId ||
            interfaceId_ == type(IBasePaymaster).interfaceId ||
            interfaceId_ == type(ILightAccountValidator).interfaceId ||
            interfaceId_ == type(IPaymaster).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
