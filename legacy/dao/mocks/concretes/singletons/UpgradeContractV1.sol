// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * An implementation of the OpenZeppelin `IVotes` voting token standard.
 * Implements the UUPS proxy pattern for upgradeability.
 */
contract UpgradeContractV1 is UUPSUpgradeable, OwnableUpgradeable {
    string public name;

    constructor() {
        _disableInitializers();
    }

    /**
     * Initialize function, will be triggered when a new proxy instance is deployed.
     *
     * @param _name Contract name
     * @param _owner Address that will own the proxy and be able to upgrade it
     */
    function initialize(
        string calldata _name,
        address _owner
    ) public virtual initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        name = _name;
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
