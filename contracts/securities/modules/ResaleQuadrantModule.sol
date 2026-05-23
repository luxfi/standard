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

import {Rule144LockupModule} from "./Rule144LockupModule.sol";

/// @title  ResaleQuadrantModule
/// @notice The §4(a)(7) resale quadrant gate composed onto ModularCompliance.
///
///         2×2 matrix on (seller_accredited, buyer_accredited):
///
///         ┌──────────────────┬───────────────────┬───────────────────────┐
///         │ seller \ buyer   │ accredited        │ retail (non-acc)      │
///         ├──────────────────┼───────────────────┼───────────────────────┤
///         │ accredited       │ ALLOWED           │ Rule 144 lockup (1y+1s)│
///         │ retail (non-acc) │ Rule 144 lockup    │ Rule 144 + REG_S/CF   │
///         └──────────────────┴───────────────────┴───────────────────────┘
///
///         (acc, acc):     Free trade among accredited per §4(a)(7) safe
///                         harbor. No holding-period gate from this module.
///
///         (acc, non-acc): Seller must satisfy Rule 144(d) holding period
///                         (1y + 1s). Module delegates to
///                         `Rule144LockupModule.moduleCheck` rather than
///                         duplicating the math.
///
///         (non-acc, acc): Same — buyer-side accreditation alone does NOT
///                         excuse the seller's holding clock. This is
///                         conservative: §4(a)(7) safe harbor speaks to
///                         buyer-side qualification, but only the seller
///                         carries the resale risk under Rule 144(d).
///                         (Compare to `ResaleModule` in the standard
///                         library, which lets buyer-accredited trades
///                         pass even with a fresh seller clock — that
///                         is the alternative reading; the strict
///                         reading is here.)
///
///         (non-acc, non-acc): Rule 144 lockup PLUS the additional
///                         REG_S / REG_CF / qualifying-public-offering
///                         gate. By default this combination is REFUSED
///                         unless the token has been flagged
///                         `retailPublicAllowlisted` on this module.
///
/// @dev    "Accredited" includes ACCREDITED_VERIFIED (topic 3), QIB
///         (topic 5), and (when `requireVerifiedBuyer = false`)
///         ACCREDITED_SELF (topic 4). The default is to require
///         VERIFIED on the buyer side per the §4(a)(7) strict reading.
///
///         Module composition: This module DELEGATES holding-period math
///         to the `Rule144LockupModule` deployed at `rule144LockupAddr`.
///         Both modules MUST be bound to the same ModularCompliance for
///         the delegation to work. If `Rule144LockupModule` is not yet
///         configured for the compliance, this module degrades open
///         (returns true) for the holding-period part — the operator is
///         responsible for binding+configuring both modules together.
contract ResaleQuadrantModule is AbstractModule {
    string private constant _NAME = "ResaleQuadrantModule";

    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_RESALE_BLOCKED = 6;
    uint8 internal constant CODE_RESALE_HOLD = 8;

    // ── storage ───────────────────────────────────────────────────────────

    /// @notice Per-compliance config.
    struct Config {
        /// @notice Address of the bound `Rule144LockupModule` instance.
        ///         When zero, the seller-side Rule 144 check is skipped.
        Rule144LockupModule rule144;
        /// @notice If true, only ACCREDITED_VERIFIED (topic 3) or QIB
        ///         (topic 5) count on the buyer side; ACCREDITED_SELF
        ///         (topic 4) is treated as retail. Default for the
        ///         strict §4(a)(7) reading.
        bool requireVerifiedBuyer;
        /// @notice If true, this token is flagged as a retail-public-
        ///         allowlisted security (e.g. a Reg A Tier 2 token
        ///         that has cleared blue-sky and is publicly tradeable
        ///         on a US venue). Retail-to-retail is permitted in
        ///         that case (subject still to the Rule 144 clock).
        bool retailPublicAllowlisted;
        bool initialised;
    }

    mapping(address compliance => Config) public config;

    // ── errors ────────────────────────────────────────────────────────────

    error AlreadyInitialised();
    error ComplianceNotBound();

    // ── events ────────────────────────────────────────────────────────────

    event Configured(
        address indexed compliance,
        address rule144,
        bool requireVerifiedBuyer,
        bool retailPublicAllowlisted
    );

    // ── configuration ─────────────────────────────────────────────────────

    function configure(
        address compliance,
        Rule144LockupModule rule144,
        bool requireVerifiedBuyer,
        bool retailPublicAllowlisted
    ) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (!this.isComplianceBound(compliance)) revert ComplianceNotBound();
        config[compliance] = Config({
            rule144: rule144,
            requireVerifiedBuyer: requireVerifiedBuyer,
            retailPublicAllowlisted: retailPublicAllowlisted,
            initialised: true
        });
        emit Configured(compliance, address(rule144), requireVerifiedBuyer, retailPublicAllowlisted);
    }

    // ── IModule view checks ───────────────────────────────────────────────

    function moduleCheck(address from, address to, uint256 value, address compliance)
        external
        view
        override
        returns (bool)
    {
        return _reason(from, to, value, compliance) == CODE_OK;
    }

    function moduleReason(address from, address to, uint256 value, address compliance)
        external
        view
        override
        returns (uint8)
    {
        return _reason(from, to, value, compliance);
    }

    function _reason(address from, address to, uint256 value, address compliance)
        internal
        view
        returns (uint8)
    {
        Config memory cfg = config[compliance];
        if (!cfg.initialised) return CODE_OK;

        // Mint / burn unconditional.
        if (from == address(0) || to == address(0)) return CODE_OK;

        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        IIdentity sellerId = registry.identity(from);
        IIdentity buyerId = registry.identity(to);

        bool sellerAcc = _accredited(sellerId, cfg.requireVerifiedBuyer);
        bool buyerAcc = _accredited(buyerId, cfg.requireVerifiedBuyer);

        // Quadrant (acc, acc): always allowed.
        if (sellerAcc && buyerAcc) return CODE_OK;

        // Quadrants (acc, non-acc) and (non-acc, acc):
        //   Rule 144 seller-side lockup applies. The buyer-side
        //   accreditation does not lift the seller's holding clock.
        // Quadrant (non-acc, non-acc):
        //   Rule 144 lockup + additional retail-public allowlist gate.
        if (!sellerAcc && !buyerAcc) {
            // Retail-to-retail is blocked unless the token is allowlisted
            // for public retail trading AND the seller's holding period
            // has elapsed (checked below).
            if (!cfg.retailPublicAllowlisted) return CODE_RESALE_BLOCKED;
        }

        // Seller-side Rule 144 lockup. We re-use the existing Rule144LockupModule
        // rather than duplicating the holding-period math.
        if (address(cfg.rule144) != address(0)) {
            uint8 r = cfg.rule144.moduleReason(from, to, value, compliance);
            if (r != 0) return CODE_RESALE_HOLD;
        }
        return CODE_OK;
    }

    // ── IModule state updates ─────────────────────────────────────────────
    // This module is stateless w.r.t. transfer events — the bound
    // Rule144LockupModule is the authoritative state-keeper.

    function moduleTransferAction(address, address, uint256) external override onlyComplianceCall {}
    function moduleMintAction(address, uint256) external override onlyComplianceCall {}
    function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

    // ── helpers ────────────────────────────────────────────────────────────

    /// @dev True iff `id` carries any of the accreditation claims. When
    ///      `verifiedOnly` is true, ACCREDITED_SELF does not count
    ///      (only VERIFIED or QIB).
    function _accredited(IIdentity id, bool verifiedOnly) internal view returns (bool) {
        if (address(id) == address(0)) return false;
        if (id.getClaimIdsByTopic(Topics.ACCREDITED_VERIFIED).length > 0) return true;
        if (id.getClaimIdsByTopic(Topics.QIB).length > 0) return true;
        if (!verifiedOnly && id.getClaimIdsByTopic(Topics.ACCREDITED_SELF).length > 0) return true;
        return false;
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
