// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

// Single import barrel for the ERC-3643 (T-REX) registry / compliance
// stack. Consumers import only from `@luxfi/standard` — no separate
// `@luxfi/erc-3643` / `@onchain-id/solidity` package dependency.
//
// Implementation files live under `securities/erc3643/` (vendored from
// upstream Tokeny T-REX 4.1.6 with OZ v5 patches; upstream is OZ-v4-
// locked and officially deprecated). The canonical per-issuance
// security-token contract is Lux's own
// `securities/token/SecurityToken.sol`, deployed through Lux's
// `securities/factory/SecurityTokenFactory.sol`. The upstream Tokeny
// `Token`, `TREXImplementationAuthority`, and `TREXFactory` are not
// re-exported — Liquidity does not use the upstream proxy/suite path.

// --- Registry implementations -----------------------------------------

import {IdentityRegistry} from "@luxfi/standard/securities/erc3643/registry/implementation/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "@luxfi/standard/securities/erc3643/registry/implementation/IdentityRegistryStorage.sol";
import {ClaimTopicsRegistry} from "@luxfi/standard/securities/erc3643/registry/implementation/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "@luxfi/standard/securities/erc3643/registry/implementation/TrustedIssuersRegistry.sol";

// --- Registry interfaces ----------------------------------------------

import {IIdentityRegistry} from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistryStorage.sol";
import {IClaimTopicsRegistry} from "@luxfi/standard/securities/erc3643/registry/interface/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "@luxfi/standard/securities/erc3643/registry/interface/ITrustedIssuersRegistry.sol";

// --- Compliance + module base -----------------------------------------

import {ModularCompliance} from "@luxfi/standard/securities/erc3643/compliance/modular/ModularCompliance.sol";
import {IModularCompliance} from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import {AbstractModule} from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";

// --- Token interface (the contract is Lux's, not re-exported) ---------

import {IToken} from "@luxfi/standard/securities/erc3643/token/IToken.sol";
