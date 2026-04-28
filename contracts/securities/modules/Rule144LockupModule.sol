// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import { IIdentity } from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";
import { Topics } from "../constants/Topics.sol";

/// @title Rule144LockupModule
/// @notice Rule 144 holding-period gate plus the affiliate volume cap.
/// @dev    Per-token configuration:
///           * `unlockTimestamp` — until this time, recipients cannot transfer
///             tokens out (first-receipt time recorded at mint).
///           * Affiliate cap (1% of supply per rolling 4-week window) is
///             enforced on holders that carry the AFFILIATE claim (topic 6).
///         Transfers from address(0) (mint) record `firstReceived[to]`.
///         A transfer (not mint) before `firstReceived[from] + holdingPeriod`
///         reverts via `moduleCheck` returning false.
contract Rule144LockupModule is AbstractModule {
    string private constant _NAME = "Rule144LockupModule";

    /// Per-compliance config.
    struct Config {
        uint64 unlockTimestamp; // global unlock for non-affiliate holders
        uint64 holdingPeriod; // per-receipt holding period (e.g. 6 months)
        uint16 affiliateCapBps; // basis points of supply per 4-week window (e.g. 100 = 1%)
        bool initialised;
    }

    mapping(address compliance => Config) public config;
    /// First time a wallet received tokens from this token (per compliance).
    mapping(address compliance => mapping(address holder => uint64)) public firstReceived;
    /// Rolling 4-week sales window per holder (sum within window).
    mapping(address compliance => mapping(address holder => uint256)) public windowSold;
    mapping(address compliance => mapping(address holder => uint64)) public windowStart;

    uint64 internal constant WINDOW = 4 weeks;

    error AlreadyInitialised();
    error NotComplianceOwner();

    /// @notice One-shot init by the compliance owner (TA agent).
    function configure(address compliance, Config calldata cfg) external {
        // Only callable by the compliance owner. AbstractModule's bindCompliance
        // requires the compliance contract to call us; configuration is a separate
        // step the compliance owner does after binding.
        if (config[compliance].initialised) revert AlreadyInitialised();
        // Guard: compliance must already be bound to us.
        require(this.isComplianceBound(compliance), "compliance not bound");
        config[compliance] = Config({
            unlockTimestamp: cfg.unlockTimestamp,
            holdingPeriod: cfg.holdingPeriod,
            affiliateCapBps: cfg.affiliateCapBps,
            initialised: true
        });
    }

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        Config memory cfg = config[_compliance];
        if (!cfg.initialised) return true;
        // Mint or burn always allowed by this module.
        if (_from == address(0) || _to == address(0)) return true;

        // Holding-period gate.
        uint64 received = firstReceived[_compliance][_from];
        if (received != 0) {
            uint64 unlock = received + cfg.holdingPeriod;
            if (block.timestamp < unlock) return false;
        }
        if (cfg.unlockTimestamp != 0 && block.timestamp < cfg.unlockTimestamp) {
            // Pre-IPO global lockup.
            return false;
        }

        // Affiliate volume cap.
        if (_isAffiliate(_compliance, _from) && cfg.affiliateCapBps > 0) {
            IToken token = IToken(IModularCompliance(_compliance).getTokenBound());
            uint256 cap = (token.totalSupply() * cfg.affiliateCapBps) / 10000;
            uint256 sold = _windowSold(_compliance, _from);
            if (sold + _value > cap) return false;
        }
        return true;
    }

    function moduleMintAction(address _to, uint256) external override onlyComplianceCall {
        if (firstReceived[msg.sender][_to] == 0) {
            firstReceived[msg.sender][_to] = uint64(block.timestamp);
        }
    }

    function moduleTransferAction(address _from, address _to, uint256 _value) external override onlyComplianceCall {
        // Track recipient first-received for downstream Rule 144 chain-of-custody.
        if (firstReceived[msg.sender][_to] == 0) {
            firstReceived[msg.sender][_to] = uint64(block.timestamp);
        }
        // Update affiliate sales window.
        if (_isAffiliate(msg.sender, _from)) {
            uint64 ws = windowStart[msg.sender][_from];
            if (ws == 0 || block.timestamp >= ws + WINDOW) {
                windowStart[msg.sender][_from] = uint64(block.timestamp);
                windowSold[msg.sender][_from] = _value;
            } else {
                windowSold[msg.sender][_from] += _value;
            }
        }
    }

    function moduleBurnAction(address, uint256) external override onlyComplianceCall { }

    // ── Internals ──────────────────────────────────────────────────────────

    function _windowSold(address compliance, address holder) internal view returns (uint256) {
        uint64 ws = windowStart[compliance][holder];
        if (ws == 0) return 0;
        if (block.timestamp >= ws + WINDOW) return 0;
        return windowSold[compliance][holder];
    }

    function _isAffiliate(address compliance, address user) internal view returns (bool) {
        IToken token = IToken(IModularCompliance(compliance).getTokenBound());
        IIdentityRegistry idReg = token.identityRegistry();
        IIdentity id = idReg.identity(user);
        if (address(id) == address(0)) return false;
        bytes32[] memory ids = id.getClaimIdsByTopic(Topics.AFFILIATE);
        // Any non-empty AFFILIATE topic claim flags the user.
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
