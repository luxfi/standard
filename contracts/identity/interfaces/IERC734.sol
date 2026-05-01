// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title IERC734 — Key Holder (ONCHAINID)
/// @notice Standard interface for keys held by an identity contract. Ported
///         from the OnchainID reference impl v2.2.1, adjusted for OZ v5 / 0.8.20+.
interface IERC734 {
    event Approved(uint256 indexed executionId, bool approved);
    event Executed(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);
    event ExecutionRequested(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);
    event ExecutionFailed(uint256 indexed executionId, address indexed to, uint256 indexed value, bytes data);
    event KeyAdded(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);
    event KeyRemoved(bytes32 indexed key, uint256 indexed purpose, uint256 indexed keyType);

    function addKey(bytes32 _key, uint256 _purpose, uint256 _keyType) external returns (bool success);
    function approve(uint256 _id, bool _approve) external returns (bool success);
    function removeKey(bytes32 _key, uint256 _purpose) external returns (bool success);
    function execute(address _to, uint256 _value, bytes calldata _data) external payable returns (uint256 executionId);

    function getKey(bytes32 _key) external view returns (uint256[] memory purposes, uint256 keyType, bytes32 key);
    function getKeyPurposes(bytes32 _key) external view returns (uint256[] memory _purposes);
    function getKeysByPurpose(uint256 _purpose) external view returns (bytes32[] memory keys);
    function keyHasPurpose(bytes32 _key, uint256 _purpose) external view returns (bool exists);
}
