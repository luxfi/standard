// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

/// @title ERC-1271 Interface
interface IERC1271 {
    /// @notice Check if a signature is valid for the a message.
    /// @param message The signing message.
    /// @param signature The signature to verify.
    /// @return magicValue The ERC-1271 magic value when the signature is
    /// valid. Any other value, or reverting indicates an invalid signature.
    function isValidSignature(bytes32 message, bytes calldata signature) external view returns (bytes4 magicValue);
}

/// @title Legacy ERC-1271 Interface
/// @dev This interface is included for compatibility with Safe versions <= v1.4.1.
interface ILegacyERC1271 {
    /// @notice Check if a signature is valid for the a message.
    /// @param message The signing message.
    /// @param signature The signature to verify.
    /// @return magicValue The ERC-1271 magic value when the signature is
    /// valid. Any other value, or reverting indicates an invalid signature.
    function isValidSignature(bytes calldata message, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}
