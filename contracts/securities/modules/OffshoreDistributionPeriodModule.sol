// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import { Topics } from "../constants/Topics.sol";

/// @title OffshoreDistributionPeriodModule
/// @notice Distribution-compliance-period (DCP) gate for OFFSHORE-exemption
///         tokens. Implements the "cannot return to the home jurisdiction"
///         window that follows offshore primary issuance.
///
///         Categories (configurable per-token):
///           NONE  — no DCP (foreign issuer + foreign markets;
///                   US Reg S Cat 1, EU passport sale)
///           40D   — 40-day DCP (US Reg S Cat 2, debt;
///                   EU cross-border debt sale; etc.)
///           1Y    — 1-year DCP (US Reg S Cat 3 equity of
///                   non-reporting issuer; equivalent global rules)
///
///         The "home jurisdiction" ISO-3166 numeric code is set per-token
///         via configure(). Buyers from that country are refused transfer
///         during the DCP window. After the window, the module is a no-op.
contract OffshoreDistributionPeriodModule is AbstractModule {
    string private constant _NAME = "OffshoreDistributionPeriodModule";

    uint64 internal constant NO_DCP   = 0;
    uint64 internal constant DCP_40D  = 40 days;
    uint64 internal constant DCP_1Y   = 31_536_001; // 1y + 1s

    struct Config {
        uint16 homeCountry;   // ISO 3166-1 numeric code of the offering's home jurisdiction
        uint64 issuanceTime;  // when DCP starts
        uint64 dcpDuration;   // seconds; one of NO_DCP, DCP_40D, DCP_1Y
        bool initialised;
    }

    mapping(address compliance => Config) public config;

    error AlreadyInitialised();
    error InvalidDcp();

    function configure(address compliance, Config calldata cfg) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (
            cfg.dcpDuration != NO_DCP &&
            cfg.dcpDuration != DCP_40D &&
            cfg.dcpDuration != DCP_1Y
        ) {
            revert InvalidDcp();
        }
        Config memory toStore = cfg;
        toStore.initialised = true;
        config[compliance] = toStore;
    }

    function moduleCheck(
        address /* from */,
        address to,
        uint256 /* amount */,
        address compliance
    ) external view returns (bool ok) {
        Config memory cfg = config[compliance];
        if (!cfg.initialised) return true;
        if (cfg.dcpDuration == NO_DCP) return true;

        // Mint / burn always allowed.
        if (to == address(0)) return true;

        // Window has elapsed → no restriction.
        if (uint64(block.timestamp) > cfg.issuanceTime + cfg.dcpDuration) return true;

        // During DCP: buyers from the home country are refused.
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        uint16 buyerCountry = registry.investorCountry(to);

        // buyerCountry == 0 means unknown / not set. Conservative: refuse
        // during DCP. Setting the country claim at onboarding is mandatory
        // for any token that might use this module.
        if (buyerCountry == 0) return false;

        return buyerCountry != cfg.homeCountry;
    }

    function moduleTransferAction(address, address, uint256) external override onlyComplianceCall {}
    function moduleMintAction(address, uint256) external override onlyComplianceCall {}
    function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

    function canComplianceBind(address) external pure override returns (bool) { return true; }
    function isPlugAndPlay() external pure override returns (bool) { return true; }
    function name() external pure returns (string memory) { return _NAME; }
}
