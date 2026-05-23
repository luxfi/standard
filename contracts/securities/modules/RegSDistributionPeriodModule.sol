// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import {AbstractModule} from
    "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import {IModularCompliance} from
    "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import {IToken} from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import {IIdentityRegistry} from
    "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import {IIdentity} from "@luxfi/standard/securities/onchainid/interface/IIdentity.sol";
import {Topics} from "../constants/Topics.sol";

/// @title  RegSDistributionPeriodModule
/// @notice Enforces SEC Reg S "distribution compliance period" (DCP).
///         During the DCP, securities sold offshore may only be
///         transferred among non-US persons. US persons cannot acquire
///         (or hold by transfer) Reg S securities during the period.
///         After the period elapses, the restriction lifts automatically.
///
///         Categories (17 CFR §230.903):
///
///           CATEGORY_1 — Foreign issuer, foreign markets. No DCP.
///                        Default for non-US issuers of equity/debt
///                        sold solely outside the US.
///           CATEGORY_2 — Reporting US issuer, or debt of any issuer.
///                        40-day DCP.
///           CATEGORY_3 — Non-reporting US issuer, equity.
///                        1-year (365-day) DCP.
///
///         The category is recorded per-compliance via `configure`. The
///         home-jurisdiction code (the country whose persons are
///         considered "US persons" for the offering — almost always 840
///         (US), but parametric to support EU/UK equivalents under MAR
///         offshore selling restrictions) is also per-compliance.
///
///         Buyer-side check: during the DCP, if the seller holds the
///         REG_S_NON_US (102) claim, the buyer must ALSO hold it OR
///         have a non-home-country `investorCountry` registration. The
///         seller-side claim is the trigger; the buyer-side check is
///         the gate.
///
/// @dev    SECONDS_PER_YEAR is 31_536_000 (strict 365d) for Category 3.
///         40 days is `40 * 86_400 = 3_456_000`. These are distinct from
///         Rule144LockupModule.HOLDING_PERIOD; do not collapse.
contract RegSDistributionPeriodModule is AbstractModule {
    // ── constants ─────────────────────────────────────────────────────────

    uint64 public constant CAT_NONE = 0;
    uint64 public constant CAT_1_DCP = 0; // explicit alias: Cat 1 has no DCP
    uint64 public constant CAT_2_DCP = 40 days; // 3_456_000s
    uint64 public constant CAT_3_DCP = 31_536_000; // 365 days

    /// @notice ISO-3166 numeric code for "United States" — the default
    ///         home jurisdiction. Configurable per-compliance for non-US
    ///         analogues (e.g. EU Reg S equivalents under MAR).
    uint16 public constant DEFAULT_HOME_COUNTRY_US = 840;

    string private constant _NAME = "RegSDistributionPeriodModule";

    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_REGS_DCP = 7;

    // ── storage ───────────────────────────────────────────────────────────

    /// @notice Per-compliance config.
    struct Config {
        /// @notice The ISO-3166 numeric code whose persons are excluded
        ///         from buying during the DCP (typically 840 = US).
        uint16 homeCountry;
        /// @notice Issuance timestamp — when the DCP clock starts.
        uint64 issuanceTime;
        /// @notice DCP duration in seconds. MUST be one of {0, 40 days,
        ///         365 days}.
        uint64 dcpDuration;
        bool initialised;
    }

    mapping(address compliance => Config) public config;

    // ── errors ────────────────────────────────────────────────────────────

    error AlreadyInitialised();
    error InvalidCategory();
    error ComplianceNotBound();

    // ── events ────────────────────────────────────────────────────────────

    event Configured(address indexed compliance, uint16 homeCountry, uint64 issuanceTime, uint64 dcpDuration);

    // ── configuration ─────────────────────────────────────────────────────

    function configure(address compliance, uint16 homeCountry, uint64 issuanceTime, uint64 dcpDuration) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (!this.isComplianceBound(compliance)) revert ComplianceNotBound();
        if (dcpDuration != CAT_NONE && dcpDuration != CAT_2_DCP && dcpDuration != CAT_3_DCP) {
            revert InvalidCategory();
        }
        config[compliance] = Config({
            homeCountry: homeCountry == 0 ? DEFAULT_HOME_COUNTRY_US : homeCountry,
            issuanceTime: issuanceTime == 0 ? uint64(block.timestamp) : issuanceTime,
            dcpDuration: dcpDuration,
            initialised: true
        });
        emit Configured(compliance, homeCountry, issuanceTime, dcpDuration);
    }

    // ── IModule view checks ───────────────────────────────────────────────

    function moduleCheck(address from, address to, uint256, address compliance)
        external
        view
        override
        returns (bool)
    {
        return _check(from, to, compliance);
    }

    function moduleReason(address from, address to, uint256, address compliance)
        external
        view
        override
        returns (uint8)
    {
        return _check(from, to, compliance) ? CODE_OK : CODE_REGS_DCP;
    }

    function _check(address from, address to, address compliance) internal view returns (bool) {
        Config memory cfg = config[compliance];
        if (!cfg.initialised) return true;
        if (cfg.dcpDuration == 0) return true; // Category 1: no DCP, always open

        // Mint / burn always allowed.
        if (from == address(0) || to == address(0)) return true;

        // DCP has elapsed → no restriction.
        if (block.timestamp >= uint256(cfg.issuanceTime) + cfg.dcpDuration) return true;

        // Inside DCP: the seller-side trigger is the REG_S_NON_US claim.
        // If the SELLER does not hold REG_S_NON_US, this module does not
        // restrict (the security wasn't acquired under Reg S to begin
        // with, so the offshore distribution gate doesn't apply).
        if (!_holdsRegS(compliance, from)) return true;

        // Seller holds REG_S_NON_US: buyer must ALSO hold REG_S_NON_US,
        // OR have a registered non-home-country investor country.
        if (_holdsRegS(compliance, to)) return true;

        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        uint16 buyerCountry = registry.investorCountry(to);

        // Unknown country: conservative reject during the DCP. The IDV
        // provider's JURISDICTION (topic 13) claim is mandatory for
        // any token that might land in this module's path; an unknown
        // country means we have no evidence the buyer is non-US.
        if (buyerCountry == 0) return false;
        return buyerCountry != cfg.homeCountry;
    }

    // ── IModule state updates ─────────────────────────────────────────────

    function moduleTransferAction(address, address, uint256) external override onlyComplianceCall {}
    function moduleMintAction(address, uint256) external override onlyComplianceCall {}
    function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

    // ── helpers ────────────────────────────────────────────────────────────

    function _holdsRegS(address compliance, address wallet) internal view returns (bool) {
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        IIdentity id = registry.identity(wallet);
        if (address(id) == address(0)) return false;
        bytes32[] memory ids = id.getClaimIdsByTopic(Topics.REG_S_NON_US);
        return ids.length > 0;
    }

    function canComplianceBind(address) external pure override returns (bool) {
        return true;
    }

    function isPlugAndPlay() external pure override returns (bool) {
        return true;
    }

    function name() external pure override returns (string memory) {
        return _NAME;
    }
}
