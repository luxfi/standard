// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SecurityTokenFactory} from "../contracts/securities/factory/SecurityTokenFactory.sol";

import {IIdentityRegistry} from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistryStorage.sol";
import {IClaimTopicsRegistry} from "@luxfi/erc-3643/contracts/registry/interface/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "@luxfi/erc-3643/contracts/registry/interface/ITrustedIssuersRegistry.sol";
import {IModularCompliance} from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";

/// @title DeploySecurityTokenStack
/// @notice Foundry script for deploying a security-token stack via
///         SecurityTokenFactory. Reads pre-deployed T-REX component addresses
///         from environment variables — see the per-chain T-REX bootstrap
///         script (out of scope: that runs once per chain to seed the
///         IdentityRegistry / IdentityRegistryStorage / ClaimTopicsRegistry /
///         TrustedIssuersRegistry / ModularCompliance implementations).
///
/// @dev    Inputs (env):
///           NAME, SYMBOL, DECIMALS
///           OFFERING                   keccak256("RETAIL_PUBLIC" | … | "RULE_144A")
///           COUNTRY_ISO                ISO 3166-1 numeric (840 = US)
///           BD_CLAIM_ISSUER            BD ClaimIssuer ONCHAINID
///           TA_CLAIM_ISSUER            TA ClaimIssuer ONCHAINID
///           ADMIN                      DEFAULT_ADMIN_ROLE on Token / owner of registries
///           IDENTITY_REGISTRY
///           IDENTITY_REGISTRY_STORAGE
///           CLAIM_TOPICS_REGISTRY
///           TRUSTED_ISSUERS_REGISTRY
///           MODULAR_COMPLIANCE
///           FACTORY                    pre-deployed SecurityTokenFactory
///
/// @dev    Build + dry-run only — never use `--broadcast` from this script
///         in code review tasks. On-chain deploys go through `~/work/liquidity/operator`.
contract DeploySecurityTokenStack is Script {
    function run() external {
        SecurityTokenFactory factory = SecurityTokenFactory(vm.envAddress("FACTORY"));

        SecurityTokenFactory.Components memory comp = SecurityTokenFactory.Components({
            identityRegistry:        IIdentityRegistry(vm.envAddress("IDENTITY_REGISTRY")),
            identityRegistryStorage: IIdentityRegistryStorage(vm.envAddress("IDENTITY_REGISTRY_STORAGE")),
            claimTopicsRegistry:     IClaimTopicsRegistry(vm.envAddress("CLAIM_TOPICS_REGISTRY")),
            trustedIssuersRegistry:  ITrustedIssuersRegistry(vm.envAddress("TRUSTED_ISSUERS_REGISTRY")),
            modularCompliance:       IModularCompliance(vm.envAddress("MODULAR_COMPLIANCE"))
        });

        SecurityTokenFactory.Params memory p = SecurityTokenFactory.Params({
            name:           vm.envString("NAME"),
            symbol:         vm.envString("SYMBOL"),
            decimals:       uint8(vm.envUint("DECIMALS")),
            offering:       vm.envBytes32("OFFERING"),
            countryISO:     uint16(vm.envUint("COUNTRY_ISO")),
            bdClaimIssuer:  vm.envAddress("BD_CLAIM_ISSUER"),
            taClaimIssuer:  vm.envAddress("TA_CLAIM_ISSUER"),
            admin:          vm.envAddress("ADMIN"),
            components:     comp
        });

        vm.startBroadcast();
        SecurityTokenFactory.Deployment memory d = factory.deploy(p);
        vm.stopBroadcast();

        console.log("token              :", address(d.token));
        console.log("documentRegistry   :", address(d.documentRegistry));
        console.log("identityRegistry   :", address(d.components.identityRegistry));
        console.log("identityRegistrySto:", address(d.components.identityRegistryStorage));
        console.log("claimTopicsRegistry:", address(d.components.claimTopicsRegistry));
        console.log("trustedIssuersReg. :", address(d.components.trustedIssuersRegistry));
        console.log("modularCompliance  :", address(d.components.modularCompliance));
    }
}
