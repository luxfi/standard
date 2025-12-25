// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.31;

/**
 * @title Safe Re-exports
 * @author Lux Industries Inc
 * @notice Re-exports Safe Global contracts for convenience
 * @dev Use these imports for Safe integration on Lux Network
 * 
 * All contracts are from audited Safe Global v1.5.0
 * See: https://github.com/safe-global/safe-smart-account
 */

// Core Safe contracts
import {Safe} from "@safe-global/safe-smart-account/Safe.sol";
import {SafeL2} from "@safe-global/safe-smart-account/SafeL2.sol";

// Proxy and Factory
import {SafeProxy} from "@safe-global/safe-smart-account/proxies/SafeProxy.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";

// Libraries
import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {MultiSend} from "@safe-global/safe-smart-account/libraries/MultiSend.sol";
import {MultiSendCallOnly} from "@safe-global/safe-smart-account/libraries/MultiSendCallOnly.sol";

// Interfaces
import {ISafe} from "@safe-global/safe-smart-account/interfaces/ISafe.sol";
import {ISignatureValidator} from "@safe-global/safe-smart-account/interfaces/ISignatureValidator.sol";

// Handlers
import {CompatibilityFallbackHandler} from "@safe-global/safe-smart-account/handler/CompatibilityFallbackHandler.sol";
