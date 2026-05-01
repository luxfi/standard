// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

/// @title ClaimTopics
/// @notice Canonical ERC-735 claim topic numbers. The role-of-issuer that
///         signs each topic is convention only — the on-chain authority is
///         `TrustedIssuersRegistry`, which any deployment configures per
///         jurisdiction. Listed here so every contract / SDK / script imports
///         the same numbers.
/// @dev    Topic range allocation:
///           1-49      identity (IDV provider scope)
///           50-99     compliance (broker-dealer / accreditation scope)
///           100-199   transfer-agent (security-token-specific restrictions)
///           200-299   custody (custodian-specific constraints)
///           300-399   AML / sanctions (screen-specific)
///           1000+     custom / experimental (per deployment)
library ClaimTopics {
    // ── Identity (1-49) — typically an IDV provider ───────────────────
    uint256 internal constant ID_VERIFIED       = 1;
    uint256 internal constant LIVENESS          = 2;
    uint256 internal constant BIOMETRIC_UNIQUE  = 3;
    uint256 internal constant JURISDICTION      = 4;

    // ── Compliance (50-99) — typically a broker-dealer ────────────────
    uint256 internal constant KYC               = 5;
    uint256 internal constant AML               = 6;
    uint256 internal constant ACCREDITED        = 7;
    uint256 internal constant SOURCE_OF_FUNDS   = 8;
    uint256 internal constant TAX_RESIDENCY     = 9;

    // ── Transfer Agent (100-199) — security-token-specific ────────────
    uint256 internal constant REG_D_LOCKUP      = 100;
    uint256 internal constant RULE_144_HOLD     = 101;
    uint256 internal constant REG_S_NON_US      = 102;
    uint256 internal constant REG_A_PLUS_TIER1  = 103;
    uint256 internal constant REG_A_PLUS_TIER2  = 104;
    uint256 internal constant REG_CF            = 105;

    // ── Signing schemes (ERC-735 `scheme` field) ──────────────────────
    uint256 internal constant SCHEME_ECDSA      = 1;  // secp256k1 (legacy / classical)
    uint256 internal constant SCHEME_MLDSA_65   = 2;  // FIPS 204 (post-quantum)
    uint256 internal constant SCHEME_HYBRID     = 3;  // ECDSA + ML-DSA, both required

    // ── Key purposes (ERC-734) ────────────────────────────────────────
    uint256 internal constant PURPOSE_MANAGEMENT = 1;
    uint256 internal constant PURPOSE_ACTION     = 2;
    uint256 internal constant PURPOSE_CLAIM      = 3;
    uint256 internal constant PURPOSE_ENCRYPTION = 4;
}
