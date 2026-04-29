// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AccessControl } from "@luxfi/oz/access/AccessControl.sol";
import { ReentrancyGuard } from "@luxfi/oz/utils/ReentrancyGuard.sol";
import { ECDSA } from "@luxfi/oz/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@luxfi/oz/utils/cryptography/MessageHashUtils.sol";
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";

/// @title SecuritiesGateway
/// @notice Compliance-aware cross-chain bridge for ERC-3643 SecurityTokens.
///
/// One gateway per chain. Holds the T-REX `AGENT_ROLE` on every registered
/// SecurityToken so it can `mint` / `burn` directly. Crosses to and from any
/// destination chain (EVM and non-EVM alike) by emitting `Outbound` events
/// for an MPC oracle to relay, and accepting `Inbound` calls signed by that
/// oracle.
///
/// Recipients are `bytes32` so the same gateway carries:
///   - **EVM destinations** — recipient = `bytes32(uint256(uint160(addr)))`
///   - **Bitcoin / OP_NET** — recipient = Taproot x-only pubkey
///
/// Compliance:
///   - Outbound is callable by any holder. The user's tokens are burned via
///     `IToken.burn(user, amount)` (T-REX agent path), bypassing the
///     identity-registry check on transfers (the user already owns the
///     tokens — KYC was enforced at issuance, and OP_NET-side compliance
///     is the destination chain's responsibility).
///   - Inbound calls `IToken.mint(recipient, amount)` which itself reverts
///     unless `IIdentityRegistry.isVerified(recipient)` and
///     `IModularCompliance.canTransfer(0, recipient, amount)`. So digital
///     securities cannot be minted on-chain to an unverified recipient.
///     **This is the canonical compliance gate for the inbound side.**
///
/// Replay protection:
///   - `processedDeposits[srcChain][nonce]` prevents inbound replay.
///   - Outbound nonces are sequential per gateway, included in event.
///
/// Trust model:
///   - The gateway trusts the MPC group address (set by governor). The MPC
///     is responsible for honoring the source-chain finality requirements
///     (e.g. 6 BTC confirmations for OP_NET).
contract SecuritiesGateway is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ── Roles ─────────────────────────────────────────────────────────────

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // ── Constants ─────────────────────────────────────────────────────────

    /// @notice OP_NET virtual chain ID (Bitcoin L1 metaprotocol).
    uint64 public constant OPNET_CHAIN_ID = 4_294_967_299; // 0x100000003

    // ── Immutables ────────────────────────────────────────────────────────

    /// @notice This chain's ID (immutable, prevents cross-chain signature replay).
    uint64 public immutable chainId;

    // ── Mutable state ─────────────────────────────────────────────────────

    /// @notice MPC oracle group address (threshold-signed messages).
    address public mpcGroup;

    /// @notice Registered SecurityToken (must grant AGENT_ROLE to this contract).
    mapping(address => bool) public registeredTokens;

    /// @notice Processed inbound deposits — replay protection per (srcChain, nonce).
    mapping(uint64 => mapping(uint64 => bool)) public processedDeposits;

    /// @notice Sequential outbound counter (used as event nonce).
    uint64 public outboundNonce;

    /// @notice Pause flag (governor-only). Outbound burns are always allowed
    ///         (exit guarantee); inbound mints respect pause.
    bool public paused;

    // ── Events ────────────────────────────────────────────────────────────

    event Outbound(
        uint64 indexed destChain,
        uint64 indexed nonce,
        address indexed token,
        address sender,
        bytes32 recipient,
        uint256 amount
    );
    event Inbound(
        uint64 indexed srcChain, uint64 indexed nonce, address indexed token, address recipient, uint256 amount
    );
    event TokenRegistered(address indexed token);
    event TokenDeregistered(address indexed token);
    event MpcGroupUpdated(address indexed oldGroup, address indexed newGroup);
    event Paused(bool paused);

    // ── Errors ────────────────────────────────────────────────────────────

    error ZeroAddress();
    error ZeroAmount();
    error TokenNotRegistered(address token);
    error AlreadyRegistered(address token);
    error AlreadyProcessed(uint64 srcChain, uint64 nonce);
    error InvalidSignature();
    error IsPaused();

    // ── Constructor ───────────────────────────────────────────────────────

    constructor(uint64 _chainId, address _governor, address _mpcGroup) {
        if (_governor == address(0)) revert ZeroAddress();
        if (_mpcGroup == address(0)) revert ZeroAddress();
        chainId = _chainId;
        mpcGroup = _mpcGroup;
        _grantRole(DEFAULT_ADMIN_ROLE, _governor);
        _grantRole(GOVERNOR_ROLE, _governor);
    }

    // ── Outbound (any L1 → any destination, including OP_NET) ─────────────

    /// @notice Burn user's `amount` of SecurityToken and emit a teleport
    ///         message destined for `destChain` / `recipient`.
    /// @dev    Caller must hold the tokens. Bridge must hold the T-REX
    ///         AGENT_ROLE on the token (granted via `Token.addAgent`).
    ///         Recipient is `bytes32` so any chain shape works:
    ///           - EVM: `bytes32(uint256(uint160(recipientAddr)))`
    ///           - OP_NET / Bitcoin: 32-byte Taproot x-only pubkey
    function outbound(address token, uint256 amount, uint64 destChain, bytes32 recipient)
        external
        nonReentrant
        returns (uint64 nonce)
    {
        if (!registeredTokens[token]) revert TokenNotRegistered(token);
        if (amount == 0) revert ZeroAmount();
        if (recipient == bytes32(0)) revert ZeroAddress();

        IToken(token).burn(msg.sender, amount);

        unchecked {
            nonce = ++outboundNonce;
        }
        emit Outbound(destChain, nonce, token, msg.sender, recipient, amount);
    }

    // ── Inbound (any source, including OP_NET, → this chain) ──────────────

    /// @notice MPC-signed inbound mint. The mint itself enforces ERC-3643
    ///         compliance (recipient must be in the IIdentityRegistry).
    function inbound(
        uint64 srcChain,
        uint64 nonce,
        address token,
        address recipient,
        uint256 amount,
        bytes calldata mpcSignature
    ) external nonReentrant {
        if (paused) revert IsPaused();
        if (!registeredTokens[token]) revert TokenNotRegistered(token);
        if (amount == 0) revert ZeroAmount();
        if (processedDeposits[srcChain][nonce]) revert AlreadyProcessed(srcChain, nonce);

        bytes32 digest = keccak256(abi.encode("INBOUND", chainId, srcChain, nonce, token, recipient, amount));
        address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
        if (recovered != mpcGroup) revert InvalidSignature();

        processedDeposits[srcChain][nonce] = true;

        // T-REX: mint reverts unless recipient is verified by the IIdentityRegistry
        // and ModularCompliance.canTransfer(0, recipient, amount) is satisfied.
        IToken(token).mint(recipient, amount);

        emit Inbound(srcChain, nonce, token, recipient, amount);
    }

    // ── Views ─────────────────────────────────────────────────────────────

    /// @notice Convenience: query verification status on a token's registry.
    function isRecipientVerified(address token, address recipient) external view returns (bool) {
        if (!registeredTokens[token]) return false;
        IIdentityRegistry registry = IToken(token).identityRegistry();
        return registry.isVerified(recipient);
    }

    // ── Admin ─────────────────────────────────────────────────────────────

    function registerToken(address token) external onlyRole(GOVERNOR_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (registeredTokens[token]) revert AlreadyRegistered(token);
        registeredTokens[token] = true;
        emit TokenRegistered(token);
    }

    function deregisterToken(address token) external onlyRole(GOVERNOR_ROLE) {
        if (!registeredTokens[token]) revert TokenNotRegistered(token);
        registeredTokens[token] = false;
        emit TokenDeregistered(token);
    }

    function setMpcGroup(address newGroup) external onlyRole(GOVERNOR_ROLE) {
        if (newGroup == address(0)) revert ZeroAddress();
        emit MpcGroupUpdated(mpcGroup, newGroup);
        mpcGroup = newGroup;
    }

    function setPaused(bool p) external onlyRole(GOVERNOR_ROLE) {
        paused = p;
        emit Paused(p);
    }
}
