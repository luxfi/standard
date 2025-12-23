// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Minimal stub for IDAO interface to allow compilation
interface IDAO {
    function isAdmin(address) external view returns (bool);
    function pause() external;
    function unpause() external;
}
