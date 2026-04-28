// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title OperatorRegistry — generic federated operator registry.
/// @notice Base primitive for any regulated venue that wants an
///         admin-gated list of licensed operators (ATS venues,
///         broker-dealers, transfer agents, any other role-based
///         federation). Consumers inherit and extend with domain-
///         specific metadata (fees, tiers, credentials).
///
/// Admin is a single authority set at deploy; registration is gated to
/// the admin. In production the admin is a governance multisig. Operators
/// are identified by address and keyed by a 32-byte license hash that the
/// consumer chooses (CRD hash, Form ATS-N filing, etc.).
abstract contract OperatorRegistry {
    address public immutable admin;

    /// @notice operator → 32-byte license hash. Zero means "not registered".
    mapping(address => bytes32) public licenseOf;

    uint64 public operatorCount;

    event OperatorRegistered(address indexed operator, bytes32 license);
    event OperatorDeactivated(address indexed operator);

    error NotAdmin();
    error OperatorExists(address operator);
    error OperatorNotFound(address operator);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(address _admin) {
        require(_admin != address(0), "OperatorRegistry: zero admin");
        admin = _admin;
    }

    /// @notice Register an operator under a license. Admin-only.
    function _registerOperator(address operator, bytes32 license) internal onlyAdmin returns (uint64) {
        if (licenseOf[operator] != bytes32(0)) revert OperatorExists(operator);
        require(license != bytes32(0), "OperatorRegistry: zero license");
        licenseOf[operator] = license;
        unchecked {
            operatorCount++;
        }
        emit OperatorRegistered(operator, license);
        return operatorCount;
    }

    /// @notice Deactivate an operator. Admin-only. Zero-out the license.
    function _deactivateOperator(address operator) internal onlyAdmin {
        if (licenseOf[operator] == bytes32(0)) revert OperatorNotFound(operator);
        licenseOf[operator] = bytes32(0);
        unchecked {
            operatorCount--;
        }
        emit OperatorDeactivated(operator);
    }

    function isRegistered(address operator) public view returns (bool) {
        return licenseOf[operator] != bytes32(0);
    }
}
