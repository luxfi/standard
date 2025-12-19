// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";

contract ConcreteDeploymentBlockInitializable is DeploymentBlockInitializable {
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __DeploymentBlockInitializable_init();
    }

    // This should fail if called after initialize
    function reinitialize() external reinitializer(2) {
        __DeploymentBlockInitializable_init();
    }
}
