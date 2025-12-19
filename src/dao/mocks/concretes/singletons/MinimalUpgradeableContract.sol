// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * A minimal implementation of an upgradeable contract for testing purposes
 * Handles various initialization scenarios
 */
contract MinimalUpgradeableContract is UUPSUpgradeable, OwnableUpgradeable {
    // Storage for initialization testing
    bool public isInitialized;
    string public largeData;

    constructor() {
        _disableInitializers();
    }

    /**
     * Empty initializer that sets only minimal state
     */
    function initializeEmpty() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        isInitialized = true;
    }

    /**
     * Initializer that accepts large data
     * @param _largeData A potentially large string to test initialization gas limits
     */
    function initializeWithLargeData(
        string calldata _largeData
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        isInitialized = true;
        largeData = _largeData;
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     * Called by {upgradeTo} and {upgradeToAndCall}.
     *
     * Reverts if the sender is not the owner of the contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        // Authorization is handled by the onlyOwner modifier
    }
}
