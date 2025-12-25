// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

/// @title ERC-165 Interface
interface IERC165 {
    /// @notice Check if a contract implements an interface.
    /// @param interfaceId The ERC-165 interface identifier.
    /// @return supported Whether or not the interface is supported.
    function supportsInterface(bytes4 interfaceId) external view returns (bool supported);
}
