// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { Topics } from "./Topics.sol";

/// @title Offerings
/// @notice The five canonical securities-offering types and the per-offering
///         required ERC-735 claim-topic sets. Country gates are configured
///         per-token on `CountryAllowModule` / `CountryRestrictModule`
///         (T-REX legacy) — not encoded here.
library Offerings {
    bytes32 internal constant RETAIL_PUBLIC = keccak256("RETAIL_PUBLIC");
    bytes32 internal constant REG_D_506B = keccak256("REG_D_506B");
    bytes32 internal constant REG_D_506C = keccak256("REG_D_506C");
    bytes32 internal constant REG_S = keccak256("REG_S");
    bytes32 internal constant RULE_144A = keccak256("RULE_144A");

    /// @notice Required claim topics for a given offering type.
    function requiredTopics(bytes32 offering) internal pure returns (uint256[] memory topics) {
        if (offering == RETAIL_PUBLIC || offering == REG_S) {
            topics = new uint256[](2);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
        } else if (offering == REG_D_506B) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.ACCREDITED_SELF;
        } else if (offering == REG_D_506C) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.ACCREDITED_VERIFIED;
        } else if (offering == RULE_144A) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.QIB;
        } else {
            revert UnknownOffering(offering);
        }
    }

    error UnknownOffering(bytes32 offering);
}
