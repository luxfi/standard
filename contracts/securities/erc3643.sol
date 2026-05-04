// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

// One-stop import of the ERC-3643 (T-REX) registry / compliance stack
// Lux and Liquidity actually use. Consumers import from
// `@luxfi/standard/contracts/securities/erc3643.sol` rather than
// `@luxfi/erc-3643/...` directly so:
//
//   1. There is exactly one path per concept.
//   2. Upstream package layout changes are absorbed at this seam.
//   3. The brand "T-REX" / "Impl" never appears in consumer code.
//
// The canonical security-token contract Liquidity deploys per issuance
// is Lux's own `SecurityToken` at `securities/token/SecurityToken.sol`
// — constructor-based, AccessControl-driven, deployed via Lux's
// `SecurityTokenFactory` at `securities/factory/SecurityTokenFactory.sol`.
// The upstream Tokeny `Token`, `TREXImplementationAuthority`, and
// `TREXFactory` are NOT re-exported from here: Liquidity does not use
// the upstream proxy/suite deploy path, and exposing two SecurityToken
// types would conflate the canonical implementation with an unused
// reference.
//
// Build note: this file is excluded from `lux/standard`'s default forge
// build via `[profile.default] skip = ["**/securities/erc3643.sol"]`.
// The upstream `@luxfi/erc-3643` npm package targets OpenZeppelin v4
// init signatures while `lux/standard` ships v5; consumers (e.g.
// liquidityio/contracts) vendor a fork that has the v5 init patches
// applied and compile this file successfully there.

// --- Registry implementations -----------------------------------------

import {IdentityRegistry} from "@luxfi/erc-3643/contracts/registry/implementation/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "@luxfi/erc-3643/contracts/registry/implementation/IdentityRegistryStorage.sol";
import {ClaimTopicsRegistry} from "@luxfi/erc-3643/contracts/registry/implementation/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "@luxfi/erc-3643/contracts/registry/implementation/TrustedIssuersRegistry.sol";

// --- Registry interfaces ----------------------------------------------

import {IIdentityRegistry} from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistryStorage.sol";
import {IClaimTopicsRegistry} from "@luxfi/erc-3643/contracts/registry/interface/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "@luxfi/erc-3643/contracts/registry/interface/ITrustedIssuersRegistry.sol";

// --- Compliance + module base -----------------------------------------

import {ModularCompliance} from "@luxfi/erc-3643/contracts/compliance/modular/ModularCompliance.sol";
import {IModularCompliance} from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";
import {AbstractModule} from "@luxfi/erc-3643/contracts/compliance/modular/modules/AbstractModule.sol";

// --- Token interface (the contract is Lux's, not re-exported) ---------

import {IToken} from "@luxfi/erc-3643/contracts/token/IToken.sol";
