// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    BasePaymaster
} from "../../../../deployables/account-abstraction/BasePaymaster.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

/**
 * @title ConcreteBasePaymaster
 * @notice Mock implementation of BasePaymaster for testing
 * @dev This contract implements the abstract methods of BasePaymaster to enable
 * unit testing of the base paymaster functionality.
 */
contract ConcreteBasePaymaster is BasePaymaster {
    // Storage for test configuration
    bool public shouldReturnContext;
    bytes public contextToReturn;
    uint256 public validationDataToReturn;
    bool public postOpImplemented;

    function initialize(
        address owner_,
        IEntryPoint entryPoint_
    ) public initializer {
        __BasePaymaster_init(owner_, entryPoint_);
    }

    /**
     * @dev Test helper to configure validation behavior
     */
    function setValidationBehavior(
        bool shouldReturnContext_,
        bytes memory contextToReturn_,
        uint256 validationDataToReturn_
    ) external {
        shouldReturnContext = shouldReturnContext_;
        contextToReturn = contextToReturn_;
        validationDataToReturn = validationDataToReturn_;
    }

    /**
     * @dev Test helper to enable/disable postOp implementation
     */
    function setPostOpImplemented(bool implemented_) external {
        postOpImplemented = implemented_;
    }

    /**
     * @inheritdoc BasePaymaster
     * @dev Mock implementation that returns configurable validation data
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata,
        bytes32,
        uint256
    ) internal view override returns (bytes memory, uint256) {
        if (shouldReturnContext) {
            return (contextToReturn, validationDataToReturn);
        }
        return (bytes(""), validationDataToReturn);
    }

    /**
     * @inheritdoc BasePaymaster
     * @dev Mock implementation that can either revert or process successfully
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        if (!postOpImplemented) {
            super._postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
        }
        // If postOpImplemented is true, this function succeeds without reverting
    }

    /**
     * @dev Test helper to directly call _requireFromEntryPoint for testing
     */
    function testRequireFromEntryPoint() external {
        _requireFromEntryPoint();
    }

    /**
     * @dev Test helper to directly call _validateEntryPointInterface for testing
     */
    function testValidateEntryPointInterface(IEntryPoint entryPoint_) external {
        _validateEntryPointInterface(entryPoint_);
    }
}
