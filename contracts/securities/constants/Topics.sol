// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

/// @title Topics
/// @notice Canonical ERC-735 claim topics + signing schemes + ERC-734 key
///         purposes. Single source of truth across every consumer
///         (Solidity, BD/TA Go, IDV providers, off-chain SDKs). Country
///         is NOT a topic — it lives in `IdentityRegistryStorage.investorCountry()`
///         as a uint16 ISO 3166-1 numeric code.
///
///         Topic semantics are jurisdiction-agnostic. The issuer
///         (per-jurisdiction broker-dealer, IDV provider, transfer
///         agent, etc.) attests that the holder satisfies *local law*
///         for the topic. Naming uses US-derived terms (`KYC`,
///         `ACCREDITED_*`, `QIB`, `REG_*`, `RULE_*`) because the
///         standard was authored in a US context; the same topic
///         numbers attest to the corresponding tier under any other
///         jurisdiction's rules. See `compliance/access-rules.md` §1
///         for the per-jurisdiction mapping.
///
/// @dev    Topic numbering buckets:
///           1-9    Compliance      (broker-dealer scope; KYC/AML/ACCREDITED/QIB/AFFILIATE)
///           10-19  Identity (IDV)  (IDV provider scope; ID_VERIFIED/LIVENESS/BIOMETRIC/JURISDICTION)
///           100-199 Transfer Agent (security-token-specific restrictions)
///           200-299 Custody        (jurisdiction-specific custodial constraints)
///           300-399 AML/Sanctions  (screen-specific)
///           1000+  Custom          (per-deployment experimental)
///
///         Issuer + expiry conventions:
///           1 KYC                  — BD ClaimIssuer, 365d
///           2 AML                  — BD ClaimIssuer, 7d
///           3 ACCREDITED_VERIFIED  — BD ClaimIssuer, 90d  (Reg D 506(c))
///           4 ACCREDITED_SELF      — BD ClaimIssuer, 365d (Reg D 506(b))
///           5 QIB                  — BD ClaimIssuer, 365d (Rule 144A)
///           6 AFFILIATE            — TA ClaimIssuer, persists
///           10 ID_VERIFIED         — IDV provider, 365d
///           11 LIVENESS            — IDV provider, 30d (re-attestable)
///           12 BIOMETRIC_UNIQUE    — IDV provider, persists
///           13 JURISDICTION        — IDV provider, 365d (FHE-encrypted in data)
///           100 REG_D_LOCKUP       — TA, per-security
///           101 RULE_144_HOLD      — TA, per-security
///           102 REG_S_NON_US       — TA, per-security
///           103 REG_A_PLUS_TIER1   — TA, per-security
///           104 REG_A_PLUS_TIER2   — TA, per-security
///           105 REG_CF             — TA, per-security (12mo validity → first-year resale window)
///           106 BLUE_SKY_STATE     — TA, per-(security, US state); Reg D 504 + Reg A T1 + Rule 147/147A
library Topics {
    // ── Compliance (1-9) — typically broker-dealer ──────────────────────
    uint256 internal constant KYC                  = 1;
    uint256 internal constant AML                  = 2;
    uint256 internal constant ACCREDITED_VERIFIED  = 3;
    uint256 internal constant ACCREDITED_SELF      = 4;
    uint256 internal constant QIB                  = 5;
    uint256 internal constant AFFILIATE            = 6;
    uint256 internal constant SOURCE_OF_FUNDS      = 7;
    uint256 internal constant TAX_RESIDENCY        = 8;

    // ── Identity / IDV (10-19) — typically IDV provider ─────────────────
    uint256 internal constant ID_VERIFIED          = 10;
    uint256 internal constant LIVENESS             = 11;
    uint256 internal constant BIOMETRIC_UNIQUE     = 12;
    uint256 internal constant JURISDICTION         = 13;

    // ── Transfer Agent (100-199) — security-token-specific ──────────────
    uint256 internal constant REG_D_LOCKUP         = 100;
    uint256 internal constant RULE_144_HOLD        = 101;
    uint256 internal constant REG_S_NON_US         = 102;
    uint256 internal constant REG_A_PLUS_TIER1     = 103;
    uint256 internal constant REG_A_PLUS_TIER2     = 104;
    uint256 internal constant REG_CF               = 105;
    uint256 internal constant BLUE_SKY_STATE       = 106;

    // ── Signing schemes (ERC-735 `scheme` field) ────────────────────────
    uint256 internal constant SCHEME_ECDSA         = 1;  // secp256k1 (classical)
    uint256 internal constant SCHEME_MLDSA_65      = 2;  // FIPS 204 (post-quantum)
    uint256 internal constant SCHEME_HYBRID        = 3;  // ECDSA + ML-DSA, both required

    // ── ERC-734 key purposes ────────────────────────────────────────────
    uint256 internal constant PURPOSE_MANAGEMENT   = 1;
    uint256 internal constant PURPOSE_ACTION       = 2;
    uint256 internal constant PURPOSE_CLAIM        = 3;
    uint256 internal constant PURPOSE_ENCRYPTION   = 4;
}
