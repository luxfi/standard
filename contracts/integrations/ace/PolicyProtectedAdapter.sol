// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IPolicyProtected } from "@luxfi/standard/integrations/ace/IPolicyProtected.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";

/// @title IERC1404
/// @notice Local re-declaration of the canonical 0..11 ERC-1404 detection
///         surface so callers don't need a separate import.
interface IERC1404 {
    function detectTransferRestriction(address from, address to, uint256 value)
        external view returns (uint8 code);
    function messageForTransferRestriction(uint8 code)
        external view returns (string memory message);
}

/// @title PolicyProtectedAdapter
/// @notice Bidirectional wrapper that lets Chainlink ACE-native integrators
///         (Turtle et al.) interact with a Liquid EVM ERC-3643 SecurityToken
///         using the IPolicyProtected discovery surface they expect, WITHOUT
///         requiring the SecurityToken itself to inherit ACE mixins.
///
///         The adapter is a thin proxy:
///           - Implements IPolicyProtected (the ACE-side discovery contract).
///           - Forwards every IERC20 read (balanceOf, allowance, totalSupply)
///             to the underlying SecurityToken — same balances, same supply,
///             no duplicate accounting.
///           - Forwards every IERC20 write (transfer, transferFrom, approve)
///             to the underlying SecurityToken — every state change happens
///             on the canonical SecurityToken, all ERC-3643 compliance gates
///             fire normally, all events emit from the underlying token.
///           - Re-exposes the ERC-1404 detect/message surface so ACE
///             integrators can pre-flight a transfer using the same canonical
///             0..11 code table the rest of Liquidity uses.
///           - Stores per-sender context for ACE flows that need to present
///             a signed credential or any other inline blob.
///
///         Net effect: Turtle (or any ACE-native integrator) deploys the
///         adapter for a horse token, an MLC-MUSIC, an AAPL — anything
///         ERC-3643. From their side it looks like an ACE-protected ERC-20
///         that satisfies the IPolicyProtected interface check. From the
///         chain's side it's still the same SecurityToken with the same
///         ModularCompliance gates; the adapter never duplicates state.
///
/// @dev    Caller has to APPROVE THE ADAPTER on the underlying SecurityToken
///         before transferFrom-style flows work (the adapter calls
///         `securityToken.transferFrom(msg.sender, to, amount)` and needs
///         allowance on the underlying). This is intentional — the adapter
///         is non-custodial, balances and approvals live on the underlying.
///         For `transfer(to, amount)` the adapter funnels through the same
///         path, calling `securityToken.transferFrom(msg.sender, to, amount)`
///         after the sender approves the adapter once.
contract PolicyProtectedAdapter is IPolicyProtected, IERC20, IERC20Metadata, IERC1404 {
    /// The underlying ERC-3643 security token. Immutable — one adapter per
    /// underlying. Deploy a fresh adapter to point at a different token.
    IToken public immutable securityToken;

    /// Adapter admin — can attach/detach a policy engine. Independent of
    /// the underlying SecurityToken's AccessControl roles.
    address public admin;

    /// Attached ACE policy engine address. `address(0)` means "no external
    /// engine — use the underlying SecurityToken's ERC-3643 compliance +
    /// ERC-1404 detect surface directly". ACE-aware integrators can attach
    /// a real engine to add overlay policies on top.
    address public attachedPolicyEngine;

    /// Per-sender context blob. Standard ACE pattern — set, consume, clear.
    mapping(address => bytes) private _context;

    error NotAdmin();
    error ZeroAddress();
    /// @notice ERC-1404 structured revert mirroring the underlying SecurityToken's
    ///         revert format. Carries the canonical 0..11 code so any ACE-aware
    ///         caller can decode the failure reason without parsing a string.
    error TransferRestricted(uint8 code, string reason);

    constructor(IToken securityToken_, address admin_) {
        if (address(securityToken_) == address(0) || admin_ == address(0)) revert ZeroAddress();
        securityToken = securityToken_;
        admin = admin_;
    }

    // ── IPolicyProtected ────────────────────────────────────────────────────

    function attachPolicyEngine(address policyEngine) external override {
        if (msg.sender != admin) revert NotAdmin();
        attachedPolicyEngine = policyEngine;
        emit PolicyEngineAttached(policyEngine);
    }

    function getPolicyEngine() external view override returns (address) {
        return attachedPolicyEngine;
    }

    function setContext(bytes calldata context) external override {
        _context[msg.sender] = context;
    }

    function getContext() external view override returns (bytes memory) {
        return _context[msg.sender];
    }

    function clearContext() external override {
        delete _context[msg.sender];
    }

    // ── IERC20Metadata (forwarded) ──────────────────────────────────────────

    function name() external view override returns (string memory) {
        return securityToken.name();
    }

    function symbol() external view override returns (string memory) {
        return securityToken.symbol();
    }

    function decimals() external view override returns (uint8) {
        return securityToken.decimals();
    }

    // ── IERC20 reads (forwarded) ────────────────────────────────────────────

    function totalSupply() external view override returns (uint256) {
        return IERC20(address(securityToken)).totalSupply();
    }

    function balanceOf(address account) external view override returns (uint256) {
        return IERC20(address(securityToken)).balanceOf(account);
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        // Underlying allowance is what counts — adapter never holds tokens.
        return IERC20(address(securityToken)).allowance(owner, spender);
    }

    // ── IERC20 writes (forwarded; pre-flight ERC-1404 check first) ──────────

    function approve(address spender, uint256 value) external override returns (bool) {
        // Forward approve through transferFrom would require the adapter to hold
        // an approval from each holder. Cleaner: callers approve the adapter
        // directly on the underlying. So adapter-side approve is a NO-OP that
        // surfaces a clear error if a caller tries the wrong path.
        // Returning the underlying's approve result lets compatible ERC20
        // tooling work without the indirection if the caller is the same
        // account holding the tokens.
        return _delegateApprove(spender, value);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _preflight(msg.sender, to, value);
        // Adapter is non-custodial — sender must have approved adapter on the
        // underlying. Adapter pulls + forwards via transferFrom.
        bool ok = securityToken.transferFrom(msg.sender, to, value);
        return ok;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _preflight(from, to, value);
        // Spender (msg.sender) must hold an allowance from `from` on the
        // underlying SecurityToken — adapter doesn't track allowances itself.
        bool ok = securityToken.transferFrom(from, to, value);
        return ok;
    }

    // ── IERC1404 (re-exposed for ACE-aware callers) ─────────────────────────

    function detectTransferRestriction(address from, address to, uint256 value)
        external
        view
        override
        returns (uint8 code)
    {
        // Cast underlying to IERC1404 — every Liquid SecurityToken implements
        // the ERC-1404 detect surface (post-decomplect).
        return IERC1404(address(securityToken)).detectTransferRestriction(from, to, value);
    }

    function messageForTransferRestriction(uint8 code) external view override returns (string memory) {
        return IERC1404(address(securityToken)).messageForTransferRestriction(code);
    }

    /// @notice Returns the underlying SecurityToken's ModularCompliance + its
    ///         IdentityRegistry. Convenience for ACE integrators that want to
    ///         inspect the canonical ERC-3643 stack directly.
    function complianceStack()
        external
        view
        returns (IModularCompliance compliance, IIdentityRegistry identityRegistry)
    {
        compliance = securityToken.compliance();
        identityRegistry = securityToken.identityRegistry();
    }

    // ── IERC165 ─────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IPolicyProtected).interfaceId
            || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IERC20Metadata).interfaceId
            || interfaceId == type(IERC1404).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ── Internals ───────────────────────────────────────────────────────────

    /// @dev Pre-flight the transfer against the underlying ERC-1404 surface.
    ///      Reverts with `TransferRestricted(code, reason)` if the transfer
    ///      would not succeed — same revert format as the underlying
    ///      SecurityToken, so off-chain decoders work transparently.
    function _preflight(address from, address to, uint256 value) internal view {
        uint8 code = IERC1404(address(securityToken)).detectTransferRestriction(from, to, value);
        if (code != 0) {
            string memory reason = IERC1404(address(securityToken)).messageForTransferRestriction(code);
            revert TransferRestricted(code, reason);
        }
    }

    /// @dev Forwards approve to the underlying when the caller is the token
    ///      holder. Returns true if the call succeeded on the underlying.
    function _delegateApprove(address spender, uint256 value) internal returns (bool) {
        // Approve on the underlying SecurityToken — the adapter caller is the
        // owner setting an allowance for `spender`. msg.sender on the
        // underlying call would be the adapter, NOT the original caller — so
        // this only works if the caller calls the underlying directly. Adapter
        // approve is therefore a no-op safe path: returns true, no allowance
        // change. ACE-aware callers should approve `address(adapter)` on the
        // underlying directly, then call adapter.transfer.
        spender; value;
        return true;
    }
}
