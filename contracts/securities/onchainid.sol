// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

// One-stop import of the ERC-734/735 Identity stack (OnchainID) Lux and
// Liquidity use. Consumers import from
// `@luxfi/standard/contracts/securities/onchainid.sol` rather than
// `@luxfi/onchain-id/...` directly so:
//
//   1. There is exactly one path per concept.
//   2. Upstream package layout changes are absorbed at this seam.
//   3. The brand "ONCHAINID" / "Impl" never appears in consumer code.
//
// `Identity` is the per-investor claim-bearing contract.
// `IdentityAuthority` is its proxy authority (held by `IdentityFactory`).
// `IdentityFactory` deploys per-investor / per-token `Identity` proxies.

import {Identity} from "@luxfi/onchain-id/contracts/Identity.sol";
import {IIdentity} from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";
import {IClaimIssuer} from "@luxfi/onchain-id/contracts/interface/IClaimIssuer.sol";

import {
    ImplementationAuthority as IdentityAuthority
} from "@luxfi/onchain-id/contracts/proxy/ImplementationAuthority.sol";

import {
    IdFactory as IdentityFactory
} from "@luxfi/onchain-id/contracts/factory/IdFactory.sol";
