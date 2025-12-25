// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.31;

import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/proxies/SafeProxy.sol";

/**
 * @title SafeFactory
 * @notice Factory for deploying Safe multisig wallets
 * @dev Extends Safe Global's SafeProxyFactory v1.5.0
 *
 * This is a thin wrapper around the audited Safe contracts.
 * See: https://github.com/safe-global/safe-smart-account
 */
contract SafeFactory is SafeProxyFactory {
    /// @notice Version identifier
    string public constant FACTORY_VERSION = "1.0.0";

    /// @notice Returns the factory version
    function factoryVersion() external pure returns (string memory) {
        return FACTORY_VERSION;
    }
}
