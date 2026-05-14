// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
//
// Vendored from smartcontractkit/chainlink-ace v1.0.0
//   packages/policy-management/src/interfaces/IPolicyProtected.sol
//
// Verbatim copy of the public surface ACE-native integrators expect from a
// policy-protected contract. Liquid's `AceSecurityTokenAdapter` implements
// this interface to wrap an ERC-3643 SecurityToken as an ACE-recognized
// contract — bidirectional integration with the AcePolicyAdapterModule
// (which goes the other way: external ACE policy used INSIDE our compliance).
pragma solidity ^0.8.20;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IPolicyProtected
/// @notice Interface a contract implements to declare itself "policy-protected"
///         in the Chainlink ACE framework. Integrators query
///         `supportsInterface(type(IPolicyProtected).interfaceId)` for
///         discovery; if true, they know the contract follows ACE conventions.
interface IPolicyProtected is IERC165 {
    /// @notice Emitted when a policy engine is attached to the contract.
    event PolicyEngineAttached(address indexed policyEngine);
    /// @notice Emitted when a policy engine detach fails.
    event PolicyEngineDetachFailed(address indexed policyEngine, bytes reason);

    /// @notice Attaches a policy engine to the current contract.
    function attachPolicyEngine(address policyEngine) external;

    /// @notice Gets the policy engine attached to the current contract.
    function getPolicyEngine() external view returns (address);

    /// @notice Sets the context for the current transaction. Per-sender
    ///         storage; not automatically linked to a specific call. Caller
    ///         is responsible for atomic set+consume.
    function setContext(bytes calldata context) external;

    /// @notice Gets the context for the current sender.
    function getContext() external view returns (bytes memory);

    /// @notice Clears the context for the current sender.
    function clearContext() external;
}
