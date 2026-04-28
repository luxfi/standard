// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IRegulatedProvider.sol";
import "./IWarpMessenger.sol";

/// @title WarpRegulatedProvider — origin-side wrapper.
/// @notice Deployed on chains that want to consume a regulated provider
///         living on a different L1 (e.g. Lux L1 consuming a provider on
///         Liquidity L1). Implements `IRegulatedProvider` but every
///         method either (a) forwards to the destination chain via Warp,
///         or (b) reads a cached attestation from a previous round-trip.
///
/// Read ops are async in the warp model — the origin-side cannot block
/// a staticcall on a round-trip, so it either:
///   - returns `(true, 0)` optimistically and lets the remote precompile
///     reject non-eligible trades atomically (the destination chain is
///     the source of truth), OR
///   - uses a cached eligibility attestation pushed by a watcher.
///
/// The default implementation below is the optimistic path: origin does
/// not re-check eligibility; the destination precompile enforces it at
/// match time via `handleWarp` with the origin sender preserved.
contract WarpRegulatedProvider is IRegulatedProvider {
    /// @notice Address of the IWarpMessenger precompile on this chain.
    ///         Standard Lux Warp address; override in constructor if needed.
    address public immutable warp;

    /// @notice Destination chain (e.g. Liquidity L1's chain ID).
    bytes32 public immutable destChainID;

    /// @notice Address of the regulated-provider precompile on the dest chain.
    address public immutable destPrecompile;

    /// @notice Opcode prefix for the destination precompile's ATS matching.
    ///         0x01 = OpMatch per precompile/ats/types.go.
    uint8 public constant DEST_OP_MATCH = 0x01;
    uint8 public constant DEST_OP_BEST_PRICE = 0x03;
    uint8 public constant DEST_OP_CHECK_ACCRED = 0x13; // BD checkAccredited
    uint8 public constant DEST_OP_CHECK_JURISD = 0x15; // BD checkJurisdiction

    uint8 public constant OP_WARP_INBOUND = 0xF0;
    uint8 public constant WARP_VERSION = 0x01;

    /// @notice Set of symbols this warp bridge handles. Operators (typically
    ///         chain governance) populate this by observing the dest
    ///         precompile's venue registry.
    mapping(bytes32 => bool) public handledSymbol;
    address public admin;

    event SwapDelegated(address indexed trader, string symbol, uint256 amountIn, bytes32 messageID);
    event SymbolEnabled(string symbol, bool enabled);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Warp: not admin");
        _;
    }

    constructor(address _warp, bytes32 _destChainID, address _destPrecompile) {
        warp = _warp;
        destChainID = _destChainID;
        destPrecompile = _destPrecompile;
        admin = msg.sender;
    }

    // ─────────────────────────── admin ────────────────────────────────

    function setHandled(string calldata symbol, bool enabled) external onlyAdmin {
        handledSymbol[keccak256(bytes(symbol))] = enabled;
        emit SymbolEnabled(symbol, enabled);
    }

    // ─────────────────────────── IRegulatedProvider ───────────────────

    function handles(string calldata symbol) external view override returns (bool) {
        return handledSymbol[keccak256(bytes(symbol))];
    }

    /// @notice Optimistic eligibility — the destination precompile is the
    ///         source of truth. We return `true` if the symbol is handled;
    ///         the real compliance check happens when `routedSwap` lands
    ///         on the destination chain.
    function isEligible(address, string calldata symbol) external view override returns (bool ok, uint8 reasonCode) {
        if (!handledSymbol[keccak256(bytes(symbol))]) return (false, 255);
        return (true, 0);
    }

    /// @notice Onboarding cannot be a read — it is an explicit mutation.
    ///         The origin chain forwards the attestation to the destination
    ///         precompile via warp; the destination decodes and applies it.
    function onboard(address trader, bytes calldata attestation) external override {
        // Destination attestation payload: inner opcode is provider-specific
        // setter (e.g. BD.OpSetAccredited / OpSetKYC encoded inside the
        // attestation bytes). Pass through unchanged.
        bytes memory envelope = _envelope(trader, uint8(attestation[0]), _slice(attestation, 1));
        IWarpMessenger(warp).sendWarpMessage(destChainID, destPrecompile, envelope);
    }

    /// @notice Best-price is fetched via an inbound warp message from a
    ///         keeper that periodically forwards the dest precompile's
    ///         state. Default returns 0 — integrators wire their own cache
    ///         (reading `getVerifiedWarpMessage`) if they need live prices.
    function bestPrice(string calldata, Side) external pure override returns (uint256) {
        return 0;
    }

    /// @notice Cross-L1 swap. Encodes an ATS match call + forwards via warp.
    ///         Returns `amountOut = 0` synchronously — the actual fill is
    ///         delivered asynchronously to the origin via a warp response.
    ///         Callers who need atomic settlement should use a local
    ///         provider or a same-L1 deployment.
    function routedSwap(
        address trader,
        address,
        /*tokenIn*/
        address,
        /*tokenOut*/
        uint256 amountIn,
        uint256,
        /*minOut*/
        string calldata symbol
    ) external override returns (uint256 amountOut) {
        require(handledSymbol[keccak256(bytes(symbol))], "Warp: unhandled");
        // Encode inner match call: side(1) | symLen(1) | symbol | price(32) | qty(32)
        // Origin does not know bestAsk; it sends qty = amountIn and the
        // destination matches at whatever the live ask is. The destination's
        // own `routedSwap` logic handles slippage; this origin wrapper is a
        // plain match_ forward for simplicity.
        bytes memory s = bytes(symbol);
        bytes memory inner = abi.encodePacked(
            uint8(0), // SideBuy
            uint8(s.length),
            s,
            uint256(0), // price=0 → destination reads live ask
            amountIn
        );
        bytes memory envelope = _envelope(trader, DEST_OP_MATCH, inner);
        bytes32 msgID = IWarpMessenger(warp).sendWarpMessage(destChainID, destPrecompile, envelope);
        emit SwapDelegated(trader, symbol, amountIn, msgID);
        return 0;
    }

    // ─────────────────────────── helpers ──────────────────────────────

    function _envelope(address origin, uint8 innerOp, bytes memory innerData) private view returns (bytes memory) {
        bytes memory out = new bytes(54 + innerData.length);
        out[0] = bytes1(OP_WARP_INBOUND);
        out[1] = bytes1(WARP_VERSION);
        // destChainID is 32 bytes — but we are encoding origin chain id,
        // which the destination reads. The calling chain's ID is known to
        // the destination via the warp verification layer; we fill zeros
        // here as a placeholder and let the verifier bind the real id.
        for (uint256 i = 0; i < 32; i++) {
            out[2 + i] = 0;
        }
        bytes20 o = bytes20(origin);
        for (uint256 i = 0; i < 20; i++) {
            out[34 + i] = o[i];
        }
        out[54 - 1] = bytes1(innerOp);
        for (uint256 i = 0; i < innerData.length; i++) {
            out[54 + i] = innerData[i];
        }
        return out;
    }

    function _slice(bytes calldata src, uint256 start) private pure returns (bytes memory) {
        return src[start:];
    }
}
