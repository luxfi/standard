// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";

/// @title HolderCapModule
/// @notice ERC-3643 compliance module that enforces a maximum unique-holder
///         count per token. Required for offerings with hard holder caps —
///         Reg D 506(b) (35 non-accredited holders), Reg CF (no cap, but
///         disclosure thresholds), various jurisdictional limits.
/// @dev    Tracks unique-holder count by hooking the `moduleTransferAction` /
///         `moduleMintAction` / `moduleBurnAction` callbacks. Increments when
///         a recipient was previously zero-balance; decrements when a sender
///         drains to zero. Pre-transfer check fails with code 9 (Holder cap
///         reached) if accepting the transfer would create a new holder past
///         the cap. Existing-holder receives never fail the cap (only NET-new
///         holders do).
contract HolderCapModule is AbstractModule {
    string private constant _NAME = "HolderCapModule";

    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_HOLDER_CAP_REACHED = 9;

    struct Config {
        uint256 cap; // 0 = unlimited; >0 = max unique holders
        uint256 count; // current unique-holder count
        bool initialised;
    }

    mapping(address compliance => Config) public config;
    /// Per-(compliance, holder) flag tracking whether the holder is currently
    /// counted. Toggled on transfer transitions (0 ↔ nonzero balance).
    mapping(address compliance => mapping(address holder => bool)) public isCountedHolder;

    event CapSet(address indexed compliance, uint256 cap);
    event HolderAdded(address indexed compliance, address indexed holder);
    event HolderRemoved(address indexed compliance, address indexed holder);

    error AlreadyInitialised();

    /// @notice Initialise the cap for a compliance. Callable once by the
    ///         compliance owner. Use `setCap` to mutate later.
    function configure(address compliance, uint256 cap_) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        if (config[compliance].initialised) revert AlreadyInitialised();
        config[compliance] = Config({cap: cap_, count: 0, initialised: true});
        emit CapSet(compliance, cap_);
    }

    /// @notice Mutate the cap after initialisation. Cap < current count is
    ///         allowed (existing holders are grandfathered; the next NEW
    ///         holder is just blocked until count drops below cap).
    function setCap(address compliance, uint256 cap_) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        require(config[compliance].initialised, "not initialised");
        config[compliance].cap = cap_;
        emit CapSet(compliance, cap_);
    }

    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return this.moduleReason(_from, _to, _value, _compliance) == CODE_OK;
    }

    /// @notice Returns code 9 (Holder cap reached) when accepting the transfer
    ///         would push the unique-holder count above the configured cap.
    ///         A recipient is "new" iff their current balance is zero and the
    ///         transfer amount is positive — the post-state would be a new
    ///         counted holder.
    function moduleReason(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        Config memory cfg = config[_compliance];
        // Unconfigured or unlimited → no gate.
        if (!cfg.initialised || cfg.cap == 0) return CODE_OK;
        // Burn (_to == 0) never creates a new holder.
        if (_to == address(0) || _value == 0) return CODE_OK;
        // Existing holder (already counted) → no new-holder transition.
        if (isCountedHolder[_compliance][_to]) return CODE_OK;
        // Recipient currently has nonzero balance but isn't counted (shouldn't
        // happen with correct hook wiring; treat as new-holder for safety).
        IToken securityToken = IToken(IModularCompliance(_compliance).getTokenBound());
        if (securityToken.balanceOf(_to) > 0) return CODE_OK;
        // New holder — would the cap be exceeded after this transfer?
        if (cfg.count >= cfg.cap) return CODE_HOLDER_CAP_REACHED;
        return CODE_OK;
    }

    function moduleTransferAction(address _from, address _to, uint256 _value) external override onlyComplianceCall {
        _updateHolder(msg.sender, _from, _to, _value);
    }

    function moduleMintAction(address _to, uint256 _value) external override onlyComplianceCall {
        _updateHolder(msg.sender, address(0), _to, _value);
    }

    function moduleBurnAction(address _from, uint256 _value) external override onlyComplianceCall {
        _updateHolder(msg.sender, _from, address(0), _value);
    }

    function _updateHolder(address compliance, address from, address to, uint256 value) internal {
        if (value == 0) return;
        Config storage cfg = config[compliance];
        if (!cfg.initialised) return;

        IToken securityToken = IToken(IModularCompliance(compliance).getTokenBound());

        // Recipient transitioned 0 → nonzero (became counted).
        if (to != address(0) && !isCountedHolder[compliance][to] && securityToken.balanceOf(to) > 0) {
            isCountedHolder[compliance][to] = true;
            unchecked { cfg.count++; }
            emit HolderAdded(compliance, to);
        }
        // Sender transitioned nonzero → 0 (no longer counted).
        if (from != address(0) && isCountedHolder[compliance][from] && securityToken.balanceOf(from) == 0) {
            isCountedHolder[compliance][from] = false;
            unchecked { cfg.count--; }
            emit HolderRemoved(compliance, from);
        }
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

    function _complianceOwner(address compliance) internal view returns (address) {
        (bool ok, bytes memory ret) = compliance.staticcall(abi.encodeWithSignature("owner()"));
        require(ok && ret.length >= 32, "owner() unavailable");
        return abi.decode(ret, (address));
    }
}
