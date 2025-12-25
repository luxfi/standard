// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {FROST} from "./FROST.sol";
import {IERC1271, ILegacyERC1271} from "./interfaces/IERC1271.sol";

/// @title Safe FROST Signer
/// @notice Safe smart account owner that can verify FROST(secp256k1, SHA-256)
/// signatures.
contract SafeFROSTSigner is IERC1271, ILegacyERC1271 {
    /// @notice The x-coordinate of the signer's public key.
    uint256 private immutable _PX;
    /// @notice The y-coordinate of the signer's public key.
    uint256 private immutable _PY;
    /// @notice The public address of the signer.
    address private immutable _SIGNER;

    /// @notice The public key is invalid or may result in the loss of funds.
    error InvalidPublicKey();

    constructor(uint256 px, uint256 py) {
        require(FROST.isValidPublicKey(px, py), InvalidPublicKey());
        _PX = px;
        _PY = py;
        _SIGNER = address(uint160(uint256(keccak256(abi.encode(px, py)))));
    }

    /// @notice Checks if the given signature is valid for the given message.
    /// @param message The message to be verified.
    /// @param signature The signature bytes, this is expected to be the encoded
    /// FROST signature `abi.encode(rx, ry, z)`.
    /// @return ok Whether or not the signature is valid.
    function _isValidSignature(bytes32 message, bytes calldata signature) public view returns (bool ok) {
        uint256 rx;
        uint256 ry;
        uint256 z;

        assembly ("memory-safe") {
            rx := calldataload(signature.offset)
            ry := calldataload(add(signature.offset, 0x20))
            z := calldataload(add(signature.offset, 0x40))
        }

        return FROST.verify(message, _PX, _PY, rx, ry, z) == _SIGNER;
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 message, bytes calldata signature) public view returns (bytes4 magicValue) {
        if (_isValidSignature(message, signature)) {
            magicValue = IERC1271.isValidSignature.selector;
        }
    }

    /// @inheritdoc ILegacyERC1271
    function isValidSignature(bytes memory message, bytes calldata signature) public view returns (bytes4 magicValue) {
        if (_isValidSignature(keccak256(message), signature)) {
            magicValue = ILegacyERC1271.isValidSignature.selector;
        }
    }
}
