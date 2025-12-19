// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * A contract with an incompatible storage layout for upgrade testing
 * This contract uses the same storage slot as the name string in ConcreteUpgradeableContract
 * but with a different data type, which will cause storage corruption
 */
contract IncompatibleStorageContract is UUPSUpgradeable, OwnableUpgradeable {
    // Using same slot as "string public name" in ConcreteUpgradeableContract
    // but with a different type
    uint256 public nameSlotAsNumber;

    constructor() {
        _disableInitializers();
    }

    /**
     * Initialize function that will corrupt storage
     */
    function initialize() public reinitializer(2) {
        // We don't need to call parent initializers again since this is an upgrade

        // Set a large value that will corrupt the string length
        nameSlotAsNumber = type(uint256).max;
    }

    /**
     * Function to check what value is in the storage slot
     */
    function getNameSlotValue() public view returns (uint256) {
        return nameSlotAsNumber;
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        // Authorization is handled by the onlyOwner modifier
    }
}
