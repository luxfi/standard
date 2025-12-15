// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

import "../IAllowList.sol";

/**
 * @title IDeployerAllowList
 * @dev Interface for the Contract Deployer Allow List precompile
 *
 * This precompile restricts which addresses can deploy contracts on the network.
 * Only addresses with Enabled, Admin, or Manager roles can deploy contracts.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000000
 *
 * Use Cases:
 * - Permissioned chains where only approved deployers can create contracts
 * - Enterprise networks with controlled smart contract deployment
 * - Development networks with restricted deployment access
 *
 * Roles:
 * - None (0): Cannot deploy contracts
 * - Enabled (1): Can deploy contracts
 * - Admin (2): Can deploy contracts and modify roles
 * - Manager (3): Can deploy contracts and modify non-admin roles
 *
 * Gas Costs:
 * - readAllowList: 2,600 gas
 * - setAdmin/setEnabled/setManager/setNone: 20,000 gas
 */
interface IDeployerAllowList is IAllowList {
    // Inherits all functions from IAllowList:
    // - readAllowList(address addr) -> uint256
    // - setAdmin(address addr)
    // - setEnabled(address addr)
    // - setManager(address addr)
    // - setNone(address addr)
}

/**
 * @title DeployerAllowListLib
 * @dev Library for interacting with the Deployer Allow List precompile
 */
library DeployerAllowListLib {
    /// @dev The address of the Deployer Allow List precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000000;

    error NotDeployerEnabled();

    /**
     * @notice Check if an address can deploy contracts
     * @param addr The address to check
     * @return True if the address can deploy contracts
     */
    function canDeploy(address addr) internal view returns (bool) {
        return AllowListLib.isEnabled(PRECOMPILE_ADDRESS, addr);
    }

    /**
     * @notice Require caller to be able to deploy contracts
     */
    function requireCanDeploy() internal view {
        if (!canDeploy(msg.sender)) {
            revert NotDeployerEnabled();
        }
    }

    /**
     * @notice Get the role of an address
     * @param addr The address to check
     * @return role The role (0=None, 1=Enabled, 2=Admin, 3=Manager)
     */
    function getRole(address addr) internal view returns (uint256 role) {
        return IDeployerAllowList(PRECOMPILE_ADDRESS).readAllowList(addr);
    }

    /**
     * @notice Set an address as admin (deployer admin)
     * @param addr The address to set as admin
     */
    function setAdmin(address addr) internal {
        IDeployerAllowList(PRECOMPILE_ADDRESS).setAdmin(addr);
    }

    /**
     * @notice Enable an address to deploy contracts
     * @param addr The address to enable
     */
    function setEnabled(address addr) internal {
        IDeployerAllowList(PRECOMPILE_ADDRESS).setEnabled(addr);
    }

    /**
     * @notice Disable an address from deploying contracts
     * @param addr The address to disable
     */
    function setNone(address addr) internal {
        IDeployerAllowList(PRECOMPILE_ADDRESS).setNone(addr);
    }
}
