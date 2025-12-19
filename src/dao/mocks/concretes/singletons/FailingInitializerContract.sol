// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * A test contract with an initializer that can be made to revert
 */
contract FailingInitializerContract is UUPSUpgradeable, OwnableUpgradeable {
    bool public isInitialized;

    constructor() {
        _disableInitializers();
    }

    /**
     * Initializer that reverts if shouldFail is true
     * @param shouldFail Pass true to make the initializer revert
     */
    function initialize(bool shouldFail) public initializer {
        require(!shouldFail, "Initialization failed as requested");

        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        isInitialized = true;
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        // Authorization is handled by the onlyOwner modifier
    }
}
