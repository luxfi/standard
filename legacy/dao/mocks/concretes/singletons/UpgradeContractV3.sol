// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {UpgradeContractV2} from "./UpgradeContractV2.sol";

/**
 * An implementation with a third version level for multi-step upgrade testing
 */
contract UpgradeContractV3 is UpgradeContractV2 {
    uint256 public additionalValue;
    bool public migrationPerformed;

    constructor() {
        _disableInitializers();
    }

    /**
     * Initialize function, will be triggered when upgrading to this implementation
     *
     * @param _additionalValue New value to store
     */
    function initialize(
        uint256 _additionalValue
    ) public virtual reinitializer(3) {
        additionalValue = _additionalValue;
    }

    /**
     * Function to migrate state from previous version
     * This simulates a complex state transformation during upgrade
     */
    function migrateState() public onlyOwner {
        // In a real implementation, this would transform existing state
        // For this test, we just set a flag
        migrationPerformed = true;
    }
}
