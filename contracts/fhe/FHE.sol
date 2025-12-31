// SPDX-License-Identifier: MIT
// FHE.sol - Lux FHE Library for encrypted computation on the T-Chain
// solhint-disable one-contract-per-file
pragma solidity >=0.8.19 <0.9.0;

// ===== Split File Imports =====
// Common utilities in FHECommon.sol
import {FHECommon} from "./FHECommon.sol";
// T-Chain network interface in FHENetwork.sol
import {FHENetwork} from "./FHENetwork.sol";
// Interfaces and structs from IFHE.sol
import {FunctionId, ITaskManager, Utils, EncryptedInput, Ebool, Euint8, Euint16, Euint32, Euint64, Euint128, Euint256, Eaddress, SealedBool, SealedUint, SealedAddress} from "./IFHE.sol";

// ===== Encrypted Value Types =====
// Types must be defined here (not imported) for "using ... global" to work
// This is a Solidity language limitation
type ebool is uint256;
type euint8 is uint256;
type euint16 is uint256;
type euint32 is uint256;
type euint64 is uint256;
type euint128 is uint256;
type euint256 is uint256;
type eaddress is uint256;
type einput is bytes32;

// ===== T-Chain FHE Gateway Address =====
// This is the gateway address for FHE operations on the Lux T-Chain (Threshold Chain)
// The T-Chain is powered by ThresholdVM and provides FHE compute
address constant T_CHAIN_FHE_ADDRESS = 0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9;

/// @title FHE
/// @notice Main library for FHE operations on the Lux T-Chain (Threshold Chain)
/// @dev The T-Chain is powered by ThresholdVM and provides FHE compute
library FHE {

    error InvalidEncryptedInput(uint8 got, uint8 expected);

    // ===== Internal isInitialized helpers =====
    // These wrap FHECommon.isInitialized(uint256) for typed values
    function _isInit(uint256 v) private pure returns (bool) { return FHECommon.isInitialized(v); }
    function _isInit(ebool v) private pure returns (bool) { return FHECommon.isInitialized(ebool.unwrap(v)); }
    function _isInit(euint8 v) private pure returns (bool) { return FHECommon.isInitialized(euint8.unwrap(v)); }
    function _isInit(euint16 v) private pure returns (bool) { return FHECommon.isInitialized(euint16.unwrap(v)); }
    function _isInit(euint32 v) private pure returns (bool) { return FHECommon.isInitialized(euint32.unwrap(v)); }
    function _isInit(euint64 v) private pure returns (bool) { return FHECommon.isInitialized(euint64.unwrap(v)); }
    function _isInit(euint128 v) private pure returns (bool) { return FHECommon.isInitialized(euint128.unwrap(v)); }
    function _isInit(euint256 v) private pure returns (bool) { return FHECommon.isInitialized(euint256.unwrap(v)); }
    function _isInit(eaddress v) private pure returns (bool) { return FHECommon.isInitialized(eaddress.unwrap(v)); }

    // ===== Public isInitialized - for developer convenience =====
    /// @notice Check if an encrypted boolean is initialized (non-zero ciphertext hash)
    function isInitialized(ebool v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted uint8 is initialized
    function isInitialized(euint8 v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted uint16 is initialized
    function isInitialized(euint16 v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted uint32 is initialized
    function isInitialized(euint32 v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted uint64 is initialized
    function isInitialized(euint64 v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted uint128 is initialized
    function isInitialized(euint128 v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted uint256 is initialized
    function isInitialized(euint256 v) internal pure returns (bool) { return _isInit(v); }
    /// @notice Check if an encrypted address is initialized
    function isInitialized(eaddress v) internal pure returns (bool) { return _isInit(v); }

    /// @notice Perform the addition operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted addition
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the addition result
    function add(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.add));
    }

    /// @notice Perform the addition operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted addition
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the addition result
    function add(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.add));
    }

    /// @notice Perform the addition operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted addition
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the addition result
    function add(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.add));
    }

    /// @notice Perform the addition operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted addition
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the addition result
    function add(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.add));
    }

    /// @notice Perform the addition operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted addition
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the addition result
    function add(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.add));
    }

    /// @notice Perform the addition operation on two parameters of type euint256
    function add(euint256 lhs, euint256 rhs) internal returns (euint256) {
        if (!_isInit(euint256.unwrap(lhs))) {
            lhs = asEuint256(0);
        }
        if (!_isInit(euint256.unwrap(rhs))) {
            rhs = asEuint256(0);
        }
        return euint256.wrap(FHENetwork.mathOp(Utils.EUINT256_TFHE, euint256.unwrap(lhs), euint256.unwrap(rhs), FunctionId.add));
    }

    /// @notice Perform the less than or equal to operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type ebool containing the comparison result
    function lte(euint8 lhs, euint8 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.lte));
    }

    /// @notice Perform the less than or equal to operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type ebool containing the comparison result
    function lte(euint16 lhs, euint16 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.lte));
    }

    /// @notice Perform the less than or equal to operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type ebool containing the comparison result
    function lte(euint32 lhs, euint32 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.lte));
    }

    /// @notice Perform the less than or equal to operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type ebool containing the comparison result
    function lte(euint64 lhs, euint64 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.lte));
    }

    /// @notice Alias for lte (less than or equal) for euint64
    function le(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return lte(lhs, rhs);
    }

    /// @notice Perform the less than or equal to operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type ebool containing the comparison result
    function lte(euint128 lhs, euint128 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.lte));
    }


    /// @notice Perform the subtraction operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted subtraction
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the subtraction result
    function sub(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.sub));
    }

    /// @notice Perform the subtraction operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted subtraction
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the subtraction result
    function sub(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.sub));
    }

    /// @notice Perform the subtraction operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted subtraction
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the subtraction result
    function sub(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.sub));
    }

    /// @notice Perform the subtraction operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted subtraction
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the subtraction result
    function sub(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.sub));
    }

    /// @notice Perform the subtraction operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted subtraction
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the subtraction result
    function sub(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.sub));
    }


    /// @notice Perform the multiplication operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted multiplication
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the multiplication result
    function mul(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.mul));
    }

    /// @notice Perform the multiplication operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted multiplication
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the multiplication result
    function mul(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.mul));
    }

    /// @notice Perform the multiplication operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted multiplication
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the multiplication result
    function mul(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.mul));
    }

    /// @notice Perform the multiplication operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted multiplication
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the multiplication result
    function mul(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.mul));
    }

    /// @notice Perform the multiplication operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted multiplication
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the multiplication result
    function mul(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.mul));
    }


    /// @notice Perform the less than operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type ebool containing the comparison result
    function lt(euint8 lhs, euint8 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.lt));
    }

    /// @notice Perform the less than operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type ebool containing the comparison result
    function lt(euint16 lhs, euint16 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.lt));
    }

    /// @notice Perform the less than operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type ebool containing the comparison result
    function lt(euint32 lhs, euint32 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.lt));
    }

    /// @notice Perform the less than operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type ebool containing the comparison result
    function lt(euint64 lhs, euint64 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.lt));
    }

    /// @notice Perform the less than operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type ebool containing the comparison result
    function lt(euint128 lhs, euint128 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.lt));
    }


    /// @notice Perform the division operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted division
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the division result
    function div(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.div));
    }

    /// @notice Perform the division operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted division
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the division result
    function div(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.div));
    }

    /// @notice Perform the division operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted division
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the division result
    function div(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.div));
    }

    /// @notice Perform the division operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted division
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the division result
    function div(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.div));
    }

    /// @notice Perform the division operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted division
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the division result
    function div(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.div));
    }

    /// @notice Perform the div operation on two parameters of type euint256
    /// @dev euint256 operations are stubbed - require full FHE backend support
    function div(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        // Stub: euint256 operations require extended backend support
        return lhs;
    }

    /// @notice Perform the rem operation on two parameters of type euint256
    /// @dev euint256 operations are stubbed - require full FHE backend support
    function rem(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return lhs;
    }

    // ===== euint256 Stubs (require full FHE backend support) =====

    function eq(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) == euint256.unwrap(rhs) ? 1 : 0);
    }
    function ne(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) != euint256.unwrap(rhs) ? 1 : 0);
    }
    function lt(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) < euint256.unwrap(rhs) ? 1 : 0);
    }
    function le(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) <= euint256.unwrap(rhs) ? 1 : 0);
    }
    function lte(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) <= euint256.unwrap(rhs) ? 1 : 0);
    }
    function gt(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) > euint256.unwrap(rhs) ? 1 : 0);
    }
    function ge(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) >= euint256.unwrap(rhs) ? 1 : 0);
    }
    function gte(euint256 lhs, euint256 rhs) internal pure returns (ebool) {
        return ebool.wrap(euint256.unwrap(lhs) >= euint256.unwrap(rhs) ? 1 : 0);
    }
    function min(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.unwrap(lhs) < euint256.unwrap(rhs) ? lhs : rhs;
    }
    function max(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.unwrap(lhs) > euint256.unwrap(rhs) ? lhs : rhs;
    }
    function and(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.wrap(euint256.unwrap(lhs) & euint256.unwrap(rhs));
    }
    function or(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.wrap(euint256.unwrap(lhs) | euint256.unwrap(rhs));
    }
    function xor(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.wrap(euint256.unwrap(lhs) ^ euint256.unwrap(rhs));
    }
    function not(euint256 v) internal pure returns (euint256) {
        return euint256.wrap(~euint256.unwrap(v));
    }
    function shl(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.wrap(euint256.unwrap(lhs) << euint256.unwrap(rhs));
    }
    function shr(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return euint256.wrap(euint256.unwrap(lhs) >> euint256.unwrap(rhs));
    }
    function rotl(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return lhs; // Stub
    }
    function rotr(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return lhs; // Stub
    }
    function rol(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return lhs; // Stub
    }
    function ror(euint256 lhs, euint256 rhs) internal pure returns (euint256) {
        return lhs; // Stub
    }
    function select(ebool condition, euint256 ifTrue, euint256 ifFalse) internal pure returns (euint256) {
        return ebool.unwrap(condition) != 0 ? ifTrue : ifFalse;
    }
    function randEuint256() internal pure returns (euint256) {
        return euint256.wrap(0); // Stub - needs secure randomness
    }
    function randomEuint256() internal pure returns (euint256) {
        return euint256.wrap(0); // Stub - needs secure randomness
    }
    function allow(euint256, address) internal pure {
        // Stub - ACL not implemented for euint256
    }
    function allowThis(euint256) internal pure {
        // Stub - ACL not implemented for euint256
    }
    function allowSender(euint256) internal pure {
        // Stub - ACL not implemented for euint256
    }
    function isAllowed(euint256, address) internal pure returns (bool) {
        return true; // Stub
    }
    function isSenderAllowed(euint256) internal pure returns (bool) {
        return true; // Stub
    }
    /// @notice Perform the greater than operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type ebool containing the comparison result
    function gt(euint8 lhs, euint8 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.gt));
    }

    /// @notice Perform the greater than operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type ebool containing the comparison result
    function gt(euint16 lhs, euint16 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.gt));
    }

    /// @notice Perform the greater than operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type ebool containing the comparison result
    function gt(euint32 lhs, euint32 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.gt));
    }

    /// @notice Perform the greater than operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type ebool containing the comparison result
    function gt(euint64 lhs, euint64 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.gt));
    }

    /// @notice Perform the greater than operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type ebool containing the comparison result
    function gt(euint128 lhs, euint128 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.gt));
    }


    /// @notice Perform the greater than or equal to operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type ebool containing the comparison result
    function gte(euint8 lhs, euint8 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.gte));
    }

    /// @notice Perform the greater than or equal to operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type ebool containing the comparison result
    function gte(euint16 lhs, euint16 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.gte));
    }

    /// @notice Perform the greater than or equal to operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type ebool containing the comparison result
    function gte(euint32 lhs, euint32 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.gte));
    }

    /// @notice Perform the greater than or equal to operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type ebool containing the comparison result
    function gte(euint64 lhs, euint64 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.gte));
    }

    /// @notice Alias for gte (greater than or equal) for euint64
    function ge(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return gte(lhs, rhs);
    }

    /// @notice Perform the greater than or equal to operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted comparison
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type ebool containing the comparison result
    function gte(euint128 lhs, euint128 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.gte));
    }


    /// @notice Perform the remainder operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted remainder calculation
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the remainder result
    function rem(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.rem));
    }

    /// @notice Perform the remainder operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted remainder calculation
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the remainder result
    function rem(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.rem));
    }

    /// @notice Perform the remainder operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted remainder calculation
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the remainder result
    function rem(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.rem));
    }

    /// @notice Perform the remainder operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted remainder calculation
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the remainder result
    function rem(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.rem));
    }

    /// @notice Perform the remainder operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted remainder calculation
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the remainder result
    function rem(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.rem));
    }


    /// @notice Perform the bitwise AND operation on two parameters of type ebool
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise AND
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return result of type ebool containing the AND result
    function and(ebool lhs, ebool rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEbool(true);
        }
        if (!_isInit(rhs)) {
            rhs = asEbool(true);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EBOOL_TFHE, ebool.unwrap(lhs), ebool.unwrap(rhs), FunctionId.and));
    }

    /// @notice Perform the bitwise AND operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise AND
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the AND result
    function and(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.and));
    }

    /// @notice Perform the bitwise AND operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise AND
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the AND result
    function and(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.and));
    }

    /// @notice Perform the bitwise AND operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise AND
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the AND result
    function and(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.and));
    }

    /// @notice Perform the bitwise AND operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise AND
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the AND result
    function and(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.and));
    }

    /// @notice Perform the bitwise AND operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise AND
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the AND result
    function and(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.and));
    }


    /// @notice Perform the bitwise OR operation on two parameters of type ebool
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise OR
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return result of type ebool containing the OR result
    function or(ebool lhs, ebool rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEbool(true);
        }
        if (!_isInit(rhs)) {
            rhs = asEbool(true);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EBOOL_TFHE, ebool.unwrap(lhs), ebool.unwrap(rhs), FunctionId.or));
    }

    /// @notice Perform the bitwise OR operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise OR
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the OR result
    function or(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.or));
    }

    /// @notice Perform the bitwise OR operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise OR
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the OR result
    function or(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.or));
    }

    /// @notice Perform the bitwise OR operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise OR
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the OR result
    function or(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.or));
    }

    /// @notice Perform the bitwise OR operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise OR
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the OR result
    function or(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.or));
    }

    /// @notice Perform the bitwise OR operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise OR
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the OR result
    function or(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.or));
    }


    /// @notice Perform the bitwise XOR operation on two parameters of type ebool
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise XOR
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return result of type ebool containing the XOR result
    function xor(ebool lhs, ebool rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEbool(true);
        }
        if (!_isInit(rhs)) {
            rhs = asEbool(true);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EBOOL_TFHE, ebool.unwrap(lhs), ebool.unwrap(rhs), FunctionId.xor));
    }

    /// @notice Perform the bitwise XOR operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise XOR
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the XOR result
    function xor(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.xor));
    }

    /// @notice Perform the bitwise XOR operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise XOR
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the XOR result
    function xor(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.xor));
    }

    /// @notice Perform the bitwise XOR operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise XOR
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the XOR result
    function xor(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.xor));
    }

    /// @notice Perform the bitwise XOR operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise XOR
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the XOR result
    function xor(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.xor));
    }

    /// @notice Perform the bitwise XOR operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted bitwise XOR
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the XOR result
    function xor(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.xor));
    }


    /// @notice Perform the equality operation on two parameters of type ebool
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return result of type ebool containing the equality result
    function eq(ebool lhs, ebool rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEbool(true);
        }
        if (!_isInit(rhs)) {
            rhs = asEbool(true);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EBOOL_TFHE, ebool.unwrap(lhs), ebool.unwrap(rhs), FunctionId.eq));
    }

    /// @notice Perform the equality operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type ebool containing the equality result
    function eq(euint8 lhs, euint8 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.eq));
    }

    /// @notice Perform the equality operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type ebool containing the equality result
    function eq(euint16 lhs, euint16 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.eq));
    }

    /// @notice Perform the equality operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type ebool containing the equality result
    function eq(euint32 lhs, euint32 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.eq));
    }

    /// @notice Perform the equality operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type ebool containing the equality result
    function eq(euint64 lhs, euint64 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.eq));
    }

    /// @notice Perform the equality operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type ebool containing the equality result
    function eq(euint128 lhs, euint128 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.eq));
    }


    /// @notice Perform the equality operation on two parameters of type eaddress
    /// @dev Verifies that inputs are initialized, performs encrypted equality check
    /// @param lhs input of type eaddress
    /// @param rhs second input of type eaddress
    /// @return result of type ebool containing the equality result
    function eq(eaddress lhs, eaddress rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEaddress(address(0));
        }
        if (!_isInit(rhs)) {
            rhs = asEaddress(address(0));
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EADDRESS_TFHE, eaddress.unwrap(lhs), eaddress.unwrap(rhs), FunctionId.eq));
    }

    /// @notice Perform the inequality operation on two parameters of type ebool
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return result of type ebool containing the inequality result
    function ne(ebool lhs, ebool rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEbool(true);
        }
        if (!_isInit(rhs)) {
            rhs = asEbool(true);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EBOOL_TFHE, ebool.unwrap(lhs), ebool.unwrap(rhs), FunctionId.ne));
    }

    /// @notice Perform the inequality operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type ebool containing the inequality result
    function ne(euint8 lhs, euint8 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.ne));
    }

    /// @notice Perform the inequality operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type ebool containing the inequality result
    function ne(euint16 lhs, euint16 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.ne));
    }

    /// @notice Perform the inequality operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type ebool containing the inequality result
    function ne(euint32 lhs, euint32 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.ne));
    }

    /// @notice Perform the inequality operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type ebool containing the inequality result
    function ne(euint64 lhs, euint64 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.ne));
    }

    /// @notice Perform the inequality operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type ebool containing the inequality result
    function ne(euint128 lhs, euint128 rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.ne));
    }


    /// @notice Perform the inequality operation on two parameters of type eaddress
    /// @dev Verifies that inputs are initialized, performs encrypted inequality check
    /// @param lhs input of type eaddress
    /// @param rhs second input of type eaddress
    /// @return result of type ebool containing the inequality result
    function ne(eaddress lhs, eaddress rhs) internal returns (ebool) {
        if (!_isInit(lhs)) {
            lhs = asEaddress(address(0));
        }
        if (!_isInit(rhs)) {
            rhs = asEaddress(address(0));
        }

        return ebool.wrap(FHENetwork.mathOp(Utils.EADDRESS_TFHE, eaddress.unwrap(lhs), eaddress.unwrap(rhs), FunctionId.ne));
    }

    /// @notice Perform the minimum operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted minimum comparison
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the minimum value
    function min(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.min));
    }

    /// @notice Perform the minimum operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted minimum comparison
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the minimum value
    function min(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.min));
    }

    /// @notice Perform the minimum operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted minimum comparison
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the minimum value
    function min(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.min));
    }

    /// @notice Perform the minimum operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted minimum comparison
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the minimum value
    function min(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.min));
    }

    /// @notice Perform the minimum operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted minimum comparison
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the minimum value
    function min(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.min));
    }


    /// @notice Perform the maximum operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted maximum calculation
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the maximum result
    function max(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.max));
    }

    /// @notice Perform the maximum operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted maximum calculation
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the maximum result
    function max(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.max));
    }

    /// @notice Perform the maximum operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted maximum calculation
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the maximum result
    function max(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.max));
    }

    /// @notice Perform the maximum operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted maximum comparison
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the maximum value
    function max(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.max));
    }

    /// @notice Perform the maximum operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted maximum comparison
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the maximum value
    function max(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.max));
    }


    /// @notice Perform the shift left operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted left shift
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the left shift result
    function shl(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.shl));
    }

    /// @notice Perform the shift left operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted left shift
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the left shift result
    function shl(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.shl));
    }

    /// @notice Perform the shift left operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted left shift
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the left shift result
    function shl(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.shl));
    }

    /// @notice Perform the shift left operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted left shift
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the left shift result
    function shl(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.shl));
    }

    /// @notice Perform the shift left operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted left shift
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the left shift result
    function shl(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.shl));
    }


    /// @notice Perform the shift right operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted right shift
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the right shift result
    function shr(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.shr));
    }

    /// @notice Perform the shift right operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted right shift
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the right shift result
    function shr(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.shr));
    }

    /// @notice Perform the shift right operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted right shift
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the right shift result
    function shr(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.shr));
    }

    /// @notice Perform the shift right operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted right shift
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the right shift result
    function shr(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.shr));
    }

    /// @notice Perform the shift right operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted right shift
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the right shift result
    function shr(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.shr));
    }


    /// @notice Perform the rol operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted left rotation
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the left rotation result
    function rol(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.rol));
    }

    /// @notice Perform the rotate left operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted left rotation
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the left rotation result
    function rol(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.rol));
    }

    /// @notice Perform the rotate left operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted left rotation
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the left rotation result
    function rol(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.rol));
    }

    /// @notice Perform the rotate left operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted left rotation
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the left rotation result
    function rol(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.rol));
    }

    /// @notice Perform the rotate left operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted left rotation
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the left rotation result
    function rol(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.rol));
    }


    /// @notice Perform the rotate right operation on two parameters of type euint8
    /// @dev Verifies that inputs are initialized, performs encrypted right rotation
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return result of type euint8 containing the right rotation result
    function ror(euint8 lhs, euint8 rhs) internal returns (euint8) {
        if (!_isInit(lhs)) {
            lhs = asEuint8(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.mathOp(Utils.EUINT8_TFHE, euint8.unwrap(lhs), euint8.unwrap(rhs), FunctionId.ror));
    }

    /// @notice Perform the rotate right operation on two parameters of type euint16
    /// @dev Verifies that inputs are initialized, performs encrypted right rotation
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return result of type euint16 containing the right rotation result
    function ror(euint16 lhs, euint16 rhs) internal returns (euint16) {
        if (!_isInit(lhs)) {
            lhs = asEuint16(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.mathOp(Utils.EUINT16_TFHE, euint16.unwrap(lhs), euint16.unwrap(rhs), FunctionId.ror));
    }

    /// @notice Perform the rotate right operation on two parameters of type euint32
    /// @dev Verifies that inputs are initialized, performs encrypted right rotation
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return result of type euint32 containing the right rotation result
    function ror(euint32 lhs, euint32 rhs) internal returns (euint32) {
        if (!_isInit(lhs)) {
            lhs = asEuint32(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.mathOp(Utils.EUINT32_TFHE, euint32.unwrap(lhs), euint32.unwrap(rhs), FunctionId.ror));
    }

    /// @notice Perform the rotate right operation on two parameters of type euint64
    /// @dev Verifies that inputs are initialized, performs encrypted right rotation
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return result of type euint64 containing the right rotation result
    function ror(euint64 lhs, euint64 rhs) internal returns (euint64) {
        if (!_isInit(lhs)) {
            lhs = asEuint64(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.mathOp(Utils.EUINT64_TFHE, euint64.unwrap(lhs), euint64.unwrap(rhs), FunctionId.ror));
    }

    /// @notice Perform the rotate right operation on two parameters of type euint128
    /// @dev Verifies that inputs are initialized, performs encrypted right rotation
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return result of type euint128 containing the right rotation result
    function ror(euint128 lhs, euint128 rhs) internal returns (euint128) {
        if (!_isInit(lhs)) {
            lhs = asEuint128(0);
        }
        if (!_isInit(rhs)) {
            rhs = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.mathOp(Utils.EUINT128_TFHE, euint128.unwrap(lhs), euint128.unwrap(rhs), FunctionId.ror));
    }


    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(ebool input1) internal {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }

        ebool.wrap(FHENetwork.decrypt(ebool.unwrap(input1)));
    }
    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(euint8 input1) internal {
        if (!_isInit(input1)) {
            input1 = asEuint8(0);
        }

        euint8.wrap(FHENetwork.decrypt(euint8.unwrap(input1)));
    }
    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(euint16 input1) internal {
        if (!_isInit(input1)) {
            input1 = asEuint16(0);
        }

        euint16.wrap(FHENetwork.decrypt(euint16.unwrap(input1)));
    }
    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(euint32 input1) internal {
        if (!_isInit(input1)) {
            input1 = asEuint32(0);
        }

        euint32.wrap(FHENetwork.decrypt(euint32.unwrap(input1)));
    }
    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(euint64 input1) internal {
        if (!_isInit(input1)) {
            input1 = asEuint64(0);
        }

        euint64.wrap(FHENetwork.decrypt(euint64.unwrap(input1)));
    }
    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(euint128 input1) internal {
        if (!_isInit(input1)) {
            input1 = asEuint128(0);
        }

        euint128.wrap(FHENetwork.decrypt(euint128.unwrap(input1)));
    }

    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(euint256 input1) internal {
        if (!_isInit(euint256.unwrap(input1))) {
            input1 = asEuint256(0);
        }

        euint256.wrap(FHENetwork.decrypt(euint256.unwrap(input1)));
    }

    /// @notice Performs the async decrypt operation on a ciphertext
    /// @dev The decrypted output should be asynchronously handled by the IAsyncFHEReceiver implementation
    /// @param input1 the input ciphertext
    function decrypt(eaddress input1) internal {
        if (!_isInit(input1)) {
            input1 = asEaddress(address(0));
        }

        FHENetwork.decrypt(eaddress.unwrap(input1));
    }

    /// @notice Gets the decrypted value from a previously decrypted ebool ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The ebool ciphertext to get the decrypted value from
    /// @return The decrypted boolean value
    function getDecryptResult(ebool input1) internal view returns (bool) {
        uint256 result = FHENetwork.getDecryptResult(ebool.unwrap(input1));
        return result != 0;
    }

    /// @notice Gets the decrypted value from a previously decrypted euint8 ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The euint8 ciphertext to get the decrypted value from
    /// @return The decrypted uint8 value
    function getDecryptResult(euint8 input1) internal view returns (uint8) {
        return uint8(FHENetwork.getDecryptResult(euint8.unwrap(input1)));
    }

    /// @notice Gets the decrypted value from a previously decrypted euint16 ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The euint16 ciphertext to get the decrypted value from
    /// @return The decrypted uint16 value
    function getDecryptResult(euint16 input1) internal view returns (uint16) {
        return uint16(FHENetwork.getDecryptResult(euint16.unwrap(input1)));
    }

    /// @notice Gets the decrypted value from a previously decrypted euint32 ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The euint32 ciphertext to get the decrypted value from
    /// @return The decrypted uint32 value
    function getDecryptResult(euint32 input1) internal view returns (uint32) {
        return uint32(FHENetwork.getDecryptResult(euint32.unwrap(input1)));
    }

    /// @notice Gets the decrypted value from a previously decrypted euint64 ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The euint64 ciphertext to get the decrypted value from
    /// @return The decrypted uint64 value
    function getDecryptResult(euint64 input1) internal view returns (uint64) {
        return uint64(FHENetwork.getDecryptResult(euint64.unwrap(input1)));
    }

    /// @notice Gets the decrypted value from a previously decrypted euint128 ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The euint128 ciphertext to get the decrypted value from
    /// @return The decrypted uint128 value
    function getDecryptResult(euint128 input1) internal view returns (uint128) {
        return uint128(FHENetwork.getDecryptResult(euint128.unwrap(input1)));
    }

    /// @notice Gets the decrypted value from a previously decrypted eaddress ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The eaddress ciphertext to get the decrypted value from
    /// @return The decrypted address value
    function getDecryptResult(eaddress input1) internal view returns (address) {
        return address(uint160(FHENetwork.getDecryptResult(eaddress.unwrap(input1))));
    }

    /// @notice Gets the decrypted value from a previously decrypted raw ciphertext
    /// @dev This function will revert if the ciphertext is not yet decrypted. Use getDecryptResultSafe for a non-reverting version.
    /// @param input1 The raw ciphertext to get the decrypted value from
    /// @return The decrypted uint256 value
    function getDecryptResult(uint256 input1) internal view returns (uint256) {
        return FHENetwork.getDecryptResult(input1);
    }

    /// @notice Safely gets the decrypted value from an ebool ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The ebool ciphertext to get the decrypted value from
    /// @return result The decrypted boolean value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(ebool input1) internal view returns (bool result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(ebool.unwrap(input1));
        return (_result != 0, _decrypted);
    }

    /// @notice Safely gets the decrypted value from a euint8 ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The euint8 ciphertext to get the decrypted value from
    /// @return result The decrypted uint8 value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(euint8 input1) internal view returns (uint8 result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(euint8.unwrap(input1));
        return (uint8(_result), _decrypted);
    }

    /// @notice Safely gets the decrypted value from a euint16 ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The euint16 ciphertext to get the decrypted value from
    /// @return result The decrypted uint16 value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(euint16 input1) internal view returns (uint16 result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(euint16.unwrap(input1));
        return (uint16(_result), _decrypted);
    }

    /// @notice Safely gets the decrypted value from a euint32 ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The euint32 ciphertext to get the decrypted value from
    /// @return result The decrypted uint32 value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(euint32 input1) internal view returns (uint32 result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(euint32.unwrap(input1));
        return (uint32(_result), _decrypted);
    }

    /// @notice Safely gets the decrypted value from a euint64 ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The euint64 ciphertext to get the decrypted value from
    /// @return result The decrypted uint64 value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(euint64 input1) internal view returns (uint64 result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(euint64.unwrap(input1));
        return (uint64(_result), _decrypted);
    }

    /// @notice Safely gets the decrypted value from a euint128 ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The euint128 ciphertext to get the decrypted value from
    /// @return result The decrypted uint128 value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(euint128 input1) internal view returns (uint128 result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(euint128.unwrap(input1));
        return (uint128(_result), _decrypted);
    }


    /// @notice Safely gets the decrypted value from an eaddress ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The eaddress ciphertext to get the decrypted value from
    /// @return result The decrypted address value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(eaddress input1) internal view returns (address result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(eaddress.unwrap(input1));
        return (address(uint160(_result)), _decrypted);
    }

    /// @notice Safely gets the decrypted value from a raw ciphertext
    /// @dev Returns the decrypted value and a flag indicating whether the decryption has finished
    /// @param input1 The raw ciphertext to get the decrypted value from
    /// @return result The decrypted uint256 value
    /// @return decrypted Flag indicating if the value was successfully decrypted
    function getDecryptResultSafe(uint256 input1) internal view returns (uint256 result, bool decrypted) {
        (uint256 _result, bool _decrypted) = FHENetwork.getDecryptResultSafe(input1);
        return (_result, _decrypted);
    }

    /// @notice Performs a multiplexer operation between two ebool values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type ebool
    /// @param input3 Second choice of type ebool
    /// @return result of type ebool containing the selected value
    function select(ebool input1, ebool input2, ebool input3) internal returns (ebool) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEbool(false);
        }
        if (!_isInit(input3)) {
            input3 = asEbool(false);
        }

        return ebool.wrap(FHENetwork.select(Utils.EBOOL_TFHE, ebool.unwrap(input1), ebool.unwrap(input2), ebool.unwrap(input3)));
    }

    /// @notice Performs a multiplexer operation between two euint8 values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type euint8
    /// @param input3 Second choice of type euint8
    /// @return result of type euint8 containing the selected value
    function select(ebool input1, euint8 input2, euint8 input3) internal returns (euint8) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEuint8(0);
        }
        if (!_isInit(input3)) {
            input3 = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.select(Utils.EUINT8_TFHE, ebool.unwrap(input1), euint8.unwrap(input2), euint8.unwrap(input3)));
    }

    /// @notice Performs a multiplexer operation between two euint16 values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type euint16
    /// @param input3 Second choice of type euint16
    /// @return result of type euint16 containing the selected value
    function select(ebool input1, euint16 input2, euint16 input3) internal returns (euint16) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEuint16(0);
        }
        if (!_isInit(input3)) {
            input3 = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.select(Utils.EUINT16_TFHE, ebool.unwrap(input1), euint16.unwrap(input2), euint16.unwrap(input3)));
    }

    /// @notice Performs a multiplexer operation between two euint32 values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type euint32
    /// @param input3 Second choice of type euint32
    /// @return result of type euint32 containing the selected value
    function select(ebool input1, euint32 input2, euint32 input3) internal returns (euint32) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEuint32(0);
        }
        if (!_isInit(input3)) {
            input3 = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.select(Utils.EUINT32_TFHE, ebool.unwrap(input1), euint32.unwrap(input2), euint32.unwrap(input3)));
    }

    /// @notice Performs a multiplexer operation between two euint64 values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type euint64
    /// @param input3 Second choice of type euint64
    /// @return result of type euint64 containing the selected value
    function select(ebool input1, euint64 input2, euint64 input3) internal returns (euint64) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEuint64(0);
        }
        if (!_isInit(input3)) {
            input3 = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.select(Utils.EUINT64_TFHE, ebool.unwrap(input1), euint64.unwrap(input2), euint64.unwrap(input3)));
    }

    /// @notice Performs a multiplexer operation between two euint128 values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type euint128
    /// @param input3 Second choice of type euint128
    /// @return result of type euint128 containing the selected value
    function select(ebool input1, euint128 input2, euint128 input3) internal returns (euint128) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEuint128(0);
        }
        if (!_isInit(input3)) {
            input3 = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.select(Utils.EUINT128_TFHE, ebool.unwrap(input1), euint128.unwrap(input2), euint128.unwrap(input3)));
    }


    /// @notice Performs a multiplexer operation between two eaddress values based on a selector
    /// @dev If input1 is true, returns input2, otherwise returns input3. All inputs are initialized to defaults if not set.
    /// @param input1 The selector of type ebool
    /// @param input2 First choice of type eaddress
    /// @param input3 Second choice of type eaddress
    /// @return result of type eaddress containing the selected value
    function select(ebool input1, eaddress input2, eaddress input3) internal returns (eaddress) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }
        if (!_isInit(input2)) {
            input2 = asEaddress(address(0));
        }
        if (!_isInit(input3)) {
            input3 = asEaddress(address(0));
        }

        return eaddress.wrap(FHENetwork.select(Utils.EADDRESS_TFHE, ebool.unwrap(input1), eaddress.unwrap(input2), eaddress.unwrap(input3)));
    }

    /// @notice Performs the not operation on a ciphertext
    /// @dev Verifies that the input value matches a valid ciphertext.
    /// @param input1 the input ciphertext
    function not(ebool input1) internal returns (ebool) {
        if (!_isInit(input1)) {
            input1 = asEbool(false);
        }

        return ebool.wrap(FHENetwork.not(Utils.EBOOL_TFHE, ebool.unwrap(input1)));
    }

    /// @notice Performs the not operation on a ciphertext
    /// @dev Verifies that the input value matches a valid ciphertext.
    /// @param input1 the input ciphertext
    function not(euint8 input1) internal returns (euint8) {
        if (!_isInit(input1)) {
            input1 = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.not(Utils.EUINT8_TFHE, euint8.unwrap(input1)));
    }
    /// @notice Performs the not operation on a ciphertext
    /// @dev Verifies that the input value matches a valid ciphertext.
    /// @param input1 the input ciphertext
    function not(euint16 input1) internal returns (euint16) {
        if (!_isInit(input1)) {
            input1 = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.not(Utils.EUINT16_TFHE, euint16.unwrap(input1)));
    }
    /// @notice Performs the not operation on a ciphertext
    /// @dev Verifies that the input value matches a valid ciphertext.
    /// @param input1 the input ciphertext
    function not(euint32 input1) internal returns (euint32) {
        if (!_isInit(input1)) {
            input1 = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.not(Utils.EUINT32_TFHE, euint32.unwrap(input1)));
    }

    /// @notice Performs the bitwise NOT operation on an encrypted 64-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      The operation inverts all bits of the input value.
    /// @param input1 The input ciphertext to negate
    /// @return An euint64 containing the bitwise NOT of the input
    function not(euint64 input1) internal returns (euint64) {
        if (!_isInit(input1)) {
            input1 = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.not(Utils.EUINT64_TFHE, euint64.unwrap(input1)));
    }

    /// @notice Performs the bitwise NOT operation on an encrypted 128-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      The operation inverts all bits of the input value.
    /// @param input1 The input ciphertext to negate
    /// @return An euint128 containing the bitwise NOT of the input
    function not(euint128 input1) internal returns (euint128) {
        if (!_isInit(input1)) {
            input1 = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.not(Utils.EUINT128_TFHE, euint128.unwrap(input1)));
    }


    /// @notice Performs the square operation on an encrypted 8-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      Note: The result may overflow if input * input exceeds 8 bits.
    /// @param input1 The input ciphertext to square
    /// @return An euint8 containing the square of the input
    function square(euint8 input1) internal returns (euint8) {
        if (!_isInit(input1)) {
            input1 = asEuint8(0);
        }

        return euint8.wrap(FHENetwork.square(Utils.EUINT8_TFHE, euint8.unwrap(input1)));
    }

    /// @notice Performs the square operation on an encrypted 16-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      Note: The result may overflow if input * input exceeds 16 bits.
    /// @param input1 The input ciphertext to square
    /// @return An euint16 containing the square of the input
    function square(euint16 input1) internal returns (euint16) {
        if (!_isInit(input1)) {
            input1 = asEuint16(0);
        }

        return euint16.wrap(FHENetwork.square(Utils.EUINT16_TFHE, euint16.unwrap(input1)));
    }

    /// @notice Performs the square operation on an encrypted 32-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      Note: The result may overflow if input * input exceeds 32 bits.
    /// @param input1 The input ciphertext to square
    /// @return An euint32 containing the square of the input
    function square(euint32 input1) internal returns (euint32) {
        if (!_isInit(input1)) {
            input1 = asEuint32(0);
        }

        return euint32.wrap(FHENetwork.square(Utils.EUINT32_TFHE, euint32.unwrap(input1)));
    }

    /// @notice Performs the square operation on an encrypted 64-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      Note: The result may overflow if input * input exceeds 64 bits.
    /// @param input1 The input ciphertext to square
    /// @return An euint64 containing the square of the input
    function square(euint64 input1) internal returns (euint64) {
        if (!_isInit(input1)) {
            input1 = asEuint64(0);
        }

        return euint64.wrap(FHENetwork.square(Utils.EUINT64_TFHE, euint64.unwrap(input1)));
    }

    /// @notice Performs the square operation on an encrypted 128-bit unsigned integer
    /// @dev Verifies that the input is initialized, defaulting to 0 if not.
    ///      Note: The result may overflow if input * input exceeds 128 bits.
    /// @param input1 The input ciphertext to square
    /// @return An euint128 containing the square of the input
    function square(euint128 input1) internal returns (euint128) {
        if (!_isInit(input1)) {
            input1 = asEuint128(0);
        }

        return euint128.wrap(FHENetwork.square(Utils.EUINT128_TFHE, euint128.unwrap(input1)));
    }

    /// @notice Generates a random value of a euint8 type for provided securityZone
    /// @dev Generates a cryptographically secure random 8-bit unsigned integer in encrypted form.
    ///      The generated value is fully encrypted and cannot be predicted by any party.
    /// @param securityZone The security zone identifier to use for random value generation.
    /// @return A randomly generated encrypted 8-bit unsigned integer (euint8)
    function randomEuint8(int32 securityZone) internal returns (euint8) {
        return euint8.wrap(FHENetwork.random(Utils.EUINT8_TFHE, 0, securityZone));
    }
    /// @notice Generates a random value of a euint8 type
    /// @dev Generates a cryptographically secure random 8-bit unsigned integer in encrypted form
    ///      using the default security zone (0). The generated value is fully encrypted and
    ///      cannot be predicted by any party.
    /// @return A randomly generated encrypted 8-bit unsigned integer (euint8)
    function randomEuint8() internal returns (euint8) {
        return randomEuint8(0);
    }
    /// @notice Generates a random value of a euint16 type for provided securityZone
    /// @dev Generates a cryptographically secure random 16-bit unsigned integer in encrypted form.
    ///      The generated value is fully encrypted and cannot be predicted by any party.
    /// @param securityZone The security zone identifier to use for random value generation.
    /// @return A randomly generated encrypted 16-bit unsigned integer (euint16)
    function randomEuint16(int32 securityZone) internal returns (euint16) {
        return euint16.wrap(FHENetwork.random(Utils.EUINT16_TFHE, 0, securityZone));
    }
    /// @notice Generates a random value of a euint16 type
    /// @dev Generates a cryptographically secure random 16-bit unsigned integer in encrypted form
    ///      using the default security zone (0). The generated value is fully encrypted and
    ///      cannot be predicted by any party.
    /// @return A randomly generated encrypted 16-bit unsigned integer (euint16)
    function randomEuint16() internal returns (euint16) {
        return randomEuint16(0);
    }
    /// @notice Generates a random value of a euint32 type for provided securityZone
    /// @dev Generates a cryptographically secure random 32-bit unsigned integer in encrypted form.
    ///      The generated value is fully encrypted and cannot be predicted by any party.
    /// @param securityZone The security zone identifier to use for random value generation.
    /// @return A randomly generated encrypted 32-bit unsigned integer (euint32)
    function randomEuint32(int32 securityZone) internal returns (euint32) {
        return euint32.wrap(FHENetwork.random(Utils.EUINT32_TFHE, 0, securityZone));
    }
    /// @notice Generates a random value of a euint32 type
    /// @dev Generates a cryptographically secure random 32-bit unsigned integer in encrypted form
    ///      using the default security zone (0). The generated value is fully encrypted and
    ///      cannot be predicted by any party.
    /// @return A randomly generated encrypted 32-bit unsigned integer (euint32)
    function randomEuint32() internal returns (euint32) {
        return randomEuint32(0);
    }
    /// @notice Generates a random value of a euint64 type for provided securityZone
    /// @dev Generates a cryptographically secure random 64-bit unsigned integer in encrypted form.
    ///      The generated value is fully encrypted and cannot be predicted by any party.
    /// @param securityZone The security zone identifier to use for random value generation.
    /// @return A randomly generated encrypted 64-bit unsigned integer (euint64)
    function randomEuint64(int32 securityZone) internal returns (euint64) {
        return euint64.wrap(FHENetwork.random(Utils.EUINT64_TFHE, 0, securityZone));
    }
    /// @notice Generates a random value of a euint64 type
    /// @dev Generates a cryptographically secure random 64-bit unsigned integer in encrypted form
    ///      using the default security zone (0). The generated value is fully encrypted and
    ///      cannot be predicted by any party.
    /// @return A randomly generated encrypted 64-bit unsigned integer (euint64)
    function randomEuint64() internal returns (euint64) {
        return randomEuint64(0);
    }
    /// @notice Generates a random value of a euint128 type for provided securityZone
    /// @dev Generates a cryptographically secure random 128-bit unsigned integer in encrypted form.
    ///      The generated value is fully encrypted and cannot be predicted by any party.
    /// @param securityZone The security zone identifier to use for random value generation.
    /// @return A randomly generated encrypted 128-bit unsigned integer (euint128)
    function randomEuint128(int32 securityZone) internal returns (euint128) {
        return euint128.wrap(FHENetwork.random(Utils.EUINT128_TFHE, 0, securityZone));
    }
    /// @notice Generates a random value of a euint128 type
    /// @dev Generates a cryptographically secure random 128-bit unsigned integer in encrypted form
    ///      using the default security zone (0). The generated value is fully encrypted and
    ///      cannot be predicted by any party.
    /// @return A randomly generated encrypted 128-bit unsigned integer (euint128)
    function randomEuint128() internal returns (euint128) {
        return randomEuint128(0);
    }

    /// @notice Verifies and converts an Ebool input to an ebool encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An ebool containing the verified encrypted value
    function asEbool(Ebool memory value) internal returns (ebool) {
        uint8 expectedUtype = Utils.EBOOL_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }

        return ebool.wrap(FHENetwork.verifyInput(Utils.inputFromEbool(value)));
    }

    /// @notice Verifies and converts an Euint8 input to an euint8 encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An euint8 containing the verified encrypted value
    function asEuint8(Euint8 memory value) internal returns (euint8) {
        uint8 expectedUtype = Utils.EUINT8_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }


        return euint8.wrap(FHENetwork.verifyInput(Utils.inputFromEuint8(value)));
    }

    /// @notice Verifies and converts an Euint16 input to an euint16 encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An euint16 containing the verified encrypted value
    function asEuint16(Euint16 memory value) internal returns (euint16) {
        uint8 expectedUtype = Utils.EUINT16_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }


        return euint16.wrap(FHENetwork.verifyInput(Utils.inputFromEuint16(value)));
    }

    /// @notice Verifies and converts an Euint32 input to an euint32 encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An euint32 containing the verified encrypted value
    function asEuint32(Euint32 memory value) internal returns (euint32) {
        uint8 expectedUtype = Utils.EUINT32_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }


        return euint32.wrap(FHENetwork.verifyInput(Utils.inputFromEuint32(value)));
    }

    /// @notice Verifies and converts an Euint64 input to an euint64 encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An euint64 containing the verified encrypted value
    function asEuint64(Euint64 memory value) internal returns (euint64) {
        uint8 expectedUtype = Utils.EUINT64_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }


        return euint64.wrap(FHENetwork.verifyInput(Utils.inputFromEuint64(value)));
    }

    /// @notice Verifies and converts an Euint128 input to an euint128 encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An euint128 containing the verified encrypted value
    function asEuint128(Euint128 memory value) internal returns (euint128) {
        uint8 expectedUtype = Utils.EUINT128_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }


        return euint128.wrap(FHENetwork.verifyInput(Utils.inputFromEuint128(value)));
    }

    /// @notice Verifies and converts an Eaddress input to an eaddress encrypted type
    /// @dev Verifies the input signature and security parameters before converting to the encrypted type
    /// @param value The input value containing hash, type, security zone and signature
    /// @return An eaddress containing the verified encrypted value
    function asEaddress(Eaddress memory value) internal returns (eaddress) {
        uint8 expectedUtype = Utils.EADDRESS_TFHE;
        if (value.utype != expectedUtype) {
            revert InvalidEncryptedInput(value.utype, expectedUtype);
        }


        return eaddress.wrap(FHENetwork.verifyInput(Utils.inputFromEaddress(value)));
    }

    // ********** TYPE CASTING ************* //
    /// @notice Converts a ebool to an euint8
    function asEuint8(ebool value) internal returns (euint8) {
        return euint8.wrap(FHENetwork.cast(ebool.unwrap(value), Utils.EUINT8_TFHE));
    }
    /// @notice Converts a ebool to an euint16
    function asEuint16(ebool value) internal returns (euint16) {
        return euint16.wrap(FHENetwork.cast(ebool.unwrap(value), Utils.EUINT16_TFHE));
    }
    /// @notice Converts a ebool to an euint32
    function asEuint32(ebool value) internal returns (euint32) {
        return euint32.wrap(FHENetwork.cast(ebool.unwrap(value), Utils.EUINT32_TFHE));
    }
    /// @notice Converts a ebool to an euint64
    function asEuint64(ebool value) internal returns (euint64) {
        return euint64.wrap(FHENetwork.cast(ebool.unwrap(value), Utils.EUINT64_TFHE));
    }
    /// @notice Converts a ebool to an euint128
    function asEuint128(ebool value) internal returns (euint128) {
        return euint128.wrap(FHENetwork.cast(ebool.unwrap(value), Utils.EUINT128_TFHE));
    }

    /// @notice Converts a euint8 to an ebool
    function asEbool(euint8 value) internal returns (ebool) {
        return ne(value, asEuint8(0));
    }
    /// @notice Converts a euint8 to an euint16
    function asEuint16(euint8 value) internal returns (euint16) {
        return euint16.wrap(FHENetwork.cast(euint8.unwrap(value), Utils.EUINT16_TFHE));
    }
    /// @notice Converts a euint8 to an euint32
    function asEuint32(euint8 value) internal returns (euint32) {
        return euint32.wrap(FHENetwork.cast(euint8.unwrap(value), Utils.EUINT32_TFHE));
    }
    /// @notice Converts a euint8 to an euint64
    function asEuint64(euint8 value) internal returns (euint64) {
        return euint64.wrap(FHENetwork.cast(euint8.unwrap(value), Utils.EUINT64_TFHE));
    }
    /// @notice Converts a euint8 to an euint128
    function asEuint128(euint8 value) internal returns (euint128) {
        return euint128.wrap(FHENetwork.cast(euint8.unwrap(value), Utils.EUINT128_TFHE));
    }

    /// @notice Converts a euint16 to an ebool
    function asEbool(euint16 value) internal returns (ebool) {
        return ne(value, asEuint16(0));
    }
    /// @notice Converts a euint16 to an euint8
    function asEuint8(euint16 value) internal returns (euint8) {
        return euint8.wrap(FHENetwork.cast(euint16.unwrap(value), Utils.EUINT8_TFHE));
    }
    /// @notice Converts a euint16 to an euint32
    function asEuint32(euint16 value) internal returns (euint32) {
        return euint32.wrap(FHENetwork.cast(euint16.unwrap(value), Utils.EUINT32_TFHE));
    }
    /// @notice Converts a euint16 to an euint64
    function asEuint64(euint16 value) internal returns (euint64) {
        return euint64.wrap(FHENetwork.cast(euint16.unwrap(value), Utils.EUINT64_TFHE));
    }
    /// @notice Converts a euint16 to an euint128
    function asEuint128(euint16 value) internal returns (euint128) {
        return euint128.wrap(FHENetwork.cast(euint16.unwrap(value), Utils.EUINT128_TFHE));
    }

    /// @notice Converts a euint32 to an ebool
    function asEbool(euint32 value) internal returns (ebool) {
        return ne(value, asEuint32(0));
    }
    /// @notice Converts a euint32 to an euint8
    function asEuint8(euint32 value) internal returns (euint8) {
        return euint8.wrap(FHENetwork.cast(euint32.unwrap(value), Utils.EUINT8_TFHE));
    }
    /// @notice Converts a euint32 to an euint16
    function asEuint16(euint32 value) internal returns (euint16) {
        return euint16.wrap(FHENetwork.cast(euint32.unwrap(value), Utils.EUINT16_TFHE));
    }
    /// @notice Converts a euint32 to an euint64
    function asEuint64(euint32 value) internal returns (euint64) {
        return euint64.wrap(FHENetwork.cast(euint32.unwrap(value), Utils.EUINT64_TFHE));
    }
    /// @notice Converts a euint32 to an euint128
    function asEuint128(euint32 value) internal returns (euint128) {
        return euint128.wrap(FHENetwork.cast(euint32.unwrap(value), Utils.EUINT128_TFHE));
    }

    /// @notice Converts a euint64 to an ebool
    function asEbool(euint64 value) internal returns (ebool) {
        return ne(value, asEuint64(0));
    }
    /// @notice Converts a euint64 to an euint8
    function asEuint8(euint64 value) internal returns (euint8) {
        return euint8.wrap(FHENetwork.cast(euint64.unwrap(value), Utils.EUINT8_TFHE));
    }
    /// @notice Converts a euint64 to an euint16
    function asEuint16(euint64 value) internal returns (euint16) {
        return euint16.wrap(FHENetwork.cast(euint64.unwrap(value), Utils.EUINT16_TFHE));
    }
    /// @notice Converts a euint64 to an euint32
    function asEuint32(euint64 value) internal returns (euint32) {
        return euint32.wrap(FHENetwork.cast(euint64.unwrap(value), Utils.EUINT32_TFHE));
    }
    /// @notice Converts a euint64 to an euint128
    function asEuint128(euint64 value) internal returns (euint128) {
        return euint128.wrap(FHENetwork.cast(euint64.unwrap(value), Utils.EUINT128_TFHE));
    }

    /// @notice Converts a euint128 to an ebool
    function asEbool(euint128 value) internal returns (ebool) {
        return ne(value, asEuint128(0));
    }
    /// @notice Converts a euint128 to an euint8
    function asEuint8(euint128 value) internal returns (euint8) {
        return euint8.wrap(FHENetwork.cast(euint128.unwrap(value), Utils.EUINT8_TFHE));
    }
    /// @notice Converts a euint128 to an euint16
    function asEuint16(euint128 value) internal returns (euint16) {
        return euint16.wrap(FHENetwork.cast(euint128.unwrap(value), Utils.EUINT16_TFHE));
    }
    /// @notice Converts a euint128 to an euint32
    function asEuint32(euint128 value) internal returns (euint32) {
        return euint32.wrap(FHENetwork.cast(euint128.unwrap(value), Utils.EUINT32_TFHE));
    }
    /// @notice Converts a euint128 to an euint64
    function asEuint64(euint128 value) internal returns (euint64) {
        return euint64.wrap(FHENetwork.cast(euint128.unwrap(value), Utils.EUINT64_TFHE));
    }

    /// @notice Converts a eaddress to an ebool
    function asEbool(eaddress value) internal returns (ebool) {
        return ne(value, asEaddress(address(0)));
    }
    /// @notice Converts a eaddress to an euint8
    function asEuint8(eaddress value) internal returns (euint8) {
        return euint8.wrap(FHENetwork.cast(eaddress.unwrap(value), Utils.EUINT8_TFHE));
    }
    /// @notice Converts a eaddress to an euint16
    function asEuint16(eaddress value) internal returns (euint16) {
        return euint16.wrap(FHENetwork.cast(eaddress.unwrap(value), Utils.EUINT16_TFHE));
    }
    /// @notice Converts a eaddress to an euint32
    function asEuint32(eaddress value) internal returns (euint32) {
        return euint32.wrap(FHENetwork.cast(eaddress.unwrap(value), Utils.EUINT32_TFHE));
    }
    /// @notice Converts a eaddress to an euint64
    function asEuint64(eaddress value) internal returns (euint64) {
        return euint64.wrap(FHENetwork.cast(eaddress.unwrap(value), Utils.EUINT64_TFHE));
    }
    /// @notice Converts a eaddress to an euint128
    function asEuint128(eaddress value) internal returns (euint128) {
        return euint128.wrap(FHENetwork.cast(eaddress.unwrap(value), Utils.EUINT128_TFHE));
    }
    /// @notice Converts a plaintext boolean value to a ciphertext ebool
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    /// @return A ciphertext representation of the input
    function asEbool(bool value) internal returns (ebool) {
        return asEbool(value, 0);
    }
    /// @notice Converts a plaintext boolean value to a ciphertext ebool, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    /// @return A ciphertext representation of the input
    function asEbool(bool value, int32 securityZone) internal returns (ebool) {
        uint256 sVal = 0;
        if (value) {
            sVal = 1;
        }
        uint256 ct = FHENetwork.trivialEncrypt(sVal, Utils.EBOOL_TFHE, securityZone);
        return ebool.wrap(ct);
    }
    /// @notice Converts a uint256 to an euint8
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint8(uint256 value) internal returns (euint8) {
        return asEuint8(value, 0);
    }
    /// @notice Converts a uint256 to an euint8, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint8(uint256 value, int32 securityZone) internal returns (euint8) {
        uint256 ct = FHENetwork.trivialEncrypt(value, Utils.EUINT8_TFHE, securityZone);
        return euint8.wrap(ct);
    }
    /// @notice Converts a uint256 to an euint16
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint16(uint256 value) internal returns (euint16) {
        return asEuint16(value, 0);
    }
    /// @notice Converts a uint256 to an euint16, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint16(uint256 value, int32 securityZone) internal returns (euint16) {
        uint256 ct = FHENetwork.trivialEncrypt(value, Utils.EUINT16_TFHE, securityZone);
        return euint16.wrap(ct);
    }
    /// @notice Converts a uint256 to an euint32
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint32(uint256 value) internal returns (euint32) {
        return asEuint32(value, 0);
    }
    /// @notice Converts a uint256 to an euint32, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint32(uint256 value, int32 securityZone) internal returns (euint32) {
        uint256 ct = FHENetwork.trivialEncrypt(value, Utils.EUINT32_TFHE, securityZone);
        return euint32.wrap(ct);
    }
    /// @notice Converts a uint256 to an euint64
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint64(uint256 value) internal returns (euint64) {
        return asEuint64(value, 0);
    }
    /// @notice Converts a uint256 to an euint64, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint64(uint256 value, int32 securityZone) internal returns (euint64) {
        uint256 ct = FHENetwork.trivialEncrypt(value, Utils.EUINT64_TFHE, securityZone);
        return euint64.wrap(ct);
    }
    /// @notice Converts a uint256 to an euint128
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint128(uint256 value) internal returns (euint128) {
        return asEuint128(value, 0);
    }
    /// @notice Converts a uint256 to an euint128, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint128(uint256 value, int32 securityZone) internal returns (euint128) {
        uint256 ct = FHENetwork.trivialEncrypt(value, Utils.EUINT128_TFHE, securityZone);
        return euint128.wrap(ct);
    }
    /// @notice Converts a uint256 to an euint256
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint256(uint256 value) internal returns (euint256) {
        return asEuint256(value, 0);
    }
    /// @notice Converts a uint256 to an euint256, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    function asEuint256(uint256 value, int32 securityZone) internal returns (euint256) {
        uint256 ct = FHENetwork.trivialEncrypt(value, Utils.EUINT256_TFHE, securityZone);
        return euint256.wrap(ct);
    }
    /// @notice Converts a address to an eaddress
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    /// Allows for a better user experience when working with eaddresses
    function asEaddress(address value) internal returns (eaddress) {
        return asEaddress(value, 0);
    }
    /// @notice Converts a address to an eaddress, specifying security zone
    /// @dev Privacy: The input value is public, therefore the resulting ciphertext should be considered public until involved in an fhe operation
    /// Allows for a better user experience when working with eaddresses
    function asEaddress(address value, int32 securityZone) internal returns (eaddress) {
        uint256 ct = FHENetwork.trivialEncrypt(uint256(uint160(value)), Utils.EADDRESS_TFHE, securityZone);
        return eaddress.wrap(ct);
    }

    // ======== Encrypted Input (einput) Conversion Functions ========
    
    /// @notice Converts an encrypted input to ebool
    /// @param encryptedInput The encrypted input handle
    /// @param inputProof The ZK proof validating the input
    /// @return An ebool containing the verified encrypted value
    function asEbool(einput encryptedInput, bytes memory inputProof) internal returns (ebool) {
        return ebool.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EBOOL_TFHE));
    }

    /// @notice Converts an encrypted input to euint8
    function asEuint8(einput encryptedInput, bytes memory inputProof) internal returns (euint8) {
        return euint8.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EUINT8_TFHE));
    }

    /// @notice Converts an encrypted input to euint16
    function asEuint16(einput encryptedInput, bytes memory inputProof) internal returns (euint16) {
        return euint16.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EUINT16_TFHE));
    }

    /// @notice Converts an encrypted input to euint32
    function asEuint32(einput encryptedInput, bytes memory inputProof) internal returns (euint32) {
        return euint32.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EUINT32_TFHE));
    }

    /// @notice Converts an encrypted input to euint64
    function asEuint64(einput encryptedInput, bytes memory inputProof) internal returns (euint64) {
        return euint64.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EUINT64_TFHE));
    }

    /// @notice Converts an encrypted input to euint128
    function asEuint128(einput encryptedInput, bytes memory inputProof) internal returns (euint128) {
        return euint128.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EUINT128_TFHE));
    }

    /// @notice Converts an encrypted input to euint256
    function asEuint256(einput encryptedInput, bytes memory inputProof) internal returns (euint256) {
        return euint256.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EUINT256_TFHE));
    }

    /// @notice Converts a euint128 to an euint256
    function asEuint256(euint128 value) internal returns (euint256) {
        return euint256.wrap(FHENetwork.cast(euint128.unwrap(value), Utils.EUINT256_TFHE));
    }

    /// @notice Converts an encrypted input to eaddress
    function asEaddress(einput encryptedInput, bytes memory inputProof) internal returns (eaddress) {
        return eaddress.wrap(FHENetwork.verifyInput(uint256(einput.unwrap(encryptedInput)), inputProof, Utils.EADDRESS_TFHE));
    }

    /// @notice Grants permission to an account to operate on the encrypted boolean value
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted boolean value to grant access to
    /// @param account The address being granted permission
    function allow(ebool ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(ebool.unwrap(ctHash), account);
    }

    /// @notice Grants permission to an account to operate on the encrypted 8-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted uint8 value to grant access to
    /// @param account The address being granted permission
    function allow(euint8 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint8.unwrap(ctHash), account);
    }

    /// @notice Grants permission to an account to operate on the encrypted 16-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted uint16 value to grant access to
    /// @param account The address being granted permission
    function allow(euint16 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint16.unwrap(ctHash), account);
    }

    /// @notice Grants permission to an account to operate on the encrypted 32-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted uint32 value to grant access to
    /// @param account The address being granted permission
    function allow(euint32 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint32.unwrap(ctHash), account);
    }

    /// @notice Grants permission to an account to operate on the encrypted 64-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted uint64 value to grant access to
    /// @param account The address being granted permission
    function allow(euint64 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint64.unwrap(ctHash), account);
    }

    /// @notice Grants permission to an account to operate on the encrypted 128-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted uint128 value to grant access to
    /// @param account The address being granted permission
    function allow(euint128 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint128.unwrap(ctHash), account);
    }

    /// @notice Grants permission to an account to operate on the encrypted address
    /// @dev Allows the specified account to access the ciphertext
    /// @param ctHash The encrypted address value to grant access to
    /// @param account The address being granted permission
    function allow(eaddress ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(eaddress.unwrap(ctHash), account);
    }

    /// @notice Grants global permission to operate on the encrypted boolean value
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted boolean value to grant global access to
    function allowGlobal(ebool ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(ebool.unwrap(ctHash));
    }

    /// @notice Grants global permission to operate on the encrypted 8-bit unsigned integer
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted uint8 value to grant global access to
    function allowGlobal(euint8 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(euint8.unwrap(ctHash));
    }

    /// @notice Grants global permission to operate on the encrypted 16-bit unsigned integer
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted uint16 value to grant global access to
    function allowGlobal(euint16 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(euint16.unwrap(ctHash));
    }

    /// @notice Grants global permission to operate on the encrypted 32-bit unsigned integer
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted uint32 value to grant global access to
    function allowGlobal(euint32 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(euint32.unwrap(ctHash));
    }

    /// @notice Grants global permission to operate on the encrypted 64-bit unsigned integer
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted uint64 value to grant global access to
    function allowGlobal(euint64 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(euint64.unwrap(ctHash));
    }

    /// @notice Grants global permission to operate on the encrypted 128-bit unsigned integer
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted uint128 value to grant global access to
    function allowGlobal(euint128 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(euint128.unwrap(ctHash));
    }

    /// @notice Grants global permission to operate on the encrypted address
    /// @dev Allows all accounts to access the ciphertext
    /// @param ctHash The encrypted address value to grant global access to
    function allowGlobal(eaddress ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowGlobal(eaddress.unwrap(ctHash));
    }

    /// @notice Checks if an account has permission to operate on the encrypted boolean value
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted boolean value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(ebool ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(ebool.unwrap(ctHash), account);
    }

    /// @notice Checks if an account has permission to operate on the encrypted 8-bit unsigned integer
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted uint8 value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(euint8 ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(euint8.unwrap(ctHash), account);
    }

    /// @notice Checks if an account has permission to operate on the encrypted 16-bit unsigned integer
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted uint16 value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(euint16 ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(euint16.unwrap(ctHash), account);
    }

    /// @notice Checks if an account has permission to operate on the encrypted 32-bit unsigned integer
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted uint32 value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(euint32 ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(euint32.unwrap(ctHash), account);
    }

    /// @notice Checks if an account has permission to operate on the encrypted 64-bit unsigned integer
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted uint64 value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(euint64 ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(euint64.unwrap(ctHash), account);
    }

    /// @notice Checks if an account has permission to operate on the encrypted 128-bit unsigned integer
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted uint128 value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(euint128 ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(euint128.unwrap(ctHash), account);
    }


    /// @notice Checks if an account has permission to operate on the encrypted address
    /// @dev Returns whether the specified account can access the ciphertext
    /// @param ctHash The encrypted address value to check access for
    /// @param account The address to check permissions for
    /// @return True if the account has permission, false otherwise
    function isAllowed(eaddress ctHash, address account) internal returns (bool) {
        return ITaskManager(T_CHAIN_FHE_ADDRESS).isAllowed(eaddress.unwrap(ctHash), account);
    }

    // isSenderAllowed functions - check if msg.sender is allowed
    function isSenderAllowed(ebool ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }
    function isSenderAllowed(euint8 ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }
    function isSenderAllowed(euint16 ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }
    function isSenderAllowed(euint32 ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }
    function isSenderAllowed(euint64 ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }
    function isSenderAllowed(euint128 ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }
    function isSenderAllowed(eaddress ctHash) internal returns (bool) {
        return isAllowed(ctHash, msg.sender);
    }

    /// @notice Grants permission to the current contract to operate on the encrypted boolean value
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted boolean value to grant access to
    function allowThis(ebool ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(ebool.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the current contract to operate on the encrypted 8-bit unsigned integer
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted uint8 value to grant access to
    function allowThis(euint8 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint8.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the current contract to operate on the encrypted 16-bit unsigned integer
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted uint16 value to grant access to
    function allowThis(euint16 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint16.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the current contract to operate on the encrypted 32-bit unsigned integer
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted uint32 value to grant access to
    function allowThis(euint32 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint32.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the current contract to operate on the encrypted 64-bit unsigned integer
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted uint64 value to grant access to
    function allowThis(euint64 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint64.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the current contract to operate on the encrypted 128-bit unsigned integer
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted uint128 value to grant access to
    function allowThis(euint128 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint128.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the current contract to operate on the encrypted address
    /// @dev Allows this contract to access the ciphertext
    /// @param ctHash The encrypted address value to grant access to
    function allowThis(eaddress ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(eaddress.unwrap(ctHash), address(this));
    }

    /// @notice Grants permission to the message sender to operate on the encrypted boolean value
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted boolean value to grant access to
    function allowSender(ebool ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(ebool.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants permission to the message sender to operate on the encrypted 8-bit unsigned integer
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted uint8 value to grant access to
    function allowSender(euint8 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint8.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants permission to the message sender to operate on the encrypted 16-bit unsigned integer
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted uint16 value to grant access to
    function allowSender(euint16 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint16.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants permission to the message sender to operate on the encrypted 32-bit unsigned integer
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted uint32 value to grant access to
    function allowSender(euint32 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint32.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants permission to the message sender to operate on the encrypted 64-bit unsigned integer
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted uint64 value to grant access to
    function allowSender(euint64 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint64.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants permission to the message sender to operate on the encrypted 128-bit unsigned integer
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted uint128 value to grant access to
    function allowSender(euint128 ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(euint128.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants permission to the message sender to operate on the encrypted address
    /// @dev Allows the transaction sender to access the ciphertext
    /// @param ctHash The encrypted address value to grant access to
    function allowSender(eaddress ctHash) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allow(eaddress.unwrap(ctHash), msg.sender);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted boolean value
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted boolean value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(ebool ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(ebool.unwrap(ctHash), account);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted 8-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted uint8 value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(euint8 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(euint8.unwrap(ctHash), account);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted 16-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted uint16 value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(euint16 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(euint16.unwrap(ctHash), account);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted 32-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted uint32 value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(euint32 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(euint32.unwrap(ctHash), account);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted 64-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted uint64 value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(euint64 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(euint64.unwrap(ctHash), account);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted 128-bit unsigned integer
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted uint128 value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(euint128 ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(euint128.unwrap(ctHash), account);
    }

    /// @notice Grants temporary permission to an account to operate on the encrypted address
    /// @dev Allows the specified account to access the ciphertext for the current transaction only
    /// @param ctHash The encrypted address value to grant temporary access to
    /// @param account The address being granted temporary permission
    function allowTransient(eaddress ctHash, address account) internal {
        ITaskManager(T_CHAIN_FHE_ADDRESS).allowTransient(eaddress.unwrap(ctHash), account);
    }

    // ********** SEALED OUTPUTS ************* //

    /// @notice Seals an encrypted value for off-chain transmission
    function sealoutput(ebool value, bytes32 sealingKey) internal view returns (bytes memory) {
        // Call the task manager to create a seal output task
        uint256 hash = ebool.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    function sealoutput(euint8 value, bytes32 sealingKey) internal view returns (bytes memory) {
        uint256 hash = euint8.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    function sealoutput(euint16 value, bytes32 sealingKey) internal view returns (bytes memory) {
        uint256 hash = euint16.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    function sealoutput(euint32 value, bytes32 sealingKey) internal view returns (bytes memory) {
        uint256 hash = euint32.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    function sealoutput(euint64 value, bytes32 sealingKey) internal view returns (bytes memory) {
        uint256 hash = euint64.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    function sealoutput(euint128 value, bytes32 sealingKey) internal view returns (bytes memory) {
        uint256 hash = euint128.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    function sealoutput(eaddress value, bytes32 sealingKey) internal view returns (bytes memory) {
        uint256 hash = eaddress.unwrap(value);
        return abi.encode(hash, sealingKey);
    }

    /// @notice Seals an encrypted boolean for off-chain transmission
    /// @param value The encrypted boolean value
    /// @param sealingKey The key to use for sealing
    /// @return A sealed boolean
    function sealoutputTyped(ebool value, bytes32 sealingKey) internal view returns (SealedBool memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedBool({data: sealedBytes});
    }

    /// @notice Seals an encrypted uint8 for off-chain transmission
    /// @param value The encrypted uint8 value
    /// @param sealingKey The key to use for sealing
    /// @return A sealed uint
    function sealoutputTyped(euint8 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedUint({data: sealedBytes, utype: Utils.EUINT8_TFHE});
    }

    /// @notice Seals an encrypted uint16 for off-chain transmission
    function sealoutputTyped(euint16 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedUint({data: sealedBytes, utype: Utils.EUINT16_TFHE});
    }

    /// @notice Seals an encrypted uint32 for off-chain transmission
    function sealoutputTyped(euint32 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedUint({data: sealedBytes, utype: Utils.EUINT32_TFHE});
    }

    /// @notice Seals an encrypted uint64 for off-chain transmission
    function sealoutputTyped(euint64 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedUint({data: sealedBytes, utype: Utils.EUINT64_TFHE});
    }

    /// @notice Seals an encrypted uint128 for off-chain transmission
    function sealoutputTyped(euint128 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedUint({data: sealedBytes, utype: Utils.EUINT128_TFHE});
    }

    /// @notice Seals an encrypted address for off-chain transmission
    function sealoutputTyped(eaddress value, bytes32 sealingKey) internal view returns (SealedAddress memory) {
        bytes memory sealedBytes = sealoutput(value, sealingKey);
        return SealedAddress({data: sealedBytes});
    }
}

// ********** BINDING DEFS ************* //

using BindingsEbool for ebool global;
library BindingsEbool {

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return the result of the eq
    function eq(ebool lhs, ebool rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return the result of the ne
    function ne(ebool lhs, ebool rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }

    /// @notice Performs the not operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type ebool
    /// @return the result of the not
    function not(ebool lhs) internal returns (ebool) {
        return FHE.not(lhs);
    }

    /// @notice Performs the and operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return the result of the and
    function and(ebool lhs, ebool rhs) internal returns (ebool) {
        return FHE.and(lhs, rhs);
    }

    /// @notice Performs the or operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return the result of the or
    function or(ebool lhs, ebool rhs) internal returns (ebool) {
        return FHE.or(lhs, rhs);
    }

    /// @notice Performs the xor operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type ebool
    /// @param rhs second input of type ebool
    /// @return the result of the xor
    function xor(ebool lhs, ebool rhs) internal returns (ebool) {
        return FHE.xor(lhs, rhs);
    }
    function toU8(ebool value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }
    function toU16(ebool value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }
    function toU32(ebool value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }
    function toU64(ebool value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }
    function toU128(ebool value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }
    function decrypt(ebool value) internal {
        FHE.decrypt(value);
    }
    function allow(ebool ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(ebool ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(ebool ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(ebool ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(ebool ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(ebool ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(ebool value, bytes32 sealingKey) internal view returns (SealedBool memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}

using BindingsEuint8 for euint8 global;
library BindingsEuint8 {

    /// @notice Performs the add operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the add
    function add(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.add(lhs, rhs);
    }

    /// @notice Performs the mul operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the mul
    function mul(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.mul(lhs, rhs);
    }

    /// @notice Performs the div operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the div
    function div(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.div(lhs, rhs);
    }

    /// @notice Performs the sub operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the sub
    function sub(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.sub(lhs, rhs);
    }

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the eq
    function eq(euint8 lhs, euint8 rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the ne
    function ne(euint8 lhs, euint8 rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }

    /// @notice Performs the not operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @return the result of the not
    function not(euint8 lhs) internal returns (euint8) {
        return FHE.not(lhs);
    }

    /// @notice Performs the and operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the and
    function and(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.and(lhs, rhs);
    }

    /// @notice Performs the or operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the or
    function or(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.or(lhs, rhs);
    }

    /// @notice Performs the xor operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the xor
    function xor(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.xor(lhs, rhs);
    }

    /// @notice Performs the gt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the gt
    function gt(euint8 lhs, euint8 rhs) internal returns (ebool) {
        return FHE.gt(lhs, rhs);
    }

    /// @notice Performs the gte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the gte
    function gte(euint8 lhs, euint8 rhs) internal returns (ebool) {
        return FHE.gte(lhs, rhs);
    }

    /// @notice Performs the lt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the lt
    function lt(euint8 lhs, euint8 rhs) internal returns (ebool) {
        return FHE.lt(lhs, rhs);
    }

    /// @notice Performs the lte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the lte
    function lte(euint8 lhs, euint8 rhs) internal returns (ebool) {
        return FHE.lte(lhs, rhs);
    }

    /// @notice Performs the rem operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the rem
    function rem(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.rem(lhs, rhs);
    }

    /// @notice Performs the max operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the max
    function max(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.max(lhs, rhs);
    }

    /// @notice Performs the min operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the min
    function min(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.min(lhs, rhs);
    }

    /// @notice Performs the shl operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the shl
    function shl(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.shl(lhs, rhs);
    }

    /// @notice Performs the shr operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the shr
    function shr(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.shr(lhs, rhs);
    }

    /// @notice Performs the rol operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the rol
    function rol(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.rol(lhs, rhs);
    }

    /// @notice Performs the ror operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @param rhs second input of type euint8
    /// @return the result of the ror
    function ror(euint8 lhs, euint8 rhs) internal returns (euint8) {
        return FHE.ror(lhs, rhs);
    }

    /// @notice Performs the square operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint8
    /// @return the result of the square
    function square(euint8 lhs) internal returns (euint8) {
        return FHE.square(lhs);
    }
    function toBool(euint8 value) internal  returns (ebool) {
        return FHE.asEbool(value);
    }
    function toU16(euint8 value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }
    function toU32(euint8 value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }
    function toU64(euint8 value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }
    function toU128(euint8 value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }
    function decrypt(euint8 value) internal {
        FHE.decrypt(value);
    }
    function allow(euint8 ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(euint8 ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(euint8 ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(euint8 ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(euint8 ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(euint8 ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(euint8 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}

using BindingsEuint16 for euint16 global;
library BindingsEuint16 {

    /// @notice Performs the add operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the add
    function add(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.add(lhs, rhs);
    }

    /// @notice Performs the mul operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the mul
    function mul(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.mul(lhs, rhs);
    }

    /// @notice Performs the div operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the div
    function div(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.div(lhs, rhs);
    }

    /// @notice Performs the sub operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the sub
    function sub(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.sub(lhs, rhs);
    }

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the eq
    function eq(euint16 lhs, euint16 rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the ne
    function ne(euint16 lhs, euint16 rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }

    /// @notice Performs the not operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @return the result of the not
    function not(euint16 lhs) internal returns (euint16) {
        return FHE.not(lhs);
    }

    /// @notice Performs the and operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the and
    function and(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.and(lhs, rhs);
    }

    /// @notice Performs the or operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the or
    function or(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.or(lhs, rhs);
    }

    /// @notice Performs the xor operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the xor
    function xor(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.xor(lhs, rhs);
    }

    /// @notice Performs the gt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the gt
    function gt(euint16 lhs, euint16 rhs) internal returns (ebool) {
        return FHE.gt(lhs, rhs);
    }

    /// @notice Performs the gte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the gte
    function gte(euint16 lhs, euint16 rhs) internal returns (ebool) {
        return FHE.gte(lhs, rhs);
    }

    /// @notice Performs the lt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the lt
    function lt(euint16 lhs, euint16 rhs) internal returns (ebool) {
        return FHE.lt(lhs, rhs);
    }

    /// @notice Performs the lte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the lte
    function lte(euint16 lhs, euint16 rhs) internal returns (ebool) {
        return FHE.lte(lhs, rhs);
    }

    /// @notice Performs the rem operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the rem
    function rem(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.rem(lhs, rhs);
    }

    /// @notice Performs the max operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the max
    function max(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.max(lhs, rhs);
    }

    /// @notice Performs the min operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the min
    function min(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.min(lhs, rhs);
    }

    /// @notice Performs the shl operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the shl
    function shl(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.shl(lhs, rhs);
    }

    /// @notice Performs the shr operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the shr
    function shr(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.shr(lhs, rhs);
    }

    /// @notice Performs the rol operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the rol
    function rol(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.rol(lhs, rhs);
    }

    /// @notice Performs the ror operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @param rhs second input of type euint16
    /// @return the result of the ror
    function ror(euint16 lhs, euint16 rhs) internal returns (euint16) {
        return FHE.ror(lhs, rhs);
    }

    /// @notice Performs the square operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint16
    /// @return the result of the square
    function square(euint16 lhs) internal returns (euint16) {
        return FHE.square(lhs);
    }
    function toBool(euint16 value) internal  returns (ebool) {
        return FHE.asEbool(value);
    }
    function toU8(euint16 value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }
    function toU32(euint16 value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }
    function toU64(euint16 value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }
    function toU128(euint16 value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }
    function decrypt(euint16 value) internal {
        FHE.decrypt(value);
    }
    function allow(euint16 ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(euint16 ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(euint16 ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(euint16 ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(euint16 ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(euint16 ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(euint16 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}

using BindingsEuint32 for euint32 global;
library BindingsEuint32 {

    /// @notice Performs the add operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the add
    function add(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.add(lhs, rhs);
    }

    /// @notice Performs the mul operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the mul
    function mul(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.mul(lhs, rhs);
    }

    /// @notice Performs the div operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the div
    function div(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.div(lhs, rhs);
    }

    /// @notice Performs the sub operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the sub
    function sub(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.sub(lhs, rhs);
    }

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the eq
    function eq(euint32 lhs, euint32 rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the ne
    function ne(euint32 lhs, euint32 rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }

    /// @notice Performs the not operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @return the result of the not
    function not(euint32 lhs) internal returns (euint32) {
        return FHE.not(lhs);
    }

    /// @notice Performs the and operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the and
    function and(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.and(lhs, rhs);
    }

    /// @notice Performs the or operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the or
    function or(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.or(lhs, rhs);
    }

    /// @notice Performs the xor operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the xor
    function xor(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.xor(lhs, rhs);
    }

    /// @notice Performs the gt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the gt
    function gt(euint32 lhs, euint32 rhs) internal returns (ebool) {
        return FHE.gt(lhs, rhs);
    }

    /// @notice Performs the gte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the gte
    function gte(euint32 lhs, euint32 rhs) internal returns (ebool) {
        return FHE.gte(lhs, rhs);
    }

    /// @notice Performs the lt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the lt
    function lt(euint32 lhs, euint32 rhs) internal returns (ebool) {
        return FHE.lt(lhs, rhs);
    }

    /// @notice Performs the lte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the lte
    function lte(euint32 lhs, euint32 rhs) internal returns (ebool) {
        return FHE.lte(lhs, rhs);
    }

    /// @notice Performs the rem operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the rem
    function rem(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.rem(lhs, rhs);
    }

    /// @notice Performs the max operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the max
    function max(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.max(lhs, rhs);
    }

    /// @notice Performs the min operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the min
    function min(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.min(lhs, rhs);
    }

    /// @notice Performs the shl operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the shl
    function shl(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.shl(lhs, rhs);
    }

    /// @notice Performs the shr operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the shr
    function shr(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.shr(lhs, rhs);
    }

    /// @notice Performs the rol operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the rol
    function rol(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.rol(lhs, rhs);
    }

    /// @notice Performs the ror operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @param rhs second input of type euint32
    /// @return the result of the ror
    function ror(euint32 lhs, euint32 rhs) internal returns (euint32) {
        return FHE.ror(lhs, rhs);
    }

    /// @notice Performs the square operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint32
    /// @return the result of the square
    function square(euint32 lhs) internal returns (euint32) {
        return FHE.square(lhs);
    }
    function toBool(euint32 value) internal  returns (ebool) {
        return FHE.asEbool(value);
    }
    function toU8(euint32 value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }
    function toU16(euint32 value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }
    function toU64(euint32 value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }
    function toU128(euint32 value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }
    function decrypt(euint32 value) internal {
        FHE.decrypt(value);
    }
    function allow(euint32 ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(euint32 ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(euint32 ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(euint32 ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(euint32 ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(euint32 ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(euint32 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}

using BindingsEuint64 for euint64 global;
library BindingsEuint64 {

    /// @notice Performs the add operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the add
    function add(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.add(lhs, rhs);
    }

    /// @notice Performs the mul operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the mul
    function mul(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.mul(lhs, rhs);
    }

    /// @notice Performs the sub operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the sub
    function sub(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.sub(lhs, rhs);
    }

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the eq
    function eq(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the ne
    function ne(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }

    /// @notice Performs the not operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @return the result of the not
    function not(euint64 lhs) internal returns (euint64) {
        return FHE.not(lhs);
    }

    /// @notice Performs the and operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the and
    function and(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.and(lhs, rhs);
    }

    /// @notice Performs the or operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the or
    function or(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.or(lhs, rhs);
    }

    /// @notice Performs the xor operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the xor
    function xor(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.xor(lhs, rhs);
    }

    /// @notice Performs the gt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the gt
    function gt(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.gt(lhs, rhs);
    }

    /// @notice Performs the gte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the gte
    function gte(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.gte(lhs, rhs);
    }

    /// @notice Performs the lt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the lt
    function lt(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.lt(lhs, rhs);
    }

    /// @notice Performs the lte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the lte
    function lte(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.lte(lhs, rhs);
    }
    
    /// @notice Alias for lte (less than or equal)
    function le(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.lte(lhs, rhs);
    }
    
    /// @notice Alias for gte (greater than or equal)
    function ge(euint64 lhs, euint64 rhs) internal returns (ebool) {
        return FHE.gte(lhs, rhs);
    }

    /// @notice Performs the max operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the max
    function max(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.max(lhs, rhs);
    }

    /// @notice Performs the min operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the min
    function min(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.min(lhs, rhs);
    }

    /// @notice Performs the shl operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the shl
    function shl(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.shl(lhs, rhs);
    }

    /// @notice Performs the shr operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the shr
    function shr(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.shr(lhs, rhs);
    }

    /// @notice Performs the rol operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the rol
    function rol(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.rol(lhs, rhs);
    }

    /// @notice Performs the ror operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @param rhs second input of type euint64
    /// @return the result of the ror
    function ror(euint64 lhs, euint64 rhs) internal returns (euint64) {
        return FHE.ror(lhs, rhs);
    }

    /// @notice Performs the square operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint64
    /// @return the result of the square
    function square(euint64 lhs) internal returns (euint64) {
        return FHE.square(lhs);
    }
    function toBool(euint64 value) internal  returns (ebool) {
        return FHE.asEbool(value);
    }
    function toU8(euint64 value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }
    function toU16(euint64 value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }
    function toU32(euint64 value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }
    function toU128(euint64 value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }
    function decrypt(euint64 value) internal {
        FHE.decrypt(value);
    }
    function allow(euint64 ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(euint64 ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(euint64 ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(euint64 ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(euint64 ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(euint64 ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(euint64 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}

using BindingsEuint128 for euint128 global;
library BindingsEuint128 {

    /// @notice Performs the add operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the add
    function add(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.add(lhs, rhs);
    }

    /// @notice Performs the sub operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the sub
    function sub(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.sub(lhs, rhs);
    }

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the eq
    function eq(euint128 lhs, euint128 rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the ne
    function ne(euint128 lhs, euint128 rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }

    /// @notice Performs the not operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @return the result of the not
    function not(euint128 lhs) internal returns (euint128) {
        return FHE.not(lhs);
    }

    /// @notice Performs the and operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the and
    function and(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.and(lhs, rhs);
    }

    /// @notice Performs the or operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the or
    function or(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.or(lhs, rhs);
    }

    /// @notice Performs the xor operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the xor
    function xor(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.xor(lhs, rhs);
    }

    /// @notice Performs the gt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the gt
    function gt(euint128 lhs, euint128 rhs) internal returns (ebool) {
        return FHE.gt(lhs, rhs);
    }

    /// @notice Performs the gte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the gte
    function gte(euint128 lhs, euint128 rhs) internal returns (ebool) {
        return FHE.gte(lhs, rhs);
    }

    /// @notice Performs the lt operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the lt
    function lt(euint128 lhs, euint128 rhs) internal returns (ebool) {
        return FHE.lt(lhs, rhs);
    }

    /// @notice Performs the lte operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the lte
    function lte(euint128 lhs, euint128 rhs) internal returns (ebool) {
        return FHE.lte(lhs, rhs);
    }

    /// @notice Performs the max operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the max
    function max(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.max(lhs, rhs);
    }

    /// @notice Performs the min operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the min
    function min(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.min(lhs, rhs);
    }

    /// @notice Performs the shl operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the shl
    function shl(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.shl(lhs, rhs);
    }

    /// @notice Performs the shr operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the shr
    function shr(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.shr(lhs, rhs);
    }

    /// @notice Performs the rol operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the rol
    function rol(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.rol(lhs, rhs);
    }

    /// @notice Performs the ror operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type euint128
    /// @param rhs second input of type euint128
    /// @return the result of the ror
    function ror(euint128 lhs, euint128 rhs) internal returns (euint128) {
        return FHE.ror(lhs, rhs);
    }
    function toBool(euint128 value) internal  returns (ebool) {
        return FHE.asEbool(value);
    }
    function toU8(euint128 value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }
    function toU16(euint128 value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }
    function toU32(euint128 value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }
    function toU64(euint128 value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }
    function decrypt(euint128 value) internal {
        FHE.decrypt(value);
    }
    function allow(euint128 ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(euint128 ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(euint128 ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(euint128 ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(euint128 ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(euint128 ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(euint128 value, bytes32 sealingKey) internal view returns (SealedUint memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}

using BindingsEaddress for eaddress global;
library BindingsEaddress {

    /// @notice Performs the eq operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type eaddress
    /// @param rhs second input of type eaddress
    /// @return the result of the eq
    function eq(eaddress lhs, eaddress rhs) internal returns (ebool) {
        return FHE.eq(lhs, rhs);
    }

    /// @notice Performs the ne operation
    /// @dev Pure in this function is marked as a hack/workaround - note that this function is NOT pure as fetches of ciphertexts require state access
    /// @param lhs input of type eaddress
    /// @param rhs second input of type eaddress
    /// @return the result of the ne
    function ne(eaddress lhs, eaddress rhs) internal returns (ebool) {
        return FHE.ne(lhs, rhs);
    }
    function toBool(eaddress value) internal  returns (ebool) {
        return FHE.asEbool(value);
    }
    function toU8(eaddress value) internal returns (euint8) {
        return FHE.asEuint8(value);
    }
    function toU16(eaddress value) internal returns (euint16) {
        return FHE.asEuint16(value);
    }
    function toU32(eaddress value) internal returns (euint32) {
        return FHE.asEuint32(value);
    }
    function toU64(eaddress value) internal returns (euint64) {
        return FHE.asEuint64(value);
    }
    function toU128(eaddress value) internal returns (euint128) {
        return FHE.asEuint128(value);
    }
    function decrypt(eaddress value) internal {
        FHE.decrypt(value);
    }
    function allow(eaddress ctHash, address account) internal {
        FHE.allow(ctHash, account);
    }
    function isAllowed(eaddress ctHash, address account) internal returns (bool) {
        return FHE.isAllowed(ctHash, account);
    }
    function allowThis(eaddress ctHash) internal {
        FHE.allowThis(ctHash);
    }
    function allowGlobal(eaddress ctHash) internal {
        FHE.allowGlobal(ctHash);
    }
    function allowSender(eaddress ctHash) internal {
        FHE.allowSender(ctHash);
    }
    function allowTransient(eaddress ctHash, address account) internal {
        FHE.allowTransient(ctHash, account);
    }
    function sealTyped(eaddress value, bytes32 sealingKey) internal view returns (SealedAddress memory) {
        return FHE.sealoutputTyped(value, sealingKey);
    }
}
