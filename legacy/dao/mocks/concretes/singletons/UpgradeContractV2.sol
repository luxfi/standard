// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {UpgradeContractV1} from "./UpgradeContractV1.sol";

/**
 * An implementation of the OpenZeppelin `IVotes` voting token standard.
 * Implements the UUPS proxy pattern for upgradeability.
 */
contract UpgradeContractV2 is UpgradeContractV1 {
    uint16 public version;

    constructor() {
        _disableInitializers();
    }

    /**
     * Initialize function, will be triggered when a new proxy instance is deployed.
     *
     * @param _version Contract version
     */
    function initialize(uint16 _version) public virtual reinitializer(2) {
        version = _version;
    }
}
