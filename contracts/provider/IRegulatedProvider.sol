// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRegulatedProvider — plug-in interface for regulated trading.
/// @notice Any Lux exchange fork can OPTIONALLY delegate regulated-asset
///         flow (security tokens, wrapped ETFs, tokenized equities) to an
///         external provider that implements this interface.
///
/// The Lux exchange itself remains permissionless and jurisdiction-neutral.
/// White-label operators wire a provider address in their chain/site
/// config; if no provider is configured, the exchange runs in open-DeFi
/// mode (no gating, crypto-only pairs). If a provider IS configured, the
/// router checks eligibility before every regulated-symbol swap.
///
/// Providers are third-party regulated businesses (broker-dealers,
/// transfer agents, ATS operators). They live outside this repo. The Lux
/// exchange never links to any specific provider.
interface IRegulatedProvider {
    enum Side {
        Buy,
        Sell
    }

    // ─────────────────────────── eligibility ──────────────────────────

    /// @notice Is the trader onboarded and permitted to trade `symbol`?
    ///         Called read-only by the router before a regulated swap.
    /// @return ok true if the trade is allowed
    /// @return reasonCode 0 if ok, otherwise an ERC-1404-style code
    function isEligible(address trader, string calldata symbol) external view returns (bool ok, uint8 reasonCode);

    /// @notice Does this provider handle `symbol`? Used to decide whether
    ///         a pair should be routed through the provider or executed
    ///         openly on Lux native liquidity.
    function handles(string calldata symbol) external view returns (bool);

    // ─────────────────────────── onboarding ───────────────────────────

    /// @notice Accept a compliance attestation for `trader`. The caller
    ///         is the integrator's white-labeled KYC surface; the attestation
    ///         is opaque to this interface — providers define their own
    ///         schemas (e.g. signed claim sets, DID proofs, VCs).
    function onboard(address trader, bytes calldata attestation) external;

    // ─────────────────────────── pricing + routing ────────────────────

    /// @notice Best execution price available through this provider.
    function bestPrice(string calldata symbol, Side side) external view returns (uint256);

    /// @notice Execute a regulated swap on the trader's behalf. The
    ///         provider matches, settles, and records; the caller is the
    ///         integrator's router contract acting under the integrator's
    ///         onboarding authority.
    /// @return amountOut actual amount delivered
    function routedSwap(
        address trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        string calldata symbol
    ) external returns (uint256 amountOut);
}
