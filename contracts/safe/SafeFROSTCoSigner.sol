// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {FROST} from "./FROST.sol";
import {ISafe} from "./interfaces/ISafe.sol";
import {IERC165, ISafeTransactionGuard} from "./interfaces/ISafeTransactionGuard.sol";

contract SafeFROSTCoSigner is ISafeTransactionGuard {
    /// @notice The x-coordinate of the signer's public key.
    uint256 private immutable _PX;
    /// @notice The y-coordinate of the signer's public key.
    uint256 private immutable _PY;
    /// @notice The public address of the signer.
    address private immutable _SIGNER;

    /// @notice The transaction was not co-signed.
    error Unauthorized();

    /// @notice The public key is invalid or may result in the loss of funds.
    error InvalidPublicKey();

    constructor(uint256 px, uint256 py) {
        require(FROST.isValidPublicKey(px, py), InvalidPublicKey());
        _PX = px;
        _PY = py;
        _SIGNER = address(uint160(uint256(keccak256(abi.encode(px, py)))));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(ISafeTransactionGuard).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc ISafeTransactionGuard
    function checkTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures,
        address
    ) external view {
        bytes32 safeTxHash;
        unchecked {
            uint256 nonce = ISafe(msg.sender).nonce() - 1;
            safeTxHash = ISafe(msg.sender).getTransactionHash(
                to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce
            );
        }

        bytes calldata signature = signatures[signatures.length - 96:];
        uint256 rx;
        uint256 ry;
        uint256 z;

        assembly ("memory-safe") {
            rx := calldataload(signature.offset)
            ry := calldataload(add(signature.offset, 0x20))
            z := calldataload(add(signature.offset, 0x40))
        }

        require(FROST.verify(safeTxHash, _PX, _PY, rx, ry, z) == _SIGNER, Unauthorized());
    }

    /// @inheritdoc ISafeTransactionGuard
    function checkAfterExecution(bytes32, bool) external pure {}
}
