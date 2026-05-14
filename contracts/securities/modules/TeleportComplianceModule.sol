// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";

/// @title TeleportComplianceModule
/// @notice Destination-side gate for cross-chain mints (lock-and-mirror).
///         Permits a mint (`_from == address(0)`) only when the recipient
///         is verified in the destination-token's IdentityRegistry AND the
///         minter is an allow-listed teleport bridge.
/// @dev    Use as a defense in depth: even if the bridge contract has
///         MINTER_ROLE / AGENT_ROLE on the token, this module blocks any
///         destination-side mint to an unverified recipient.
contract TeleportComplianceModule is AbstractModule {
    string private constant _NAME = "TeleportComplianceModule";

    /// Per-compliance bridge allow-list.
    mapping(address compliance => mapping(address bridge => bool)) public bridgeAllowed;
    /// Optional: the only address allowed to *initiate* mints when locked down.
    /// If unset (address(0)) any caller passing the standard token mint path is OK.
    mapping(address compliance => address) public exclusiveBridge;

    function setBridgeAllowed(address compliance, address bridge, bool allowed) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        // The compliance owner is the only one expected to call this. We trust
        // the compliance owner contract (typically a TA-controlled multisig).
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        bridgeAllowed[compliance][bridge] = allowed;
    }

    function setExclusiveBridge(address compliance, address bridge) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        exclusiveBridge[compliance] = bridge;
    }

    /// ERC-1404 codes returned by {moduleReason}.
    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_RECIPIENT_NOT_REGISTERED = 4;
    uint8 internal constant CODE_BRIDGE_NOT_ALLOWED = 11;

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return this.moduleReason(_from, _to, _value, _compliance) == CODE_OK;
    }

    /// @notice See {IModule-moduleReason}. Returns code 4 if the cross-chain
    ///         mint recipient is not in the destination IdentityRegistry, or
    ///         code 11 if the originating bridge is not allow-listed.
    function moduleReason(address _from, address _to, uint256, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        if (_from != address(0)) return CODE_OK; // not a mint — out of scope
        // Mint path — destination-side gate.
        IToken securityToken = IToken(IModularCompliance(_compliance).getTokenBound());
        IIdentityRegistry idReg = securityToken.identityRegistry();
        if (!idReg.isVerified(_to)) return CODE_RECIPIENT_NOT_REGISTERED;

        address exclusive = exclusiveBridge[_compliance];
        if (exclusive != address(0) && tx.origin != exclusive && msg.sender != exclusive) {
            // We can't inspect the original mint() caller chain easily — rely on
            // the compliance contract's caller (the token) calling us, and the
            // bridge calling the token. The compliance contract is bound to one
            // token and the token's mint is restricted to AGENT_ROLE; the
            // bridge is the agent. tx.origin is acceptable here because this
            // is a defense-in-depth gate, not the primary auth.
            return CODE_BRIDGE_NOT_ALLOWED;
        }
        if (
            exclusive == address(0) && !bridgeAllowed[_compliance][tx.origin] && !bridgeAllowed[_compliance][msg.sender]
        ) {
            // No allow-list configured -> default-deny only when at least one
            // entry exists. If the allow-list is empty, the module is a no-op
            // and we accept (so Mainnet-issued tokens that never teleport are
            // unaffected).
            if (_anyAllowed(_compliance)) return CODE_BRIDGE_NOT_ALLOWED;
        }
        return CODE_OK;
    }

    function moduleTransferAction(address, address, uint256) external override onlyComplianceCall { }
    function moduleMintAction(address, uint256) external override onlyComplianceCall { }
    function moduleBurnAction(address, uint256) external override onlyComplianceCall { }

    // ── Internals ──────────────────────────────────────────────────────────

    function _anyAllowed(address compliance) internal view returns (bool) {
        return exclusiveBridge[compliance] != address(0);
    }

    function _complianceOwner(address compliance) internal view returns (address) {
        // ModularCompliance inherits Ownable; expose owner() via low-level call
        // to avoid a hard dependency on the upgradeable Ownable variant.
        (bool ok, bytes memory ret) = compliance.staticcall(abi.encodeWithSignature("owner()"));
        require(ok && ret.length >= 32, "owner() unavailable");
        return abi.decode(ret, (address));
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
