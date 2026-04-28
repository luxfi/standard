// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IComplianceGate — generic yes/no trading gate.
/// @notice The minimal surface any compliance provider must implement for
///         the standard ComplianceHook, AMM overlays, and routers to
///         consume. Richer domain-specific APIs (KYC tiers, accreditation
///         expiries, Reg D/S caps, Rule 144 holding periods) live in
///         domain libraries that embed this interface.
interface IComplianceGate {
    /// @notice Is the trader permitted to trade this symbol right now?
    /// @return ok true if allowed
    /// @return reasonCode 0 if ok, otherwise an ERC-1404-style code
    function isEligible(address trader, string calldata symbol) external view returns (bool ok, uint8 reasonCode);

    /// @notice Cheaper check for transfer-level gating (no symbol).
    function checkJurisdiction(address trader) external view returns (bool);
}
