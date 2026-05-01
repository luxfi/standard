// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

import { ClaimIssuer } from "@luxfi/onchain-id/contracts/ClaimIssuer.sol";

/// @title Issuer
/// @notice Generic, brand-neutral ERC-735 ClaimIssuer template. Any party
///         (IDV provider, broker-dealer, transfer agent, registrar, custodian,
///         AML screen, accreditation verifier) deploys an instance and is
///         authorised for a topic set in `TrustedIssuersRegistry`.
/// @dev    On-chain authority is the management key; off-chain signing happens
///         via the issuer's secp256k1 (or, post-PQ, ML-DSA-65) key registered
///         on this contract with purpose=3 (CLAIM key). Topic restrictions are
///         enforced by `TrustedIssuersRegistry`, NOT by this contract — keep
///         the contract maximally generic so the same template ships across
///         every regulated role.
///
///         Naming convention for deployed instances (off-chain config / docs):
///           IDV{N}    — identity verification (typically topics 1-4)
///           BD{N}     — broker-dealer (typically 5-7: KYC/AML/ACCREDITED)
///           TA{N}     — transfer agent (typically 100+: Reg D / Rule 144 / Reg S)
///           AML{N}    — AML screening (typically topic 6 alone)
///           CUSTODY{N}— custodian (jurisdiction-specific)
///         The {N} index lets multi-tenant deployments coexist
///         (e.g. BD-liquidity, BD-mlc, BD-vcc).
contract Issuer is ClaimIssuer {
    /// @param initialManagementKey Address whose hash becomes the seed
    ///        MANAGEMENT (purpose 1) key. Required by ERC-734.
    constructor(address initialManagementKey) ClaimIssuer(initialManagementKey) {}
}
