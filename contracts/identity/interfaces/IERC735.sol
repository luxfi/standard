// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title IERC735 — Claim Holder (ONCHAINID)
/// @notice Standard interface for claims held by an identity contract.
interface IERC735 {
    event ClaimAdded(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );

    event ClaimRemoved(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );

    event ClaimChanged(
        bytes32 indexed claimId,
        uint256 indexed topic,
        uint256 scheme,
        address indexed issuer,
        bytes signature,
        bytes data,
        string uri
    );

    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address issuer,
        bytes calldata _signature,
        bytes calldata _data,
        string calldata _uri
    ) external returns (bytes32 claimRequestId);

    function removeClaim(bytes32 _claimId) external returns (bool success);

    function getClaim(bytes32 _claimId)
        external
        view
        returns (uint256 topic, uint256 scheme, address issuer, bytes memory signature, bytes memory data, string memory uri);

    function getClaimIdsByTopic(uint256 _topic) external view returns (bytes32[] memory claimIds);
}
