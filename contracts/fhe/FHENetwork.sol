// SPDX-License-Identifier: MIT
// FHENetwork.sol - Interface to the Lux T-Chain FHE Network
pragma solidity >=0.8.19 <0.9.0;

import {T_CHAIN_FHE_ADDRESS} from "./FHETypes.sol";
import {FHECommon} from "./FHECommon.sol";
import {FunctionId, IFHENetwork, EncryptedInput} from "./IFHE.sol";

/// @title FHENetwork
/// @notice Library for FHE operations on the Lux T-Chain (Threshold Chain)
/// @dev The T-Chain is powered by ThresholdVM and provides FHE compute
library FHENetwork {
    /// @notice Trivially encrypt a plaintext value
    /// @param value The plaintext value to encrypt
    /// @param toType The encrypted type to create
    /// @param securityZone The security zone for the ciphertext
    /// @return The ciphertext hash
    function trivialEncrypt(uint256 value, uint8 toType, int32 securityZone) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createTask(
            toType,
            FunctionId.trivialEncrypt,
            new uint256[](0),
            FHECommon.createUint256Inputs(value, toType, FHECommon.convertInt32ToUint256(securityZone))
        );
    }

    /// @notice Cast an encrypted value to a different type
    /// @param key The ciphertext hash
    /// @param toType The target encrypted type
    /// @return The new ciphertext hash
    function cast(uint256 key, uint8 toType) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createTask(
            toType,
            FunctionId.cast,
            FHECommon.createUint256Inputs(key),
            FHECommon.createUint256Inputs(toType)
        );
    }

    /// @notice Conditional select between two encrypted values
    /// @param returnType The return type
    /// @param control The encrypted boolean condition (raw ciphertext hash)
    /// @param ifTrue Value to return if condition is true
    /// @param ifFalse Value to return if condition is false
    /// @return The selected ciphertext hash
    function select(uint8 returnType, uint256 control, uint256 ifTrue, uint256 ifFalse) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createTask(
            returnType,
            FunctionId.select,
            FHECommon.createUint256Inputs(control, ifTrue, ifFalse),
            new uint256[](0)
        );
    }

    /// @notice Perform a binary math operation on two encrypted values
    /// @param returnType The return type
    /// @param lhs Left-hand side ciphertext hash
    /// @param rhs Right-hand side ciphertext hash
    /// @param functionId The operation to perform
    /// @return The result ciphertext hash
    function mathOp(uint8 returnType, uint256 lhs, uint256 rhs, FunctionId functionId) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createTask(
            returnType,
            functionId,
            FHECommon.createUint256Inputs(lhs, rhs),
            new uint256[](0)
        );
    }

    /// @notice Request decryption of an encrypted value
    /// @param input The ciphertext hash to decrypt
    /// @return The input hash (for tracking)
    function decrypt(uint256 input) internal returns (uint256) {
        IFHENetwork(T_CHAIN_FHE_ADDRESS).createDecryptTask(input, msg.sender);
        return input;
    }

    /// @notice Get the decryption result (reverts if not ready)
    /// @param input The ciphertext hash
    /// @return The decrypted value
    function reveal(uint256 input) internal view returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).reveal(input);
    }

    /// @notice Get the decryption result safely (returns success status)
    /// @param input The ciphertext hash
    /// @return result The decrypted value
    /// @return ready Whether decryption is complete
    function revealSafe(uint256 input) internal view returns (uint256 result, bool ready) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).revealSafe(input);
    }

    /// @notice Perform bitwise NOT on an encrypted value
    /// @param returnType The return type
    /// @param input The ciphertext hash
    /// @return The result ciphertext hash
    function not(uint8 returnType, uint256 input) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createTask(
            returnType,
            FunctionId.not,
            FHECommon.createUint256Inputs(input),
            new uint256[](0)
        );
    }

    /// @notice Square an encrypted value
    /// @param returnType The return type
    /// @param input The ciphertext hash
    /// @return The result ciphertext hash
    function square(uint8 returnType, uint256 input) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createTask(
            returnType,
            FunctionId.square,
            FHECommon.createUint256Inputs(input),
            new uint256[](0)
        );
    }

    /// @notice Verify an encrypted input from a user
    /// @param input The encrypted input struct
    /// @return The verified ciphertext hash
    function verifyInput(EncryptedInput memory input) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).verifyInput(input, msg.sender);
    }

    /// @notice Verify an encrypted input with proof
    /// @param handle The encrypted input handle
    /// @param proof The ZK proof validating the input
    /// @param utype The expected type
    /// @return The verified ciphertext hash
    function verifyInput(uint256 handle, bytes memory proof, uint8 utype) internal returns (uint256) {
        require(proof.length >= 34, "Invalid proof length");
        EncryptedInput memory input = EncryptedInput({
            ctHash: handle,
            securityZone: 0,
            utype: utype,
            signature: proof
        });
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).verifyInput(input, msg.sender);
    }

    /// @notice Generate a random encrypted value
    /// @param uintType The encrypted type
    /// @param seed The random seed
    /// @param securityZone The security zone
    /// @return The random ciphertext hash
    function random(uint8 uintType, uint256 seed, int32 securityZone) internal returns (uint256) {
        return IFHENetwork(T_CHAIN_FHE_ADDRESS).createRandomTask(uintType, seed, securityZone);
    }

    /// @notice Generate a random encrypted value with default security zone
    function random(uint8 uintType, uint256 seed) internal returns (uint256) {
        return random(uintType, seed, 0);
    }

    /// @notice Generate a random encrypted value with defaults
    function random(uint8 uintType) internal returns (uint256) {
        return random(uintType, 0, 0);
    }
}
