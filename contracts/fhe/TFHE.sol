// SPDX-License-Identifier: MIT
// TFHE.sol - fhEVM-compatible API wrapper for Lux FHE
// This provides compatibility with Zama's fhEVM TFHE API
pragma solidity ^0.8.24;

import {FHE, ebool, euint8, euint16, euint32, euint64, euint128, euint256, eaddress, einput} from "./FHE.sol";
import {Common} from "./FHE.sol";

/**
 * @title TFHE
 * @notice fhEVM-compatible TFHE library for Lux Network
 * @dev This library provides API compatibility with Zama's fhEVM TFHE.sol
 *      while using Lux's native FHE precompile infrastructure.
 *
 * Precompile Addresses (Lux):
 *   - FheOS:           0x80 (128)
 *   - ACL:             0x81 (129)
 *   - InputVerifier:   0x82 (130)
 *   - DecryptGateway:  0x83 (131)
 */
library TFHE {
    // ===== Type Constants =====
    uint8 internal constant TYPE_EBOOL = 0;
    uint8 internal constant TYPE_EUINT8 = 2;
    uint8 internal constant TYPE_EUINT16 = 3;
    uint8 internal constant TYPE_EUINT32 = 4;
    uint8 internal constant TYPE_EUINT64 = 5;
    uint8 internal constant TYPE_EUINT128 = 6;
    uint8 internal constant TYPE_EADDRESS = 7;
    uint8 internal constant TYPE_EUINT256 = 8;

    // ===== Initialization Checks =====

    function isInitialized(ebool v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    function isInitialized(euint8 v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    function isInitialized(euint16 v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    function isInitialized(euint32 v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    function isInitialized(euint64 v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    function isInitialized(euint128 v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    function isInitialized(euint256 v) internal pure returns (bool) {
        return euint256.unwrap(v) != 0;
    }

    function isInitialized(eaddress v) internal pure returns (bool) {
        return Common.isInitialized(v);
    }

    // ===== Encryption (asEuintXX) =====

    function asEbool(bool value) internal returns (ebool) {
        return FHE.asEbool(value);
    }

    function asEuint8(uint8 value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }

    function asEuint16(uint16 value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }

    function asEuint32(uint32 value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }

    function asEuint64(uint64 value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }

    function asEuint128(uint128 value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }

    function asEuint256(uint256 value) internal returns (euint256) {
        return FHE.asEuint256(value);
    }

    function asEaddress(address value) internal returns (eaddress) {
        return FHE.asEaddress(value);
    }

    // ===== Input Verification =====

    function asEbool(einput inputHandle, bytes memory inputProof) internal returns (ebool) {
        return FHE.asEbool(inputHandle, inputProof);
    }

    function asEuint8(einput inputHandle, bytes memory inputProof) internal returns (euint8) {
        return FHE.asEuint8(inputHandle, inputProof);
    }

    function asEuint16(einput inputHandle, bytes memory inputProof) internal returns (euint16) {
        return FHE.asEuint16(inputHandle, inputProof);
    }

    function asEuint32(einput inputHandle, bytes memory inputProof) internal returns (euint32) {
        return FHE.asEuint32(inputHandle, inputProof);
    }

    function asEuint64(einput inputHandle, bytes memory inputProof) internal returns (euint64) {
        return FHE.asEuint64(inputHandle, inputProof);
    }

    function asEuint128(einput inputHandle, bytes memory inputProof) internal returns (euint128) {
        return FHE.asEuint128(inputHandle, inputProof);
    }

    function asEuint256(einput inputHandle, bytes memory inputProof) internal returns (euint256) {
        return FHE.asEuint256(inputHandle, inputProof);
    }

    function asEaddress(einput inputHandle, bytes memory inputProof) internal returns (eaddress) {
        return FHE.asEaddress(inputHandle, inputProof);
    }

    // ===== Arithmetic Operations =====

    function add(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.add(a, b);
    }

    function add(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.add(a, b);
    }

    function add(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.add(a, b);
    }

    function add(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.add(a, b);
    }

    function add(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.add(a, b);
    }

    function add(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.add(a, b);
    }

    function sub(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.sub(a, b);
    }

    function sub(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.sub(a, b);
    }

    function sub(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.sub(a, b);
    }

    function sub(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.sub(a, b);
    }

    function sub(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.sub(a, b);
    }

    // Note: euint256 sub not yet supported in FHE.sol
    // function sub(euint256 a, euint256 b) internal returns (euint256) {
    //     return FHE.sub(a, b);
    // }

    function mul(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.mul(a, b);
    }

    function mul(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.mul(a, b);
    }

    function mul(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.mul(a, b);
    }

    function mul(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.mul(a, b);
    }

    function mul(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.mul(a, b);
    }

    // Note: euint256 mul not yet supported in FHE.sol
    // function mul(euint256 a, euint256 b) internal returns (euint256) {
    //     return FHE.mul(a, b);
    // }

    function div(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.div(a, b);
    }

    function div(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.div(a, b);
    }

    function div(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.div(a, b);
    }

    function div(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.div(a, b);
    }

    function div(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.div(a, b);
    }

    function div(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.div(a, b);
    }

    function rem(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.rem(a, b);
    }

    function rem(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.rem(a, b);
    }

    function rem(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.rem(a, b);
    }

    function rem(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.rem(a, b);
    }

    function rem(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.rem(a, b);
    }

    function rem(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.rem(a, b);
    }

    // ===== Comparison Operations =====

    function eq(euint8 a, euint8 b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function eq(euint16 a, euint16 b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function eq(euint32 a, euint32 b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function eq(euint64 a, euint64 b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function eq(euint128 a, euint128 b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function eq(euint256 a, euint256 b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function eq(eaddress a, eaddress b) internal returns (ebool) {
        return FHE.eq(a, b);
    }

    function ne(euint8 a, euint8 b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function ne(euint16 a, euint16 b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function ne(euint32 a, euint32 b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function ne(euint64 a, euint64 b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function ne(euint128 a, euint128 b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function ne(euint256 a, euint256 b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function ne(eaddress a, eaddress b) internal returns (ebool) {
        return FHE.ne(a, b);
    }

    function lt(euint8 a, euint8 b) internal returns (ebool) {
        return FHE.lt(a, b);
    }

    function lt(euint16 a, euint16 b) internal returns (ebool) {
        return FHE.lt(a, b);
    }

    function lt(euint32 a, euint32 b) internal returns (ebool) {
        return FHE.lt(a, b);
    }

    function lt(euint64 a, euint64 b) internal returns (ebool) {
        return FHE.lt(a, b);
    }

    function lt(euint128 a, euint128 b) internal returns (ebool) {
        return FHE.lt(a, b);
    }

    function lt(euint256 a, euint256 b) internal returns (ebool) {
        return FHE.lt(a, b);
    }

    function le(euint8 a, euint8 b) internal returns (ebool) {
        return FHE.lte(a, b);
    }

    function le(euint16 a, euint16 b) internal returns (ebool) {
        return FHE.lte(a, b);
    }

    function le(euint32 a, euint32 b) internal returns (ebool) {
        return FHE.lte(a, b);
    }

    function le(euint64 a, euint64 b) internal returns (ebool) {
        return FHE.lte(a, b);
    }

    function le(euint128 a, euint128 b) internal returns (ebool) {
        return FHE.lte(a, b);
    }

    function le(euint256 a, euint256 b) internal returns (ebool) {
        return FHE.lte(a, b);
    }

    function gt(euint8 a, euint8 b) internal returns (ebool) {
        return FHE.gt(a, b);
    }

    function gt(euint16 a, euint16 b) internal returns (ebool) {
        return FHE.gt(a, b);
    }

    function gt(euint32 a, euint32 b) internal returns (ebool) {
        return FHE.gt(a, b);
    }

    function gt(euint64 a, euint64 b) internal returns (ebool) {
        return FHE.gt(a, b);
    }

    function gt(euint128 a, euint128 b) internal returns (ebool) {
        return FHE.gt(a, b);
    }

    function gt(euint256 a, euint256 b) internal returns (ebool) {
        return FHE.gt(a, b);
    }

    function ge(euint8 a, euint8 b) internal returns (ebool) {
        return FHE.gte(a, b);
    }

    function ge(euint16 a, euint16 b) internal returns (ebool) {
        return FHE.gte(a, b);
    }

    function ge(euint32 a, euint32 b) internal returns (ebool) {
        return FHE.gte(a, b);
    }

    function ge(euint64 a, euint64 b) internal returns (ebool) {
        return FHE.gte(a, b);
    }

    function ge(euint128 a, euint128 b) internal returns (ebool) {
        return FHE.gte(a, b);
    }

    function ge(euint256 a, euint256 b) internal returns (ebool) {
        return FHE.gte(a, b);
    }

    // ===== Min/Max Operations =====

    function min(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.min(a, b);
    }

    function min(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.min(a, b);
    }

    function min(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.min(a, b);
    }

    function min(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.min(a, b);
    }

    function min(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.min(a, b);
    }

    function min(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.min(a, b);
    }

    function max(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.max(a, b);
    }

    function max(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.max(a, b);
    }

    function max(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.max(a, b);
    }

    function max(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.max(a, b);
    }

    function max(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.max(a, b);
    }

    function max(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.max(a, b);
    }

    // ===== Bitwise Operations =====

    function and(ebool a, ebool b) internal returns (ebool) {
        return FHE.and(a, b);
    }

    function and(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.and(a, b);
    }

    function and(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.and(a, b);
    }

    function and(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.and(a, b);
    }

    function and(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.and(a, b);
    }

    function and(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.and(a, b);
    }

    function and(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.and(a, b);
    }

    function or(ebool a, ebool b) internal returns (ebool) {
        return FHE.or(a, b);
    }

    function or(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.or(a, b);
    }

    function or(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.or(a, b);
    }

    function or(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.or(a, b);
    }

    function or(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.or(a, b);
    }

    function or(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.or(a, b);
    }

    function or(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.or(a, b);
    }

    function xor(ebool a, ebool b) internal returns (ebool) {
        return FHE.xor(a, b);
    }

    function xor(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.xor(a, b);
    }

    function xor(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.xor(a, b);
    }

    function xor(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.xor(a, b);
    }

    function xor(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.xor(a, b);
    }

    function xor(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.xor(a, b);
    }

    function xor(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.xor(a, b);
    }

    function not(ebool a) internal returns (ebool) {
        return FHE.not(a);
    }

    function not(euint8 a) internal returns (euint8) {
        return FHE.not(a);
    }

    function not(euint16 a) internal returns (euint16) {
        return FHE.not(a);
    }

    function not(euint32 a) internal returns (euint32) {
        return FHE.not(a);
    }

    function not(euint64 a) internal returns (euint64) {
        return FHE.not(a);
    }

    function not(euint128 a) internal returns (euint128) {
        return FHE.not(a);
    }

    function not(euint256 a) internal returns (euint256) {
        return FHE.not(a);
    }

    // ===== Shift Operations =====

    function shl(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.shl(a, b);
    }

    function shl(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.shl(a, b);
    }

    function shl(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.shl(a, b);
    }

    function shl(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.shl(a, b);
    }

    function shl(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.shl(a, b);
    }

    function shl(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.shl(a, b);
    }

    function shr(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.shr(a, b);
    }

    function shr(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.shr(a, b);
    }

    function shr(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.shr(a, b);
    }

    function shr(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.shr(a, b);
    }

    function shr(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.shr(a, b);
    }

    function shr(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.shr(a, b);
    }

    function rotl(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.rol(a, b);
    }

    function rotl(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.rol(a, b);
    }

    function rotl(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.rol(a, b);
    }

    function rotl(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.rol(a, b);
    }

    function rotl(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.rol(a, b);
    }

    function rotl(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.rol(a, b);
    }

    function rotr(euint8 a, euint8 b) internal returns (euint8) {
        return FHE.ror(a, b);
    }

    function rotr(euint16 a, euint16 b) internal returns (euint16) {
        return FHE.ror(a, b);
    }

    function rotr(euint32 a, euint32 b) internal returns (euint32) {
        return FHE.ror(a, b);
    }

    function rotr(euint64 a, euint64 b) internal returns (euint64) {
        return FHE.ror(a, b);
    }

    function rotr(euint128 a, euint128 b) internal returns (euint128) {
        return FHE.ror(a, b);
    }

    function rotr(euint256 a, euint256 b) internal returns (euint256) {
        return FHE.ror(a, b);
    }

    // ===== Conditional Selection =====

    function select(ebool condition, ebool ifTrue, ebool ifFalse) internal returns (ebool) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, euint8 ifTrue, euint8 ifFalse) internal returns (euint8) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, euint16 ifTrue, euint16 ifFalse) internal returns (euint16) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, euint32 ifTrue, euint32 ifFalse) internal returns (euint32) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, euint64 ifTrue, euint64 ifFalse) internal returns (euint64) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, euint128 ifTrue, euint128 ifFalse) internal returns (euint128) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, euint256 ifTrue, euint256 ifFalse) internal returns (euint256) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    function select(ebool condition, eaddress ifTrue, eaddress ifFalse) internal returns (eaddress) {
        return FHE.select(condition, ifTrue, ifFalse);
    }

    // ===== Random Number Generation =====

    function randEuint8() internal returns (euint8) {
        return FHE.randomEuint8();
    }

    function randEuint16() internal returns (euint16) {
        return FHE.randomEuint16();
    }

    function randEuint32() internal returns (euint32) {
        return FHE.randomEuint32();
    }

    function randEuint64() internal returns (euint64) {
        return FHE.randomEuint64();
    }

    function randEuint128() internal returns (euint128) {
        return FHE.randomEuint128();
    }

    function randEuint256() internal returns (euint256) {
        return FHE.randomEuint256();
    }

    // ===== Access Control =====

    function allow(euint8 ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(euint16 ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(euint32 ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(euint64 ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(euint128 ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(euint256 ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(eaddress ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allow(ebool ct, address account) internal {
        FHE.allow(ct, account);
    }

    function allowThis(euint8 ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(euint16 ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(euint32 ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(euint64 ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(euint128 ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(euint256 ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(eaddress ct) internal {
        FHE.allowThis(ct);
    }

    function allowThis(ebool ct) internal {
        FHE.allowThis(ct);
    }

    // ===== Type Casting =====

    function asEuint8(ebool v) internal returns (euint8) {
        return FHE.asEuint8(v);
    }

    function asEuint16(euint8 v) internal returns (euint16) {
        return FHE.asEuint16(v);
    }

    function asEuint32(euint16 v) internal returns (euint32) {
        return FHE.asEuint32(v);
    }

    function asEuint64(euint32 v) internal returns (euint64) {
        return FHE.asEuint64(v);
    }

    function asEuint128(euint64 v) internal returns (euint128) {
        return FHE.asEuint128(v);
    }

    function asEuint256(euint128 v) internal returns (euint256) {
        return FHE.asEuint256(v);
    }

    // ===== Decryption (via Gateway) =====

    // Async decrypt functions - results delivered via callback
    function decrypt(ebool ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(euint8 ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(euint16 ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(euint32 ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(euint64 ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(euint128 ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(euint256 ct) internal {
        FHE.decrypt(ct);
    }

    function decrypt(eaddress ct) internal {
        FHE.decrypt(ct);
    }
}
