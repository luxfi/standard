// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { SecurityToken } from "../token/SecurityToken.sol";
import { DocumentRegistry } from "../registry/DocumentRegistry.sol";

import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import { IIdentityRegistryStorage } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistryStorage.sol";
import { IClaimTopicsRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IClaimTopicsRegistry.sol";
import { ITrustedIssuersRegistry } from "@luxfi/erc-3643/contracts/registry/interface/ITrustedIssuersRegistry.sol";
import { IModularCompliance } from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";
import { IClaimIssuer } from "@luxfi/onchain-id/contracts/interface/IClaimIssuer.sol";

import { Topics } from "../constants/Topics.sol";
import { Offerings } from "../constants/Offerings.sol";

/// @title SecurityTokenFactory
/// @notice Wires a complete T-REX security-token stack for a given offering type.
///         The caller supplies pre-deployed (and pre-initialised) T-REX
///         implementation contracts (`IdentityRegistry`, `IdentityRegistryStorage`,
///         `ClaimTopicsRegistry`, `TrustedIssuersRegistry`, `ModularCompliance`).
///         The factory deploys the `SecurityToken` and the `DocumentRegistry`,
///         configures per-offering claim topics, registers the BD + TA
///         `ClaimIssuer`s, and binds the storage / compliance to the token.
/// @dev    Why "wire pre-deployed components" instead of "factory deploys them":
///         the canonical Tokeny T-REX is OpenZeppelin v4. Lux/Liquidity ship
///         OpenZeppelin v5. To stay on stock T-REX (no custom rewrite of the
///         registries) we accept the implementations as input — the deploy
///         script handles the v4 init dance once, and per-token deploys are
///         pure-v5 here.
///
///         All ownership/agent rights are transferred to `params.admin` at the
///         end of `deploy()`.
contract SecurityTokenFactory {
    struct Components {
        IIdentityRegistry identityRegistry;
        IIdentityRegistryStorage identityRegistryStorage;
        IClaimTopicsRegistry claimTopicsRegistry;
        ITrustedIssuersRegistry trustedIssuersRegistry;
        IModularCompliance modularCompliance;
    }

    struct Params {
        string name;
        string symbol;
        uint8 decimals;
        bytes32 offering; // Offerings.* (REG_D_506C, RULE_144A, …)
        uint16 countryISO; // ISO 3166-1 numeric (840 = US, 250 = FR)
        address bdClaimIssuer; // BD ClaimIssuer ONCHAINID (issues topics 1-5)
        address taClaimIssuer; // TA ClaimIssuer ONCHAINID (issues topic 6)
        address admin; // ends up as DEFAULT_ADMIN_ROLE on the Token
        Components components; // pre-deployed T-REX components
    }

    struct Deployment {
        SecurityToken token;
        DocumentRegistry documentRegistry;
        Components components;
    }

    event SecurityStackDeployed(address indexed token, bytes32 indexed offering, uint16 countryISO, address admin);

    error ZeroAddress();
    error EmptyParams();

    /// @notice Wire a security-token stack on top of pre-deployed T-REX components.
    function deploy(Params calldata p) external returns (Deployment memory d) {
        if (p.admin == address(0) || p.bdClaimIssuer == address(0) || p.taClaimIssuer == address(0)) {
            revert ZeroAddress();
        }
        if (bytes(p.name).length == 0 || bytes(p.symbol).length == 0) revert EmptyParams();
        if (
            address(p.components.identityRegistry) == address(0)
                || address(p.components.identityRegistryStorage) == address(0)
                || address(p.components.claimTopicsRegistry) == address(0)
                || address(p.components.trustedIssuersRegistry) == address(0)
                || address(p.components.modularCompliance) == address(0)
        ) revert ZeroAddress();

        // 1. Per-offering claim topics ------------------------------------
        uint256[] memory required = Offerings.requiredTopics(p.offering);
        for (uint256 i = 0; i < required.length; ++i) {
            p.components.claimTopicsRegistry.addClaimTopic(required[i]);
        }

        // 2. Trusted issuers (BD: 1-5, TA: 6) -----------------------------
        uint256[] memory bdTopics = _bdTopics();
        p.components.trustedIssuersRegistry.addTrustedIssuer(IClaimIssuer(p.bdClaimIssuer), bdTopics);

        uint256[] memory taTopics = new uint256[](1);
        taTopics[0] = Topics.AFFILIATE;
        p.components.trustedIssuersRegistry.addTrustedIssuer(IClaimIssuer(p.taClaimIssuer), taTopics);

        // 3. Token --------------------------------------------------------
        d.token = new SecurityToken(
            p.name,
            p.symbol,
            p.decimals,
            p.components.identityRegistry,
            p.components.modularCompliance,
            address(0),
            p.admin
        );

        // 4. Documents ----------------------------------------------------
        d.documentRegistry = new DocumentRegistry(p.admin);

        d.components = p.components;

        emit SecurityStackDeployed(address(d.token), p.offering, p.countryISO, p.admin);
    }

    function _bdTopics() internal pure returns (uint256[] memory t) {
        t = new uint256[](5);
        t[0] = Topics.KYC;
        t[1] = Topics.AML;
        t[2] = Topics.ACCREDITED_VERIFIED;
        t[3] = Topics.ACCREDITED_SELF;
        t[4] = Topics.QIB;
    }
}
