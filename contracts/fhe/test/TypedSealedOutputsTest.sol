// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {FHE, BindingsEbool, BindingsEuint8, BindingsEuint16, BindingsEuint32, BindingsEuint64, BindingsEuint128, BindingsEaddress, ebool, euint8, euint16, euint32, euint64, euint128, euint256, eaddress} from "../FHE.sol";
import {SealedBool, SealedUint, SealedAddress} from "../IFHE.sol";
import {PermissionedV2, PermissionV2} from "../access/PermissionedV2.sol";

contract TypedSealedOutputsTest is PermissionedV2 {
    using BindingsEbool for ebool;
    using BindingsEuint8 for euint8;
    using BindingsEuint16 for euint16;
    using BindingsEuint32 for euint32;
    using BindingsEuint64 for euint64;
    using BindingsEuint128 for euint128;
    using BindingsEaddress for eaddress;

    constructor() PermissionedV2("TEST") {}

    // Placeholder functions - full implementation requires sealoutputTyped in FHE.sol
    function getSealedEBool(PermissionV2 memory permission, bool value) public withPermission(permission) returns (bytes memory) {
        ebool encrypted = FHE.asEbool(value);
        return abi.encode(ebool.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEUint8(PermissionV2 memory permission, uint8 value) public withPermission(permission) returns (bytes memory) {
        euint8 encrypted = FHE.asEuint8(value);
        return abi.encode(euint8.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEUint16(PermissionV2 memory permission, uint16 value) public withPermission(permission) returns (bytes memory) {
        euint16 encrypted = FHE.asEuint16(value);
        return abi.encode(euint16.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEUint32(PermissionV2 memory permission, uint32 value) public withPermission(permission) returns (bytes memory) {
        euint32 encrypted = FHE.asEuint32(value);
        return abi.encode(euint32.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEUint64(PermissionV2 memory permission, uint64 value) public withPermission(permission) returns (bytes memory) {
        euint64 encrypted = FHE.asEuint64(value);
        return abi.encode(euint64.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEUint128(PermissionV2 memory permission, uint128 value) public withPermission(permission) returns (bytes memory) {
        euint128 encrypted = FHE.asEuint128(value);
        return abi.encode(euint128.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEUint256(PermissionV2 memory permission, uint256 value) public withPermission(permission) returns (bytes memory) {
        euint256 encrypted = FHE.asEuint256(value);
        return abi.encode(euint256.unwrap(encrypted), permission.sealingKey);
    }

    function getSealedEAddress(PermissionV2 memory permission, address value) public withPermission(permission) returns (bytes memory) {
        eaddress encrypted = FHE.asEaddress(value);
        return abi.encode(eaddress.unwrap(encrypted), permission.sealingKey);
    }
}
