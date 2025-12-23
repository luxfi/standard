// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {
    IBasePaymaster
} from "../../interfaces/dao/deployables/IBasePaymaster.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IPaymaster
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    UserOperationLib
} from "@account-abstraction/contracts/core/UserOperationLib.sol";

/**
 * @title BasePaymaster
 * @author Lux Industriesn Inc
 * @notice Abstract base contract for ERC-4337 paymaster implementations
 * @dev This abstract contract provides common functionality for paymasters,
 * including entry point validation, staking, and deposit management.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Provides helper methods for staking and deposits
 * - Validates that postOp is called only by the entryPoint
 * - Must be extended by concrete paymaster contracts
 *
 * @custom:security-contact security@lux.network
 */
abstract contract BasePaymaster is
    IBasePaymaster,
    IPaymaster,
    OwnableUpgradeable
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for BasePaymaster following EIP-7201
     * @dev Contains the entry point reference for validation
     * @custom:storage-location erc7201:DAO.BasePaymaster.main
     */
    struct BasePaymasterStorage {
        /** @notice The ERC-4337 entry point contract for operation validation */
        IEntryPoint entryPoint;
    }

    /**
     * @dev Storage slot for BasePaymasterStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.BasePaymaster.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant BASE_PAYMASTER_STORAGE_LOCATION =
        0xad46a2c487d466a30553d8946911648c5925537fb9ab436a7edd0606d8258100;

    /**
     * @dev Returns the storage struct for BasePaymaster
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for BasePaymaster
     */
    function _getBasePaymasterStorage()
        internal
        pure
        virtual
        returns (BasePaymasterStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := BASE_PAYMASTER_STORAGE_LOCATION
        }
    }

    /** @notice Gas offset for paymaster validation operations as defined in UserOperationLib */
    uint256 internal constant PAYMASTER_VALIDATION_GAS_OFFSET =
        UserOperationLib.PAYMASTER_VALIDATION_GAS_OFFSET;

    /** @notice Gas offset for paymaster post-operation handling as defined in UserOperationLib */
    uint256 internal constant PAYMASTER_POSTOP_GAS_OFFSET =
        UserOperationLib.PAYMASTER_POSTOP_GAS_OFFSET;

    /** @notice Data offset for paymaster-specific data in user operations as defined in UserOperationLib */
    uint256 internal constant PAYMASTER_DATA_OFFSET =
        UserOperationLib.PAYMASTER_DATA_OFFSET;

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the BasePaymaster contract
     * @dev Called by inheriting contracts during initialization.
     * Sets up ownership and validates the EntryPoint interface.
     * @param _owner The address that will own this paymaster
     * @param _entryPoint The ERC-4337 EntryPoint contract address
     */
    function __BasePaymaster_init(
        // solhint-disable-previous-line func-name-mixedcase
        address _owner,
        IEntryPoint _entryPoint
    ) internal onlyInitializing {
        __Ownable_init(_owner);
        _validateEntryPointInterface(_entryPoint);

        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        $.entryPoint = _entryPoint;
    }

    // ======================================================================
    // IPaymaster
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IBasePaymaster
     */
    function entryPoint() public view virtual override returns (IEntryPoint) {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        return $.entryPoint;
    }

    /**
     * @inheritdoc IBasePaymaster
     */
    function getDeposit() public view virtual override returns (uint256) {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        return $.entryPoint.balanceOf(address(this));
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IPaymaster
     */
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp_,
        bytes32 userOpHash_,
        uint256 maxCost_
    ) public virtual override returns (bytes memory, uint256) {
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp_, userOpHash_, maxCost_);
    }

    /**
     * @inheritdoc IPaymaster
     */
    function postOp(
        PostOpMode mode_,
        bytes calldata context_,
        uint256 actualGasCost_,
        uint256 actualUserOpFeePerGas_
    ) public virtual override {
        _requireFromEntryPoint();
        _postOp(mode_, context_, actualGasCost_, actualUserOpFeePerGas_);
    }

    /**
     * @inheritdoc IBasePaymaster
     */
    function deposit() public payable virtual override {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        $.entryPoint.depositTo{value: msg.value}(address(this));
    }

    /**
     * @inheritdoc IBasePaymaster
     */
    function withdrawTo(
        address payable withdrawAddress_,
        uint256 amount_
    ) public virtual override onlyOwner {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        $.entryPoint.withdrawTo(withdrawAddress_, amount_);
    }

    /**
     * @inheritdoc IBasePaymaster
     */
    function addStake(
        uint32 unstakeDelaySec_
    ) public payable virtual override onlyOwner {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        $.entryPoint.addStake{value: msg.value}(unstakeDelaySec_);
    }

    /**
     * @inheritdoc IBasePaymaster
     */
    function unlockStake() public virtual override onlyOwner {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        $.entryPoint.unlockStake();
    }

    /**
     * @inheritdoc IBasePaymaster
     */
    function withdrawStake(
        address payable withdrawAddress_
    ) public virtual override onlyOwner {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        $.entryPoint.withdrawStake(withdrawAddress_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Validates a user operation for paymaster sponsorship
     * @dev Must be implemented by concrete paymaster contracts.
     * Called by validatePaymasterUserOp after EntryPoint validation.
     * @param userOp_ The user operation to validate
     * @param userOpHash_ The hash of the user operation
     * @param maxCost_ The maximum cost of the user operation
     * @return context Optional context data to pass to postOp
     * @return validationData Validation result (0 for success, 1 for failure, or packed timestamp)
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp_,
        bytes32 userOpHash_,
        uint256 maxCost_
    ) internal virtual returns (bytes memory context, uint256 validationData);

    /**
     * @notice Handles post-operation logic after user operation execution
     * @dev Called only by the EntryPoint after operation execution.
     * If validatePaymasterUserOp returns a non-empty context, this method must be overridden.
     * @param mode_ The result mode of the operation (opSucceeded, opReverted, postOpReverted)
     * @param context_ The context data returned by validatePaymasterUserOp
     * @param actualGasCost_ Actual gas used so far (excluding this postOp call)
     * @param actualUserOpFeePerGas_ The gas price paid by this UserOp
     * @custom:throws PostOpNotImplemented if not overridden by inheriting contract
     */
    function _postOp(
        PostOpMode mode_,
        bytes calldata context_,
        uint256 actualGasCost_,
        uint256 actualUserOpFeePerGas_
    ) internal virtual {
        (mode_, context_, actualGasCost_, actualUserOpFeePerGas_); // unused params
        // subclass must override this method if validatePaymasterUserOp returns a context
        revert PostOpNotImplemented();
    }

    /**
     * @notice Validates that the caller is the configured EntryPoint
     * @dev Used as a modifier replacement to ensure only EntryPoint can call certain functions
     * @custom:throws CallerNotEntryPoint if caller is not the EntryPoint
     */
    function _requireFromEntryPoint() internal virtual {
        BasePaymasterStorage storage $ = _getBasePaymasterStorage();
        if (msg.sender != address($.entryPoint)) {
            revert CallerNotEntryPoint();
        }
    }

    /**
     * @notice Validates that the provided address implements the IEntryPoint interface
     * @dev Ensures compatibility between the paymaster and EntryPoint contracts
     * @param entryPoint_ The EntryPoint contract to validate
     * @custom:throws InvalidEntryPointInterface if the address doesn't implement IEntryPoint
     */
    function _validateEntryPointInterface(
        IEntryPoint entryPoint_
    ) internal virtual {
        if (
            !IERC165(address(entryPoint_)).supportsInterface(
                type(IEntryPoint).interfaceId
            )
        ) {
            revert InvalidEntryPointInterface();
        }
    }
}
