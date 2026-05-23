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

/// @title  RegCFFirstYearModule
/// @notice ERC-3643 IModule implementing the Reg CF §227.501 12-month
///         resale restriction. Per Securities Act §4(a)(6) and the
///         implementing rules in 17 CFR §227.501, securities sold in a
///         crowdfunding offering may NOT be resold by the original
///         primary subscriber within 12 months of purchase, except to:
///
///           (a) the issuer of the securities;
///           (b) an "accredited investor" as defined in 17 CFR §230.501;
///           (c) a registered offering;
///           (d) a member of the family of the purchaser, or a trust
///               created for the benefit of a family member, in
///               connection with death or divorce.
///
///         On-chain we enforce (a) and (b) automatically. Cases (c) and
///         (d) require an issuer-set per-(holder→receiver) exception
///         flag, since they depend on off-chain evidence (offering
///         registration, marriage certificate, death certificate).
///
///         The 365-day clock runs from each PRIMARY SUBSCRIPTION, not
///         from token issuance. Every primary buyer has their own
///         clock; a secondary buyer who is NOT a primary subscriber is
///         unrestricted (their seller bore the §227.501 risk; the
///         buyer is now free to re-sell at will, subject to all other
///         applicable resale rules — Rule 144, Rule 144A, etc.).
///
/// @dev    Distinguishing primary from secondary: at the moment of
///         primary sale, the BD funding portal issues a
///         REG_CF_SUBSCRIBER claim (Topics.REG_CF_SUBSCRIBER = 9) to
///         the buyer's OnchainID. The hook reads this claim at the
///         buyer-side of a transfer. On the next transfer attempt
///         FROM that wallet, the seller-side check sees the same
///         claim and applies the 12-month clock.
///
///         365-day constant: `SECONDS_PER_YEAR = 31_536_000`. This is
///         the strict 365-day clock — distinct from the
///         `Rule144LockupModule` 1y+1s constant used for the SEC
///         Rule 144(d) holding period. The two constants represent
///         two different regulatory clocks; they must not be conflated.
contract RegCFFirstYearModule is AbstractModule {
    // ── constants ─────────────────────────────────────────────────────────

    /// @notice 365 days in seconds. Strict Reg CF §227.501 clock.
    uint64 public constant SECONDS_PER_YEAR = 31_536_000;

    string private constant _NAME = "RegCFFirstYearModule";

    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_REGCF_LOCKUP = 9;

    // ── storage ───────────────────────────────────────────────────────────

    /// @notice Per-compliance config.
    struct Config {
        /// @notice Issuer treasury address — always allowed as a transfer
        ///         destination per §227.501(a).
        address issuerTreasury;
        bool initialised;
    }

    /// @notice Per-compliance config.
    mapping(address compliance => Config) public config;

    /// @notice Per-(compliance, subscriber) timestamp of primary
    ///         subscription. Recorded automatically via
    ///         `moduleMintAction` when the mint recipient carries
    ///         the REG_CF_SUBSCRIBER claim at the moment of the mint.
    mapping(address compliance => mapping(address subscriber => uint64)) public subscribedAt;

    /// @notice One-shot exceptions per (compliance, from, to). Used by
    ///         issuer for (c) registered-offering re-issuance and (d)
    ///         death/divorce/family transfers. Consumed on first use.
    mapping(
        address compliance
            => mapping(address from => mapping(address to => bool))
    ) public oneShotException;

    // ── errors ────────────────────────────────────────────────────────────

    error AlreadyInitialised();
    error ComplianceNotBound();
    error NotIssuer();

    // ── events ────────────────────────────────────────────────────────────

    event Configured(address indexed compliance, address issuerTreasury);
    event PrimarySubscribed(address indexed compliance, address indexed subscriber, uint64 at);
    event ExceptionGranted(
        address indexed compliance,
        address indexed from,
        address indexed to,
        bytes32 reason
    );
    event ExceptionConsumed(address indexed compliance, address indexed from, address indexed to);

    // ── configuration ─────────────────────────────────────────────────────

    function configure(address compliance, address issuerTreasury) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (!this.isComplianceBound(compliance)) revert ComplianceNotBound();
        config[compliance] = Config({issuerTreasury: issuerTreasury, initialised: true});
        emit Configured(compliance, issuerTreasury);
    }

    /// @notice Issuer-only: grant a one-shot exception for a (from, to) pair.
    ///         Audited via `ExceptionGranted` event; `reason` is a free-form
    ///         bytes32 tag the issuer uses to label the cause
    ///         (e.g. keccak256("DEATH"), keccak256("REGISTERED_OFFERING")).
    function setException(address compliance, address from, address to, bytes32 reason) external {
        Config memory c = config[compliance];
        if (!c.initialised) revert ComplianceNotBound();
        if (msg.sender != c.issuerTreasury) revert NotIssuer();
        oneShotException[compliance][from][to] = true;
        emit ExceptionGranted(compliance, from, to, reason);
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
        return _check(from, to, compliance) ? CODE_OK : CODE_REGCF_LOCKUP;
    }

    function _check(address from, address to, address compliance) internal view returns (bool) {
        Config memory cfg = config[compliance];
        if (!cfg.initialised) return true;

        // Mint / burn always allowed.
        if (from == address(0) || to == address(0)) return true;

        // §227.501(a): transfers to the issuer always allowed.
        if (cfg.issuerTreasury != address(0) && to == cfg.issuerTreasury) return true;

        // (c) / (d) issuer-blessed one-shot exception.
        if (oneShotException[compliance][from][to]) return true;

        // If the SELLER is not a primary subscriber, this module imposes
        // no restriction.
        uint64 subAt = subscribedAt[compliance][from];
        if (subAt == 0) return true;

        // Primary subscriber inside the 12-month window: must transfer
        // to (a) issuer (covered above), (b) accredited buyer, or (c)/(d)
        // exception (covered above).
        if (block.timestamp < uint256(subAt) + SECONDS_PER_YEAR) {
            return _isAccreditedBuyer(compliance, to);
        }

        // Past 12 months: free.
        return true;
    }

    // ── IModule state updates ─────────────────────────────────────────────

    /// @notice Record primary subscription on mint if the recipient
    ///         carries the REG_CF_SUBSCRIBER claim.
    function moduleMintAction(address to, uint256) external override onlyComplianceCall {
        if (_hasPrimarySubscriberClaim(msg.sender, to) && subscribedAt[msg.sender][to] == 0) {
            subscribedAt[msg.sender][to] = uint64(block.timestamp);
            emit PrimarySubscribed(msg.sender, to, uint64(block.timestamp));
        }
    }

    /// @notice Consume one-shot exceptions on transfer.
    function moduleTransferAction(address from, address to, uint256)
        external
        override
        onlyComplianceCall
    {
        if (oneShotException[msg.sender][from][to]) {
            delete oneShotException[msg.sender][from][to];
            emit ExceptionConsumed(msg.sender, from, to);
        }
    }

    function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

    // ── helpers ────────────────────────────────────────────────────────────

    /// @dev True iff `wallet` carries the REG_CF_SUBSCRIBER claim on
    ///      their OnchainID.
    function _hasPrimarySubscriberClaim(address compliance, address wallet) internal view returns (bool) {
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        IIdentity id = registry.identity(wallet);
        if (address(id) == address(0)) return false;
        bytes32[] memory ids = id.getClaimIdsByTopic(Topics.REG_CF_SUBSCRIBER);
        return ids.length > 0;
    }

    /// @dev True iff `wallet` carries an accredited / QIB / REG_CF_SUBSCRIBER
    ///      claim — i.e., the buyer is one of the categories permitted as
    ///      a transferee under §227.501(b). REG_CF_SUBSCRIBER counts because
    ///      a primary subscriber in the same Reg CF offering is a permitted
    ///      transferee per §227.501 (they're already on the cap table under
    ///      the same exemption).
    function _isAccreditedBuyer(address compliance, address wallet) internal view returns (bool) {
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        IIdentity id = registry.identity(wallet);
        if (address(id) == address(0)) return false;
        if (id.getClaimIdsByTopic(Topics.ACCREDITED_VERIFIED).length > 0) return true;
        if (id.getClaimIdsByTopic(Topics.ACCREDITED_SELF).length > 0) return true;
        if (id.getClaimIdsByTopic(Topics.QIB).length > 0) return true;
        if (id.getClaimIdsByTopic(Topics.REG_CF_SUBSCRIBER).length > 0) return true;
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
