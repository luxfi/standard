// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

// Single import barrel for the ERC-734/735 Identity stack (OnchainID).
// Consumers import only from `@luxfi/standard` — no separate
// `@luxfi/onchain-id` / `@onchain-id/solidity` package dependency.
//
// Implementation files live under `securities/onchainid/` (vendored from
// upstream Tokeny ONCHAINID 2.2.1 with OZ v5 patches; upstream is OZ-v4-
// locked).
//
// `Identity` is the per-investor claim-bearing contract.
// `IdentityAuthority` is its proxy authority (held by `IdentityFactory`).
// `IdentityFactory` deploys per-investor / per-token `Identity` proxies.

import {Identity} from "@luxfi/standard/securities/onchainid/Identity.sol";
import {IIdentity} from "@luxfi/standard/securities/onchainid/interface/IIdentity.sol";
import {IClaimIssuer} from "@luxfi/standard/securities/onchainid/interface/IClaimIssuer.sol";

import {
    ImplementationAuthority as IdentityAuthority
} from "@luxfi/standard/securities/onchainid/proxy/ImplementationAuthority.sol";

import {
    IdFactory as IdentityFactory
} from "@luxfi/standard/securities/onchainid/factory/IdFactory.sol";
