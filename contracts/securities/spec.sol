// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

// Single import surface for the ERC-3643 + ERC-734/735 implementations
// Lux and Liquidity consume. Consumers import from
// `@luxfi/standard/contracts/securities/spec.sol` rather than
// `@luxfi/erc-3643/...` or `@luxfi/onchain-id/...` directly so:
//
//   1. There is exactly one import path per concept.
//   2. Brand-neutral aliases (no "TREX", "ONCHAINID", or "Impl" in
//      consumer code) are applied here once.
//   3. Upstream package layout changes don't ripple through every
//      consumer — they're absorbed at this single seam.
//
// Lux's own ERC-3643 extensions (`SecurityToken`, `SecurityTokenFactory`,
// `SecurityBridge`, `CorporateActions`, `DividendDistributor`,
// `DocumentRegistry`) live alongside in `securities/{token,factory,...}/`
// and are imported from their direct paths — they're _not_ re-exported
// here because they're already brand-neutral and Lux-native.
//
// Build note: this file is excluded from `lux/standard`'s default forge
// build via `[profile.default] skip = ["spec.sol"]` because the upstream
// `@luxfi/erc-3643` package on npm targets OpenZeppelin v4 init signatures
// and `lux/standard` ships v5. Consumers (e.g. liquidityio/contracts)
// vendor a fork that has the v5 init patches applied and compile this
// file successfully there. Once the v5 patches land in upstream
// `@luxfi/erc-3643` main, the skip can be removed.

// --- ERC-3643 token logic + interface ----------------------------------

import {Token} from "@luxfi/erc-3643/contracts/token/Token.sol";
import {IToken} from "@luxfi/erc-3643/contracts/token/IToken.sol";

// --- Registry implementations + interfaces -----------------------------

import {IdentityRegistry} from "@luxfi/erc-3643/contracts/registry/implementation/IdentityRegistry.sol";
import {IdentityRegistryStorage} from "@luxfi/erc-3643/contracts/registry/implementation/IdentityRegistryStorage.sol";
import {ClaimTopicsRegistry} from "@luxfi/erc-3643/contracts/registry/implementation/ClaimTopicsRegistry.sol";
import {TrustedIssuersRegistry} from "@luxfi/erc-3643/contracts/registry/implementation/TrustedIssuersRegistry.sol";

import {IIdentityRegistry} from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistryStorage.sol";
import {IClaimTopicsRegistry} from "@luxfi/erc-3643/contracts/registry/interface/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "@luxfi/erc-3643/contracts/registry/interface/ITrustedIssuersRegistry.sol";

// --- Compliance + module base ------------------------------------------

import {ModularCompliance} from "@luxfi/erc-3643/contracts/compliance/modular/ModularCompliance.sol";
import {IModularCompliance} from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";
import {AbstractModule} from "@luxfi/erc-3643/contracts/compliance/modular/modules/AbstractModule.sol";

// --- ERC-3643 v4.0.0 proxy infrastructure ------------------------------
//
// `SecurityTokenAuthority` holds the version-aware addresses of the six
// logic contracts above; per-suite proxies read it on every call.
// Brand-neutral aliases applied so consumers never type "TREX".

import {
    TREXImplementationAuthority as SecurityTokenAuthority
} from "@luxfi/erc-3643/contracts/proxy/authority/TREXImplementationAuthority.sol";
import {
    ITREXImplementationAuthority as ISecurityTokenAuthority
} from "@luxfi/erc-3643/contracts/proxy/authority/ITREXImplementationAuthority.sol";
// Aliased: distinguishes the upstream "deploys a full SecurityToken suite
// (token + 5 registries + ClaimIssuer wiring) in one tx" factory from
// Lux's own per-token `SecurityTokenFactory` (`securities/factory/`).
import {
    TREXFactory as SecurityTokenSuiteFactory
} from "@luxfi/erc-3643/contracts/factory/TREXFactory.sol";

// --- ERC-734/735 Identity ----------------------------------------------
//
// `Identity` is the per-investor claim-bearing contract.
// `IdentityAuthority` is its proxy authority (held by `IdentityFactory`).
// `IdentityFactory` deploys per-investor / per-token Identity proxies.

import {Identity} from "@luxfi/onchain-id/contracts/Identity.sol";
import {
    ImplementationAuthority as IdentityAuthority
} from "@luxfi/onchain-id/contracts/proxy/ImplementationAuthority.sol";
import {
    IdFactory as IdentityFactory
} from "@luxfi/onchain-id/contracts/factory/IdFactory.sol";
import {IIdentity} from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";
import {IClaimIssuer} from "@luxfi/onchain-id/contracts/interface/IClaimIssuer.sol";
