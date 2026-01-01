// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import {ebool, euint8, euint16, euint32, euint64, euint128, euint256, eaddress} from "../FHE.sol";

/**
 * @title TFHE
 * @author Lux Network
 * @dev Library for Threshold FHE operations - requesting async decryption via T-Chain
 * @notice FHE ciphertexts cannot be decrypted on C-Chain directly. Instead, decryption
 *         requests are sent to T-Chain where threshold validators (n-of-m MPC) collaborate
 *         to decrypt. Results are delivered via callback after threshold consensus.
 *
 * Architecture:
 *   C-Chain Contract → TFHE.decrypt() → T-Chain Validators → callback with plaintext
 *
 * The T-Chain uses threshold cryptography protocols (like FROST, CGGMP21, or Ringtail)
 * to ensure no single validator can decrypt alone - threshold consensus is required.
 *
 * Usage:
 *   import {TFHE} from "./threshold/TFHE.sol";
 *
 *   uint256[] memory cts = new uint256[](1);
 *   cts[0] = TFHE.toUint256(encryptedValue);
 *   uint256 requestId = TFHE.decrypt(cts, this.callback.selector, 0, block.timestamp + 100, false);
 */
library TFHE {
    /// @dev Storage slot for T-Chain gateway address (follows EIP-1967)
    bytes32 private constant GATEWAY_SLOT = keccak256("luxfhe.threshold.gateway");

    /// @dev Storage slot for request counter
    bytes32 private constant COUNTER_SLOT = keccak256("luxfhe.threshold.counter");

    /// @dev Event emitted when decryption is requested to T-Chain
    event DecryptionRequested(uint256 indexed requestId, uint256[] ciphertext, bytes4 callbackSelector);

    // ============================================================
    // Type Conversions - Convert encrypted types to uint256 handles
    // ============================================================

    /**
     * @dev Convert ebool to uint256 handle
     */
    function toUint256(ebool value) internal pure returns (uint256) {
        return ebool.unwrap(value);
    }

    /**
     * @dev Convert euint8 to uint256 handle
     */
    function toUint256(euint8 value) internal pure returns (uint256) {
        return euint8.unwrap(value);
    }

    /**
     * @dev Convert euint16 to uint256 handle
     */
    function toUint256(euint16 value) internal pure returns (uint256) {
        return euint16.unwrap(value);
    }

    /**
     * @dev Convert euint32 to uint256 handle
     */
    function toUint256(euint32 value) internal pure returns (uint256) {
        return euint32.unwrap(value);
    }

    /**
     * @dev Convert euint64 to uint256 handle
     */
    function toUint256(euint64 value) internal pure returns (uint256) {
        return euint64.unwrap(value);
    }

    /**
     * @dev Convert euint128 to uint256 handle
     */
    function toUint256(euint128 value) internal pure returns (uint256) {
        return euint128.unwrap(value);
    }

    /**
     * @dev Convert euint256 to uint256 handle
     */
    function toUint256(euint256 value) internal pure returns (uint256) {
        return euint256.unwrap(value);
    }

    /**
     * @dev Convert eaddress to uint256 handle
     */
    function toUint256(eaddress value) internal pure returns (uint256) {
        return eaddress.unwrap(value);
    }

    // ============================================================
    // Gateway Management - T-Chain endpoint configuration
    // ============================================================

    /**
     * @dev Get the current T-Chain gateway address
     */
    function getGateway() internal view returns (address gateway) {
        bytes32 slot = GATEWAY_SLOT;
        assembly {
            gateway := sload(slot)
        }
    }

    /**
     * @dev Set the T-Chain gateway address
     */
    function setGateway(address gateway) internal {
        bytes32 slot = GATEWAY_SLOT;
        assembly {
            sstore(slot, gateway)
        }
    }

    // ============================================================
    // Decryption Requests - Send to T-Chain for threshold decryption
    // ============================================================

    /**
     * @dev Generate a unique request ID
     */
    function _generateRequestId() private returns (uint256 requestId) {
        bytes32 slot = COUNTER_SLOT;
        assembly {
            requestId := add(sload(slot), 1)
            sstore(slot, requestId)
        }
    }

    /**
     * @dev Request async decryption via T-Chain threshold validators
     * @param cts Array of ciphertext handles to decrypt
     * @param callback The function selector for the callback
     * @param value Any ETH value to send with the request
     * @param deadline Maximum timestamp for the request to be valid
     * @param passSignatures Whether to pass threshold signatures to caller
     * @return requestId The unique request identifier
     *
     * @notice Decryption is async - your contract must implement a callback function
     *         with the selector provided. T-Chain validators will call it with results.
     */
    function decrypt(
        uint256[] memory cts,
        bytes4 callback,
        uint256 value,
        uint256 deadline,
        bool passSignatures
    ) internal returns (uint256 requestId) {
        requestId = _generateRequestId();
        emit DecryptionRequested(requestId, cts, callback);

        // In production, this calls the T-Chain gateway bridge contract
        // Event is picked up by T-Chain validators for threshold decryption
        (value, deadline, passSignatures); // silence unused warnings
    }
}
