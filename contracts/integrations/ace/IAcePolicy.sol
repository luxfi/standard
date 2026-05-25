// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
//
// Minimal Chainlink ACE Policy interface vendor — just the types and methods
// we need to call an ACE Policy from inside an ERC-3643 compliance module.
// Source: smartcontractkit/chainlink-ace v1.0.0
//   packages/policy-management/src/interfaces/IPolicyEngine.sol
//   packages/policy-management/src/interfaces/IPolicy.sol
//
// Not a full re-export — we don't re-implement the engine. regulated EVM tokens
// stay ERC-3643/ModularCompliance native; this interface lets the adapter
// module delegate evaluation to an external ACE policy contract when bound.
pragma solidity ^0.8.20;

/// @title IAcePolicyEngine
/// @notice Subset of Chainlink ACE PolicyEngine types referenced by IAcePolicy.run.
interface IAcePolicyEngine {
    /// @notice Trinary result returned by every IPolicy.run.
    ///   None      — policy made no decision (treated as reject by the engine)
    ///   Allowed   — policy explicitly approves the action
    ///   Continue  — policy abstains; processing continues to the next policy
    enum PolicyResult {
        None,
        Allowed,
        Continue
    }

    /// @notice Named parameter passed to a policy's run method.
    struct Parameter {
        bytes32 name;
        bytes value;
    }
}

/// @title IAcePolicy
/// @notice Minimal Chainlink ACE policy interface. The adapter module calls
///         `run(...)` with the (from, to, value) of an ERC-3643 transfer
///         pre-encoded as ACE-style parameters.
interface IAcePolicy {
    /// @notice Returns the type/version identifier (e.g. "ACE.VolumePolicy 1.0.0").
    function typeAndVersion() external pure returns (string memory);

    /// @notice Evaluates the policy. The adapter packages the ERC-3643 transfer
    ///         arguments as `parameters` and forwards through.
    /// @param caller The sender of the underlying transaction (transfer initiator).
    /// @param subject The contract being protected (the SecurityToken bound to the
    ///        ModularCompliance that owns the adapter module).
    /// @param selector The function selector being protected (transfer/transferFrom).
    /// @param parameters Named parameter values extracted from the call.
    /// @param context Optional authorization/context blob (empty for our adapter).
    function run(
        address caller,
        address subject,
        bytes4 selector,
        bytes[] calldata parameters,
        bytes calldata context
    ) external view returns (IAcePolicyEngine.PolicyResult);
}
