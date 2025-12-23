// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/proxies/SafeProxy.sol";

/**
 * @title LuxSafeFactory
 * @author Lux Industries Inc
 * @notice Factory for deploying Safe multisig wallets on Lux Network
 * @dev Extends Safe Global's SafeProxyFactory v1.5.0
 * 
 * This is a thin wrapper around the audited Safe contracts.
 * See: https://github.com/safe-global/safe-smart-account
 */
contract LuxSafeFactory is SafeProxyFactory {
    /// @notice Lux-specific version identifier
    string public constant LUX_VERSION = "1.0.0";

    /// @notice Returns the Lux factory version
    function luxVersion() external pure returns (string memory) {
        return LUX_VERSION;
    }
}
