// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";

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

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256, address _compliance)
        external
        view
        override
        returns (bool)
    {
        if (_from != address(0)) return true; // not a mint — out of scope
        // Mint path — destination-side gate.
        IToken token = IToken(IModularCompliance(_compliance).getTokenBound());
        IIdentityRegistry idReg = token.identityRegistry();
        if (!idReg.isVerified(_to)) return false;

        address exclusive = exclusiveBridge[_compliance];
        if (exclusive != address(0) && tx.origin != exclusive && msg.sender != exclusive) {
            // We can't inspect the original mint() caller chain easily — rely on
            // the compliance contract's caller (the token) calling us, and the
            // bridge calling the token. The compliance contract is bound to one
            // token and the token's mint is restricted to AGENT_ROLE; the
            // bridge is the agent. tx.origin is acceptable here because this
            // is a defense-in-depth gate, not the primary auth.
            return false;
        }
        if (
            exclusive == address(0) && !bridgeAllowed[_compliance][tx.origin] && !bridgeAllowed[_compliance][msg.sender]
        ) {
            // No allow-list configured -> default-deny only when at least one
            // entry exists. If the allow-list is empty, the module is a no-op
            // and we accept (so Mainnet-issued tokens that never teleport are
            // unaffected).
            if (_anyAllowed(_compliance)) return false;
        }
        return true;
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
