// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

/// @title Topics
/// @notice The six canonical ERC-735 claim topics every Lux/Liquidity security
///         token recognises. Country is NOT a topic — it lives in
///         `IdentityRegistryStorage.investorCountry()` as a uint16
///         ISO 3166-1 numeric code.
/// @dev    Issuer + expiry rules:
///           1 KYC                  — BD ClaimIssuer, 365d
///           2 AML                  — BD ClaimIssuer, 7d
///           3 ACCREDITED_VERIFIED  — BD ClaimIssuer, 90d  (Reg D 506(c))
///           4 ACCREDITED_SELF      — BD ClaimIssuer, 365d (Reg D 506(b))
///           5 QIB                  — BD ClaimIssuer, 365d (Rule 144A)
///           6 AFFILIATE            — TA ClaimIssuer, persists
library Topics {
    uint256 internal constant KYC = 1;
    uint256 internal constant AML = 2;
    uint256 internal constant ACCREDITED_VERIFIED = 3;
    uint256 internal constant ACCREDITED_SELF = 4;
    uint256 internal constant QIB = 5;
    uint256 internal constant AFFILIATE = 6;
}
