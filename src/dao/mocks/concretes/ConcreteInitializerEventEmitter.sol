// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";

/**
 * @title ConcreteInitializerEventEmitter
 * @author Lux Industriesn Inc
 * @notice Concrete implementation of InitializerEventEmitter for testing
 * @dev This contract is used to test the InitializerEventEmitter abstract contract
 * in isolation. It provides a minimal implementation with standard test scenarios.
 */
contract ConcreteInitializerEventEmitter is InitializerEventEmitter {
    /**
     * @notice Constructor disables initializers to prevent implementation initialization
     * @dev Standard pattern for upgradeable contract implementations
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract and emits initialization data
     * @dev Standard initializer that calls the parent __InitializerEventEmitter_init
     * @param initData_ The initialization data to emit
     */
    function initialize(bytes memory initData_) external initializer {
        __InitializerEventEmitter_init(initData_);
    }

    /**
     * @notice Attempts to reinitialize the contract (should fail)
     * @dev This function is used to test that __InitializerEventEmitter_init
     * cannot be called after initialization due to onlyInitializing modifier
     * @param initData_ The initialization data to emit
     */
    function reinitialize(bytes memory initData_) external reinitializer(2) {
        __InitializerEventEmitter_init(initData_);
    }
}
