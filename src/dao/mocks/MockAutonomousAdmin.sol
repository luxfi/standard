// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockAutonomousAdmin
 * @dev Mock implementation of AutonomousAdminV1 for testing purposes.
 * Provides functionality needed for testing UtilityRolesManagementV1.
 */
contract MockAutonomousAdmin {
    bool public initialized;

    /**
     * @dev Initialize the autonomous admin
     */
    function initialize() external {
        initialized = true;
    }

    /**
     * @dev Check if initialized (for testing)
     * @return Whether the contract is initialized
     */
    function isInitialized() external view returns (bool) {
        return initialized;
    }
}
