// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import { IIdentity } from "@luxfi/standard/securities/onchainid/interface/IIdentity.sol";
import { Topics } from "../constants/Topics.sol";

/// @title  Rule144LockupModule
/// @notice Canonical ERC-3643 IModule for SEC Rule 144 — holding period
///         (§144(d)) plus affiliate volume cap (§144(e)). Configurable so
///         every Rule 144 variant a securities token may need is
///         expressible without forking the module.
///
/// @dev    Decomplected: one source of truth for the rule, fully
///         per-compliance configurable. Concerns are kept separate:
///
///         (1) Holding-period clock — `holdingPeriod` per-compliance.
///             Anchored at `firstAcquired[compliance][holder]`, set on
///             the FIRST inbound transfer (mint OR receive). Carries
///             forward through chain-of-custody per §144(d) tacking.
///             Default `DEFAULT_HOLDING_PERIOD = 31_536_001` (1y + 1s)
///             — the strict +1 second tiebreaker that removes the
///             inclusive/exclusive day-365 ambiguity where SEC and
///             FINRA counsel split. A reporting issuer can set 6 months
///             via configure; a token not subject to §144 at all (e.g.
///             a public-registered token) sets `holdingPeriod = 0`.
///
///         (2) Global pre-IPO lockup — `unlockTimestamp` per-compliance.
///             When non-zero, no non-treasury transfer is allowed
///             before this timestamp regardless of individual holding
///             periods. Used for the founders' lock at IPO + the
///             standard 180-day post-IPO lockup. 0 disables.
///
///         (3) Affiliate volume cap — `affiliateVolumeCapBps` +
///             `affiliateWindow` per-compliance. A holder carrying the
///             AFFILIATE (topic 6) claim may not sell more than
///             `affiliateVolumeCapBps` basis-points of total supply
///             within any rolling `affiliateWindow`. Default cap is
///             100 bps (1% of supply per §144(e)(1)). Default window
///             is 90 days (the §144(e) 3-month aggregate cap). Setting
///             cap = 0 disables the volume gate.
///
///         (4) Treasury bypass — `issuerTreasury` per-compliance.
///             Transfers TO the issuer treasury (buybacks,
///             share-repurchase, redemptions) skip the holding-period
///             AND the affiliate volume gate. Setting 0 disables.
///
///         Per-(compliance, holder) state is keyed on the compliance
///         address so one module deployment can serve N security tokens.
contract Rule144LockupModule is AbstractModule {
    // ── constants ─────────────────────────────────────────────────────────

    /// @notice Default §144(d) holding period — 1 Gregorian year + 1 second.
    ///         Strict (>365d). See dev notes for the rationale on the +1s
    ///         tiebreaker.
    uint64 public constant DEFAULT_HOLDING_PERIOD = 31_536_001;

    /// @notice Default affiliate-sale rolling window — 90 days
    ///         (§144(e) three-month aggregate cap).
    uint64 public constant DEFAULT_AFFILIATE_WINDOW = 90 days;

    /// @notice Default affiliate volume cap — 100 bps (1%) of supply.
    uint16 public constant DEFAULT_AFFILIATE_CAP_BPS = 100;

    string private constant _NAME = "Rule144LockupModule";

    /// ERC-1404 reason codes returned by `moduleReason`.
    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_LOCKED = 8;
    uint8 internal constant CODE_AFFILIATE_LIMIT = 10;

    // ── storage ───────────────────────────────────────────────────────────

    /// @notice Per-compliance configuration.
    struct Config {
        /// @notice Address that may receive transfers regardless of any
        ///         holding-period or affiliate gate (issuer buybacks /
        ///         redemptions). 0 disables.
        address issuerTreasury;
        /// @notice Per-receipt holding period (seconds). 0 disables the
        ///         per-holder lockup. Defaulted to DEFAULT_HOLDING_PERIOD
        ///         on configure() when the caller passes 0 AND wants the
        ///         default — see `configure` semantics below.
        uint64 holdingPeriod;
        /// @notice Global pre-IPO lockup timestamp. Until this time, no
        ///         non-treasury transfer is allowed. 0 disables.
        uint64 unlockTimestamp;
        /// @notice Rolling window for the affiliate sale cap. Defaulted
        ///         to DEFAULT_AFFILIATE_WINDOW on configure() when 0.
        uint64 affiliateWindow;
        /// @notice Cap (basis points of total supply) on affiliate sales
        ///         per rolling `affiliateWindow`. Defaulted to
        ///         DEFAULT_AFFILIATE_CAP_BPS on configure() when 0.
        ///         Setting cap to type(uint16).max (65535 ≡ 655.35%)
        ///         effectively disables the gate.
        uint16 affiliateVolumeCapBps;
        /// @notice Init guard.
        bool initialised;
    }

    /// @notice Per-compliance config.
    mapping(address compliance => Config) public config;

    /// @notice First-time-received timestamp per (compliance, holder).
    ///         Anchored at the first inbound transfer; NEVER reset by
    ///         partial sales (so each chain-of-custody hop carries the
    ///         original clock forward, per §144(d) tacking).
    mapping(address compliance => mapping(address holder => uint64)) public firstAcquired;

    /// @notice Rolling-window affiliate sale total per (compliance, holder).
    mapping(address compliance => mapping(address holder => uint256)) public windowSold;

    /// @notice Start of the current rolling window per (compliance, holder).
    ///         Window rolls forward when the next sale falls AFTER
    ///         `windowStart + affiliateWindow`.
    mapping(address compliance => mapping(address holder => uint64)) public windowStart;

    // ── errors ────────────────────────────────────────────────────────────

    error AlreadyInitialised();
    error ComplianceNotBound();
    error NotIssuer();

    // ── events ────────────────────────────────────────────────────────────

    event Configured(
        address indexed compliance,
        address issuerTreasury,
        uint64 holdingPeriod,
        uint64 unlockTimestamp,
        uint64 affiliateWindow,
        uint16 affiliateVolumeCapBps
    );
    event IssuerTreasuryUpdated(address indexed compliance, address oldTreasury, address newTreasury);

    // ── configuration ─────────────────────────────────────────────────────

    /// @notice One-shot init by the compliance owner (TA agent).
    /// @dev    Zero in any of `holdingPeriod`, `affiliateWindow`,
    ///         `affiliateVolumeCapBps` resolves to the corresponding
    ///         DEFAULT_* constant. To truly disable a clock pass a
    ///         sentinel: `holdingPeriod = type(uint64).max` for "never
    ///         locked", `affiliateVolumeCapBps = type(uint16).max` for
    ///         "no affiliate cap".
    function configure(address compliance, Config calldata cfg) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (!this.isComplianceBound(compliance)) revert ComplianceNotBound();
        uint64 hp = cfg.holdingPeriod == 0 ? DEFAULT_HOLDING_PERIOD : cfg.holdingPeriod;
        if (hp == type(uint64).max) hp = 0; // sentinel: "no holding period"
        uint64 aw = cfg.affiliateWindow == 0 ? DEFAULT_AFFILIATE_WINDOW : cfg.affiliateWindow;
        uint16 cap = cfg.affiliateVolumeCapBps == 0 ? DEFAULT_AFFILIATE_CAP_BPS : cfg.affiliateVolumeCapBps;
        if (cap == type(uint16).max) cap = 0; // sentinel: "no affiliate cap"
        config[compliance] = Config({
            issuerTreasury: cfg.issuerTreasury,
            holdingPeriod: hp,
            unlockTimestamp: cfg.unlockTimestamp,
            affiliateWindow: aw,
            affiliateVolumeCapBps: cap,
            initialised: true
        });
        emit Configured(compliance, cfg.issuerTreasury, hp, cfg.unlockTimestamp, aw, cap);
    }

    /// @notice Convenience init: defaults for holdingPeriod (1y+1s),
    ///         affiliateWindow (90d), and affiliateVolumeCapBps (100=1%).
    ///         For full control (custom holding period, pre-IPO unlock
    ///         timestamp, alternative window/cap) use the Config-taking
    ///         overload above. Pass `affiliateVolumeCapBps = 0` to get
    ///         the 100bps default; pass `type(uint16).max` to disable
    ///         the volume gate entirely.
    function configure(address compliance, address issuerTreasury, uint16 affiliateVolumeCapBps) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (!this.isComplianceBound(compliance)) revert ComplianceNotBound();
        uint16 cap = affiliateVolumeCapBps == 0 ? DEFAULT_AFFILIATE_CAP_BPS : affiliateVolumeCapBps;
        if (cap == type(uint16).max) cap = 0;
        config[compliance] = Config({
            issuerTreasury: issuerTreasury,
            holdingPeriod: DEFAULT_HOLDING_PERIOD,
            unlockTimestamp: 0,
            affiliateWindow: DEFAULT_AFFILIATE_WINDOW,
            affiliateVolumeCapBps: cap,
            initialised: true
        });
        emit Configured(compliance, issuerTreasury, DEFAULT_HOLDING_PERIOD, 0, DEFAULT_AFFILIATE_WINDOW, cap);
    }

    /// @notice Rotate the issuer-treasury address. Compliance-owner only.
    function setIssuerTreasury(address compliance, address newTreasury) external {
        Config storage c = config[compliance];
        if (!c.initialised) revert ComplianceNotBound();
        if (msg.sender != c.issuerTreasury) revert NotIssuer();
        address old = c.issuerTreasury;
        c.issuerTreasury = newTreasury;
        emit IssuerTreasuryUpdated(compliance, old, newTreasury);
    }

    // ── IModule view checks ───────────────────────────────────────────────

    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return _reason(_from, _to, _value, _compliance) == CODE_OK;
    }

    function moduleReason(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        return _reason(_from, _to, _value, _compliance);
    }

    /// @dev Internal reason resolver. Order matters: treasury bypass
    ///      first (issuer buybacks must always work); then global
    ///      pre-IPO lockup; then per-holder holding period; then
    ///      affiliate volume cap.
    function _reason(address from, address to, uint256 value, address compliance)
        internal
        view
        returns (uint8)
    {
        Config memory cfg = config[compliance];
        if (!cfg.initialised) return CODE_OK;

        // Mints + burns: unconditional. They're driven by the issuer or
        // the user-initiated burn path; not Rule-144 events.
        if (from == address(0) || to == address(0)) return CODE_OK;

        // Treasury bypass — buybacks / share-repurchase never blocked.
        if (cfg.issuerTreasury != address(0) && to == cfg.issuerTreasury) return CODE_OK;

        // Global pre-IPO lockup.
        if (cfg.unlockTimestamp != 0 && block.timestamp < cfg.unlockTimestamp) {
            return CODE_LOCKED;
        }

        // Per-holder holding period. Strict `<` per the +1s tiebreaker:
        //   allowed when (now - acquired) >= holdingPeriod.
        if (cfg.holdingPeriod != 0) {
            uint64 acquired = firstAcquired[compliance][from];
            if (acquired != 0 && block.timestamp < uint256(acquired) + cfg.holdingPeriod) {
                return CODE_LOCKED;
            }
        }

        // Affiliate volume cap (§144(e)(1)).
        if (cfg.affiliateVolumeCapBps != 0 && _isAffiliate(compliance, from)) {
            uint256 cap = _volumeCap(compliance, cfg.affiliateVolumeCapBps);
            uint256 sold = _activeWindowSold(compliance, from, cfg.affiliateWindow);
            if (sold + value > cap) return CODE_AFFILIATE_LIMIT;
        }
        return CODE_OK;
    }

    // ── IModule state updates ─────────────────────────────────────────────

    /// @notice Anchor first-receipt timestamp on mint.
    function moduleMintAction(address _to, uint256) external override onlyComplianceCall {
        if (firstAcquired[msg.sender][_to] == 0) {
            firstAcquired[msg.sender][_to] = uint64(block.timestamp);
        }
    }

    /// @notice Update first-receipt + affiliate window on transfer.
    function moduleTransferAction(address _from, address _to, uint256 _value)
        external
        override
        onlyComplianceCall
    {
        // Recipient: anchor first-receipt if this is their first inbound
        // (chain-of-custody tacking per §144(d)).
        if (firstAcquired[msg.sender][_to] == 0) {
            firstAcquired[msg.sender][_to] = uint64(block.timestamp);
        }
        // Sender: if affiliate, advance the rolling window.
        Config memory cfg = config[msg.sender];
        if (cfg.affiliateVolumeCapBps != 0 && _isAffiliate(msg.sender, _from)) {
            uint64 ws = windowStart[msg.sender][_from];
            if (ws == 0 || block.timestamp >= uint256(ws) + cfg.affiliateWindow) {
                windowStart[msg.sender][_from] = uint64(block.timestamp);
                windowSold[msg.sender][_from] = _value;
            } else {
                windowSold[msg.sender][_from] += _value;
            }
        }
    }

    function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

    // ── helpers ────────────────────────────────────────────────────────────

    /// @dev capBps of current total supply (cap shrinks/grows with supply).
    function _volumeCap(address compliance, uint16 capBps) internal view returns (uint256) {
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        return (token.totalSupply() * uint256(capBps)) / 10_000;
    }

    /// @dev Active rolling-window sold; 0 when the window has elapsed.
    function _activeWindowSold(address compliance, address holder, uint64 windowSize)
        internal
        view
        returns (uint256)
    {
        uint64 ws = windowStart[compliance][holder];
        if (ws == 0) return 0;
        if (block.timestamp >= uint256(ws) + windowSize) return 0;
        return windowSold[compliance][holder];
    }

    /// @dev True iff `user` carries the AFFILIATE (topic 6) claim.
    function _isAffiliate(address compliance, address user) internal view returns (bool) {
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        IIdentity id = registry.identity(user);
        if (address(id) == address(0)) return false;
        bytes32[] memory ids = id.getClaimIdsByTopic(Topics.AFFILIATE);
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
