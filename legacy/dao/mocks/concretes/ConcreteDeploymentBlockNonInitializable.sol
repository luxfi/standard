// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    DeploymentBlockNonInitializable
} from "../../DeploymentBlockNonInitializable.sol";

// Concrete implementation for testing
contract ConcreteDeploymentBlockNonInitializable is
    DeploymentBlockNonInitializable
{
    constructor() DeploymentBlockNonInitializable() {}
}
