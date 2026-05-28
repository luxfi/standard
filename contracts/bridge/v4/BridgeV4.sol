// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IBridgedToken } from "../IBridgedToken.sol";
import { BasketRegistry } from "./BasketRegistry.sol";
import { P3Q_PRECOMPILE } from "./IP3QPrecompile.sol";
import { IZChainBridge } from "./IZChainBridge.sol";

/**
 * @title BridgeV4
 * @author Lux Industries
 * @notice Canonical post-quantum-default bridge entrypoint for the Lux network.
 *
 *  This replaces the V1 (Bridge.sol) and V2 (TeleportBridge.sol) entrypoints for
 *  new mints and redeems. V1/V2 stay deployed for back-compat reads on legacy
 *  vaults, but new flows MUST go through V4.
 *
 *  ─────────────────────────────────────────────────────────────────────────
 *  P3Q strict profile (default)
 *  ─────────────────────────────────────────────────────────────────────────
 *  V4 verifies Warp 2.0 envelopes by STATICCALLing the P3Q precompile at
 *  0x012205. This is the round-signer of Pulsar threshold sig × Prism
 *  commitment cut — see contract.RefuseUnderStrictPQ for the dispatch logic.
 *  Classical (ECDSA-only) envelopes are REFUSED by default.
 *
 *  Governance can opt into a classical-compat tail with enableClassicalCompat()
 *  for a fixed window (max 30 days, governance-only). When the window expires,
 *  classical envelopes start reverting again automatically — no manual undo.
 *
 *  ─────────────────────────────────────────────────────────────────────────
 *  Claim & redeem semantics
 *  ─────────────────────────────────────────────────────────────────────────
 *  claim(envelope, proof):
 *    1. Compute claimId = keccak256(envelope). Reject if used.
 *    2. STATICCALL P3Q with (envelope || proof). Reject if !valid AND
 *       not in classical-compat window.
 *    3. Decode envelope → (srcChain, srcTx, dstAsset, amount, recipient, nonce).
 *    4. Skim feeRateBps to feeReceiver. Mint (amount − fee) to recipient.
 *    5. Mark claimId used. Emit Claimed.
 *
 *  redeem(asset, amount, dstChain, dstAddr):
 *    1. Pull `amount` of `asset` from msg.sender via burn-with-allowance.
 *    2. Compute redeemHash = keccak256(asset, amount, dstChain, dstAddr, nonce).
 *    3. Emit RedeemRequested. Daemon-side broadcaster observes & signs on dst.
 *
 *  ─────────────────────────────────────────────────────────────────────────
 *  Role separation
 *  ─────────────────────────────────────────────────────────────────────────
 *    MPC_ROLE        — registers basket members at BasketRegistry; relays
 *                      legacy claims during classical-compat window
 *    GOVERNANCE_ROLE — toggles classical-compat, pauses, sets fee rate &
 *                      feeReceiver, sets zChainBridge, exits Recovery
 *    OPERATOR_ROLE   — drains accumulated fees from feeReceiver vault
 *
 *  Fees flow to a SEPARATE feeReceiver wallet (NOT the main vault) — privilege
 *  separation so an operator key compromise can't drain user funds.
 *
 *  ─────────────────────────────────────────────────────────────────────────
 *  Z-Chain hooks (zClaim, zRedeem)
 *  ─────────────────────────────────────────────────────────────────────────
 *  These mirror claim/redeem but route through a configured IZChainBridge.
 *  Revert ZChainNotConfigured if the bridge address is unset. Nullifier
 *  dedup is enforced at V4 level (nullifier set), proof verification is
 *  delegated to Z-Chain via the IZChainBridge interface.
 */
contract BridgeV4 is AccessControl, ReentrancyGuard, Pausable {
    // ═══════════════════════════════════════════════════════════════════════
    //  ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant MPC_ROLE = keccak256("MPC_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    //  CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Hard ceiling on fee rate — 5% (500 bps)
    uint16 public constant MAX_FEE_BPS = 500;

    /// @notice Maximum classical-compat window — 30 days
    uint256 public constant MAX_CLASSICAL_WINDOW = 30 days;

    // ═══════════════════════════════════════════════════════════════════════
    //  ENVELOPE TYPE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Warp 2.0 bridge envelope — what the off-chain MPC signs and
    ///         what P3Q verifies. abi.encode'd and concatenated with the
    ///         opaque proof bytes for the precompile call.
    struct BridgeEnvelope {
        uint64 srcChain; // source chain id
        bytes32 srcTx; // source-chain tx hash
        address dstAsset; // BridgedXXX contract to mint on Lux
        uint256 amount; // amount in dstAsset's raw decimals
        address recipient; // Lux address to mint to
        uint64 nonce; // monotonic per (srcChain, recipient) — prevents replay
        bool classical; // false = P3Q signed; true = ECDSA legacy (compat path)
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Pluggable basket registry
    BasketRegistry public immutable basketRegistry;

    /// @notice Used claim ids (replay protection)
    mapping(bytes32 => bool) public usedClaims;

    /// @notice Z-Chain nullifiers (zRedeem replay protection)
    mapping(bytes32 => bool) public usedNullifiers;

    /// @notice Monotonic redeem nonce per recipient
    mapping(address => uint64) public redeemNonce;

    /// @notice Fee rate in basis points (1 bp = 0.01%). Default 100 = 1%.
    uint16 public feeBps = 100;

    /// @notice Where bridge fees accumulate — separate from main vault.
    address public feeReceiver;

    /// @notice Z-Chain bridge target (0 disables zClaim/zRedeem)
    address public zChainBridge;

    /// @notice Classical-compat window expiry — 0 means strict-PQ (default).
    ///         When `block.timestamp <= classicalCompatUntil`, envelope.classical
    ///         envelopes are processed without P3Q verification (they still
    ///         require MPC_ROLE-relayed claim, see _verifyEnvelope).
    uint256 public classicalCompatUntil;

    /// @notice Optional override to mock the P3Q precompile in tests. When
    ///         non-zero, `claim` uses this address instead of P3Q_PRECOMPILE.
    ///         Production deployments leave this 0 and never set it.
    address public precompileOverride;

    // ═══════════════════════════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Claimed(
        bytes32 indexed claimId,
        uint64 indexed srcChain,
        address indexed recipient,
        address dstAsset,
        uint256 mintedToRecipient,
        uint256 feeSkimmed
    );

    event RedeemRequested(
        bytes32 indexed redeemHash,
        address indexed sender,
        address indexed asset,
        uint256 amount,
        uint64 dstChain,
        bytes dstAddr,
        uint64 nonce
    );

    event ZClaimRouted(bytes32 indexed claimId, address indexed asset, uint256 amount, bytes32 commitment);
    event ZRedeemRouted(bytes32 indexed nullifier, address indexed asset, uint256 amount, bytes dstAddr);

    event FeeBpsSet(uint16 newBps);
    event FeeReceiverSet(address indexed newReceiver);
    event ClassicalCompatEnabled(uint256 untilTimestamp);
    event ClassicalCompatDisabled();
    event ZChainBridgeSet(address indexed newBridge);
    event PrecompileOverrideSet(address indexed newOverride);
    event FeesDrained(address indexed asset, uint256 amount, address indexed to);

    // ═══════════════════════════════════════════════════════════════════════
    //  ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error V4_ZeroAddress();
    error V4_FeeAboveMax();
    error V4_ClassicalDisabled();
    error V4_ClaimAlreadyUsed();
    error V4_NullifierAlreadyUsed();
    error V4_EnvelopeInvalid();
    error V4_NotInBasket();
    error V4_ZChainNotConfigured();
    error V4_WindowTooLong();
    error V4_ZeroAmount();

    // ═══════════════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address admin, address _basketRegistry, address _feeReceiver) {
        if (admin == address(0)) revert V4_ZeroAddress();
        if (_basketRegistry == address(0)) revert V4_ZeroAddress();
        if (_feeReceiver == address(0)) revert V4_ZeroAddress();

        basketRegistry = BasketRegistry(_basketRegistry);
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _setRoleAdmin(MPC_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, GOVERNANCE_ROLE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CLAIM (inbound: source chain → Lux)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify a Warp 2.0 envelope via P3Q and mint the bridged asset.
     * @param envelope  abi.encoded BridgeEnvelope
     * @param proof     opaque P3Q proof bytes (Pulsar threshold sig + Prism cut)
     * @return claimId  the deduplication key, also returned for the daemon
     */
    function claim(bytes calldata envelope, bytes calldata proof)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 claimId)
    {
        claimId = keccak256(envelope);
        if (usedClaims[claimId]) revert V4_ClaimAlreadyUsed();

        BridgeEnvelope memory e = abi.decode(envelope, (BridgeEnvelope));
        if (e.amount == 0) revert V4_ZeroAmount();
        if (e.recipient == address(0)) revert V4_ZeroAddress();
        if (e.dstAsset == address(0)) revert V4_ZeroAddress();

        _verifyEnvelope(envelope, proof, e.classical);

        usedClaims[claimId] = true;

        (uint256 net, uint256 fee) = _splitFee(e.amount);

        IBridgedToken token = IBridgedToken(e.dstAsset);
        token.mint(e.recipient, net);
        if (fee > 0) token.mint(feeReceiver, fee);

        emit Claimed(claimId, e.srcChain, e.recipient, e.dstAsset, net, fee);
    }

    /**
     * @notice Internal: verify the envelope under the active profile.
     * @dev Strict-PQ (default): require !classical and successful P3Q verify.
     *      Classical-compat window: allow classical=true envelopes ONLY when
     *      the caller has MPC_ROLE and we're within the compat window. Even
     *      then, P3Q envelopes are still preferred and verified via precompile.
     */
    function _verifyEnvelope(bytes calldata envelope, bytes calldata proof, bool classical) internal view {
        if (classical) {
            // Classical envelopes are accepted only inside the compat window
            // and only when relayed by MPC_ROLE. P3Q is bypassed by design
            // for this back-compat tail.
            if (block.timestamp > classicalCompatUntil) revert V4_ClassicalDisabled();
            if (!hasRole(MPC_ROLE, msg.sender)) revert V4_ClassicalDisabled();
            return;
        }

        // P3Q strict path — STATICCALL the precompile (or its override in tests).
        address target = precompileOverride == address(0) ? P3Q_PRECOMPILE : precompileOverride;

        // Build the call payload: abi.encodeCall(IP3QPrecompile.verifyEnvelope, (encoded))
        // The precompile reads a single bytes parameter (envelope || proof concat).
        bytes memory encoded = bytes.concat(envelope, proof);
        bytes memory callData = abi.encodeWithSelector(
            // selector of `verifyEnvelope(bytes)`
            bytes4(keccak256("verifyEnvelope(bytes)")),
            encoded
        );

        (bool ok, bytes memory ret) = target.staticcall(callData);
        if (!ok || ret.length < 32) revert V4_EnvelopeInvalid();
        bool valid = abi.decode(ret, (bool));
        if (!valid) revert V4_EnvelopeInvalid();
    }

    function _splitFee(uint256 amount) internal view returns (uint256 net, uint256 fee) {
        // Fee math: bp out of 10_000. Caps at MAX_FEE_BPS (500 = 5%) via setter.
        fee = (amount * uint256(feeBps)) / 10_000;
        net = amount - fee;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  REDEEM (outbound: Lux → destination chain)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Burn `amount` of a bridged asset on Lux; daemon broadcaster
     *         observes the RedeemRequested event and signs the destination tx.
     * @param asset     bridged asset to burn
     * @param amount    amount to burn (raw asset units)
     * @param dstChain  destination chain id (matches src side of next claim)
     * @param dstAddr   destination-chain address bytes (variable length to fit
     *                  non-EVM addrs: SOL pubkey, TON workchain+addr, XRP r-addr,
     *                  DOT 32-byte AccountId, etc.)
     */
    function redeem(address asset, uint256 amount, uint64 dstChain, bytes calldata dstAddr)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 redeemHash)
    {
        if (asset == address(0)) revert V4_ZeroAddress();
        if (amount == 0) revert V4_ZeroAmount();
        if (dstAddr.length == 0) revert V4_ZeroAddress();

        uint64 nonce = ++redeemNonce[msg.sender];
        redeemHash = keccak256(abi.encode(asset, amount, dstChain, dstAddr, msg.sender, nonce));

        // Burn-with-allowance: caller must approve V4 to spend their balance.
        IBridgedToken(asset).burn(msg.sender, amount);

        emit RedeemRequested(redeemHash, msg.sender, asset, amount, dstChain, dstAddr, nonce);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Z-CHAIN HOOKS (shielded path)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Shielded inbound claim — verify P3Q envelope, route the mint
     *         to Z-Chain as a note commitment instead of a public balance.
     * @param envelope     abi.encoded BridgeEnvelope (recipient is unused — the
     *                     commitment carries the receiving note)
     * @param zkProof      ZK proof of (commitment ↔ envelope.amount) integrity;
     *                     V4 does NOT verify this directly — Z-Chain does.
     * @param commitment   ZK commitment that becomes a new Z-Chain note
     * @return claimId     V4 dedup key
     */
    function zClaim(bytes calldata envelope, bytes calldata zkProof, bytes32 commitment)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 claimId)
    {
        if (zChainBridge == address(0)) revert V4_ZChainNotConfigured();

        claimId = keccak256(envelope);
        if (usedClaims[claimId]) revert V4_ClaimAlreadyUsed();

        BridgeEnvelope memory e = abi.decode(envelope, (BridgeEnvelope));
        if (e.amount == 0) revert V4_ZeroAmount();
        if (e.dstAsset == address(0)) revert V4_ZeroAddress();

        // P3Q-only for shielded path — no classical-compat allowed.
        _verifyEnvelope(envelope, zkProof, false);

        usedClaims[claimId] = true;

        IZChainBridge(zChainBridge).receiveShieldedMint(e.dstAsset, e.amount, commitment, claimId);

        emit ZClaimRouted(claimId, e.dstAsset, e.amount, commitment);
    }

    /**
     * @notice Shielded outbound redeem — spend a Z-Chain note via nullifier,
     *         emit a RedeemRequested for the daemon to broadcast on dst.
     * @param nullifier   nullifier disclosed by the note spender
     * @param asset       destination bridged-asset (on Lux) — burned here
     * @param amount      amount to release on the destination chain
     * @param dstChain    destination chain id
     * @param dstAddr     destination-chain recipient
     * @param zkProof     ZK proof bytes; V4 hands them to Z-Chain for verify
     */
    function zRedeem(
        bytes32 nullifier,
        address asset,
        uint256 amount,
        uint64 dstChain,
        bytes calldata dstAddr,
        bytes calldata zkProof
    ) external nonReentrant whenNotPaused returns (bytes32 redeemHash) {
        if (zChainBridge == address(0)) revert V4_ZChainNotConfigured();
        if (usedNullifiers[nullifier]) revert V4_NullifierAlreadyUsed();
        if (asset == address(0)) revert V4_ZeroAddress();
        if (amount == 0) revert V4_ZeroAmount();
        if (dstAddr.length == 0) revert V4_ZeroAddress();

        // Z-Chain verifies the note spend. Reverts on bad proof.
        IZChainBridge(zChainBridge).verifyShieldedSpend(nullifier, asset, amount, zkProof);

        usedNullifiers[nullifier] = true;
        uint64 nonce = ++redeemNonce[msg.sender];
        redeemHash = keccak256(abi.encode(asset, amount, dstChain, dstAddr, nullifier, nonce));

        // Burn the public-side balance held by the Z-Chain bridge itself
        // (Z-Chain transferred the public token here when a note was created).
        IBridgedToken(asset).burn(zChainBridge, amount);

        emit RedeemRequested(redeemHash, msg.sender, asset, amount, dstChain, dstAddr, nonce);
        emit ZRedeemRouted(nullifier, asset, amount, dstAddr);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GOVERNANCE
    // ═══════════════════════════════════════════════════════════════════════

    function setFeeBps(uint16 newBps) external onlyRole(GOVERNANCE_ROLE) {
        if (newBps > MAX_FEE_BPS) revert V4_FeeAboveMax();
        feeBps = newBps;
        emit FeeBpsSet(newBps);
    }

    function setFeeReceiver(address newReceiver) external onlyRole(GOVERNANCE_ROLE) {
        if (newReceiver == address(0)) revert V4_ZeroAddress();
        feeReceiver = newReceiver;
        emit FeeReceiverSet(newReceiver);
    }

    /// @notice Enable the classical-compat tail for `windowSecs` seconds.
    ///         Governance-only. Window caps at MAX_CLASSICAL_WINDOW.
    function enableClassicalCompat(uint256 windowSecs) external onlyRole(GOVERNANCE_ROLE) {
        if (windowSecs > MAX_CLASSICAL_WINDOW) revert V4_WindowTooLong();
        classicalCompatUntil = block.timestamp + windowSecs;
        emit ClassicalCompatEnabled(classicalCompatUntil);
    }

    /// @notice Force-disable classical-compat immediately (governance-only).
    function disableClassicalCompat() external onlyRole(GOVERNANCE_ROLE) {
        classicalCompatUntil = 0;
        emit ClassicalCompatDisabled();
    }

    function setZChainBridge(address newBridge) external onlyRole(GOVERNANCE_ROLE) {
        zChainBridge = newBridge; // 0 disables; non-zero enables zClaim/zRedeem
        emit ZChainBridgeSet(newBridge);
    }

    /// @notice Test-only: install a mock precompile address. Governance can
    ///         set this to 0 to revert to the canonical P3Q precompile.
    function setPrecompileOverride(address newOverride) external onlyRole(GOVERNANCE_ROLE) {
        precompileOverride = newOverride;
        emit PrecompileOverrideSet(newOverride);
    }

    function pause() external onlyRole(GOVERNANCE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }

    /// @notice Drain accumulated fees of `asset` from feeReceiver to `to`.
    ///         OPERATOR_ROLE only. The feeReceiver itself doesn't hold ERC-20
    ///         allowance to V4 by default — operator must first approve.
    function drainFees(address asset, uint256 amount, address to) external onlyRole(OPERATOR_ROLE) {
        if (to == address(0)) revert V4_ZeroAddress();
        // burn from feeReceiver. feeReceiver must approve V4 to burn.
        IBridgedToken(asset).burn(feeReceiver, amount);
        IBridgedToken(asset).mint(to, amount);
        emit FeesDrained(asset, amount, to);
    }
}
