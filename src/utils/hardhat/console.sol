// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

/// @notice Hardhat console.sol compatibility shim for Foundry
/// @dev All functions are no-ops in production, use forge console2 for actual logging
library console {
    function log() internal pure {}
    function log(string memory) internal pure {}
    function log(string memory, string memory) internal pure {}
    function log(string memory, uint256) internal pure {}
    function log(string memory, int256) internal pure {}
    function log(string memory, address) internal pure {}
    function log(string memory, bool) internal pure {}
    function log(uint256) internal pure {}
    function log(int256) internal pure {}
    function log(address) internal pure {}
    function log(bool) internal pure {}
    function log(uint256, uint256) internal pure {}
    function log(uint256, string memory) internal pure {}
    function log(uint256, address) internal pure {}
    function log(address, address) internal pure {}
    function log(address, string memory) internal pure {}
    function log(address, uint256) internal pure {}
    function log(string memory, string memory, string memory) internal pure {}
    function log(string memory, string memory, uint256) internal pure {}
    function log(string memory, uint256, uint256) internal pure {}
    function log(string memory, uint256, string memory) internal pure {}
    function log(string memory, address, address) internal pure {}
    function log(string memory, address, uint256) internal pure {}
    function log(string memory, uint256, address, uint256) internal pure {}
    function log(string memory, uint256, bool, uint256) internal pure {}
    function log(string memory, uint256, address) internal pure {}
    function log(string memory, bool, string memory) internal pure {}
    function logInt(int256) internal pure {}
    function logUint(uint256) internal pure {}
    function logString(string memory) internal pure {}
    function logBool(bool) internal pure {}
    function logAddress(address) internal pure {}
    function logBytes(bytes memory) internal pure {}
    function logBytes1(bytes1) internal pure {}
    function logBytes32(bytes32) internal pure {}
}
