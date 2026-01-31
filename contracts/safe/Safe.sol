// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.31;

/**
 * @title Safe Re-exports
 * @author Lux Industries Inc
 * @notice Complete Safe Global contract re-exports for @luxfi/standard
 * @dev Import everything from here - no need for @safe-global imports
 *
 * Usage:
 *   import {Safe, SafeL2, SafeProxy, SafeProxyFactory} from "@luxfi/standard/safe/Safe.sol";
 *   import {MultiSend, MultiSendCallOnly} from "@luxfi/standard/safe/Safe.sol";
 *   import {Enum} from "@luxfi/standard/safe/Safe.sol";
 *
 * All contracts are from audited Safe Global v1.5.0
 * See: https://github.com/safe-global/safe-smart-account
 */

// ============ Core Safe Contracts ============

import {Safe} from "@safe-global/safe-smart-account/Safe.sol";
import {SafeL2} from "@safe-global/safe-smart-account/SafeL2.sol";

// ============ Proxy & Factory ============

import {SafeProxy} from "@safe-global/safe-smart-account/proxies/SafeProxy.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";

// ============ Libraries ============

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {MultiSend} from "@safe-global/safe-smart-account/libraries/MultiSend.sol";
import {MultiSendCallOnly} from "@safe-global/safe-smart-account/libraries/MultiSendCallOnly.sol";

// ============ Handlers ============

import {CompatibilityFallbackHandler} from "@safe-global/safe-smart-account/handler/CompatibilityFallbackHandler.sol";
import {TokenCallbackHandler} from "@safe-global/safe-smart-account/handler/TokenCallbackHandler.sol";

// ============ Interfaces ============

import {ISafe} from "@safe-global/safe-smart-account/interfaces/ISafe.sol";
import {ISignatureValidator} from "@safe-global/safe-smart-account/interfaces/ISignatureValidator.sol";
import {IModuleManager} from "@safe-global/safe-smart-account/interfaces/IModuleManager.sol";

// ============ Base Contracts ============

import {Executor} from "@safe-global/safe-smart-account/base/Executor.sol";
import {FallbackManager} from "@safe-global/safe-smart-account/base/FallbackManager.sol";
import {GuardManager} from "@safe-global/safe-smart-account/base/GuardManager.sol";
import {ModuleManager} from "@safe-global/safe-smart-account/base/ModuleManager.sol";
import {OwnerManager} from "@safe-global/safe-smart-account/base/OwnerManager.sol";
