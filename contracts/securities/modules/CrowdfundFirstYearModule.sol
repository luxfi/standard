// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import { IIdentity } from "@luxfi/standard/securities/onchainid/interface/IIdentity.sol";
import { Topics } from "../constants/Topics.sol";

/// @title CrowdfundFirstYearModule
/// @notice First-year transfer restriction for RETAIL_CROWDFUND tokens.
///         Implements the carve-out matrix common to retail-crowdfunding
///         exemptions globally (US Reg CF §4(a)(6), EU ECSP, UK FCA P2P,
///         AU CSF). During the first 12 months from token issuance,
///         transfers are blocked EXCEPT to:
///
///           - the issuer itself (buyback)
///           - any qualified investor (accredited / verified / institutional)
///           - immediate family of the holder (off-chain attested by issuer)
///           - in connection with a registered offering (re-registration)
///           - in connection with death / divorce (off-chain attested)
///
///         After day 366 the restriction lifts and standard ResaleModule
///         rules apply. The 12-month clock is anchored at the token's
///         issuance (per-token, not per-holder), recorded via
///         `configure(...)`.
///
///         Family + death/divorce + registered-offering exceptions are
///         signaled by issuer-set per-(holder→receiver) flags
///         (`setException`); the chain trusts the issuer's off-chain
///         determination but records the override for audit.
contract CrowdfundFirstYearModule is AbstractModule {
    string private constant _NAME = "CrowdfundFirstYearModule";

    uint64 internal constant FIRST_YEAR = 31_536_001; // 1 year + 1 second

    struct Config {
        address issuer; // the issuing entity's address — buybacks always allowed
        uint64 issuanceTime; // when the token was deemed issued (first sale)
        bool initialised;
    }

    mapping(address compliance => Config) public config;
    /// Per-(compliance, from, to) one-shot exception. Cleared on use.
    mapping(address compliance => mapping(address from => mapping(address to => bool))) public oneShotException;

    error AlreadyInitialised();
    error NotIssuer();

    function configure(address compliance, Config calldata cfg) external {
        if (config[compliance].initialised) revert AlreadyInitialised();
        Config memory toStore = cfg;
        toStore.initialised = true;
        config[compliance] = toStore;
    }

    /// @notice Issuer-only: grant a one-shot exception for a (from, to) pair.
    ///         Used to bless family transfers, death/divorce, and re-registered
    ///         offerings. Audited via event emission.
    function setException(address compliance, address from, address to, bytes32 reason) external {
        if (msg.sender != config[compliance].issuer) revert NotIssuer();
        oneShotException[compliance][from][to] = true;
        emit ExceptionGranted(compliance, from, to, reason);
    }

    event ExceptionGranted(address indexed compliance, address indexed from, address indexed to, bytes32 reason);
    event ExceptionConsumed(address indexed compliance, address indexed from, address indexed to);

    function moduleCheck(
        address from,
        address to,
        uint256 /* amount */,
        address compliance
    ) external view returns (bool ok) {
        Config memory cfg = config[compliance];
        if (!cfg.initialised) return true;

        // Mint / burn always allowed.
        if (from == address(0) || to == address(0)) return true;

        // Past the first year: this module no longer restricts; ResaleModule
        // takes over.
        if (uint64(block.timestamp) > cfg.issuanceTime + FIRST_YEAR) return true;

        // Buyback by issuer is always allowed.
        if (to == cfg.issuer) return true;

        // One-shot exception (family / death-divorce / re-registration).
        if (oneShotException[compliance][from][to]) return true;

        // Buyer-side qualified-investor check (Reg CF / EU ECSP / etc. all
        // permit transfers to accredited regardless of holding).
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry registry = token.identityRegistry();
        IIdentity buyerId = registry.identity(to);
        if (_hasFreshClaim(buyerId, Topics.ACCREDITED_VERIFIED)) return true;
        if (_hasFreshClaim(buyerId, Topics.ACCREDITED_SELF)) return true;
        if (_hasFreshClaim(buyerId, Topics.QIB)) return true;

        return false;
    }

    function moduleTransferAction(
        address from,
        address to,
        uint256 /* amount */
    ) external override onlyComplianceCall {
        if (oneShotException[msg.sender][from][to]) {
            delete oneShotException[msg.sender][from][to];
            emit ExceptionConsumed(msg.sender, from, to);
        }
    }

    function moduleMintAction(address, uint256) external override onlyComplianceCall {}
    function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

    function canComplianceBind(address) external pure override returns (bool) { return true; }
    function isPlugAndPlay() external pure override returns (bool) { return true; }
    function name() external pure returns (string memory) { return _NAME; }

    function _hasFreshClaim(IIdentity id, uint256 topic) internal view returns (bool) {
        if (address(id) == address(0)) return false;
        bytes32[] memory ids = id.getClaimIdsByTopic(topic);
        for (uint256 i = 0; i < ids.length; i++) {
            (uint256 t,,,,,) = id.getClaim(ids[i]);
            if (t == topic) return true;
        }
        return false;
    }
}
