// SPDX-License-Identifier: MIT
// FHECommon.sol - Common utility functions for FHE operations
// This library works with raw uint256 ciphertext hashes to avoid circular type dependencies
pragma solidity >=0.8.19 <0.9.0;

/// @title FHECommon
/// @notice Common utility functions for FHE operations on the Lux T-Chain
/// @dev Works with raw uint256 hashes to avoid circular dependencies with typed values
library FHECommon {
    error InvalidHexCharacter(bytes1 char);
    error SecurityZoneOutOfBounds(int32 value);

    /// @notice Convert a signed int32 security zone to uint256
    /// @dev Reverts if value is negative
    function convertInt32ToUint256(int32 value) internal pure returns (uint256) {
        if (value < 0) {
            revert SecurityZoneOutOfBounds(value);
        }
        return uint256(uint32(value));
    }

    /// @notice Check if a ciphertext hash is initialized (non-zero)
    /// @param hash The ciphertext hash to check
    /// @return True if the hash is non-zero (initialized)
    function isInitialized(uint256 hash) internal pure returns (bool) {
        return hash != 0;
    }

    /// @notice Create a uint256 array with one element
    function createUint256Inputs(uint256 input1) internal pure returns (uint256[] memory) {
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = input1;
        return inputs;
    }

    /// @notice Create a uint256 array with two elements
    function createUint256Inputs(uint256 input1, uint256 input2) internal pure returns (uint256[] memory) {
        uint256[] memory inputs = new uint256[](2);
        inputs[0] = input1;
        inputs[1] = input2;
        return inputs;
    }

    /// @notice Create a uint256 array with three elements
    function createUint256Inputs(uint256 input1, uint256 input2, uint256 input3) internal pure returns (uint256[] memory) {
        uint256[] memory inputs = new uint256[](3);
        inputs[0] = input1;
        inputs[1] = input2;
        inputs[2] = input3;
        return inputs;
    }
}
