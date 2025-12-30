// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import {ebool, euint8, euint16, euint32, euint64, euint128, euint256, eaddress} from "../FHE.sol";

/**
 * @title Gateway
 * @dev Library for interacting with the FHE gateway for decryption requests
 * @notice Provides utilities for converting encrypted types to uint256 handles and requesting decryption
 */
library Gateway {
    /// @dev Storage slot for gateway address (follows EIP-1967)
    bytes32 private constant GATEWAY_SLOT = keccak256("luxfhe.gateway.address");
    
    /// @dev Storage slot for request counter
    bytes32 private constant COUNTER_SLOT = keccak256("luxfhe.gateway.counter");

    /// @dev Event emitted when decryption is requested
    event DecryptionRequested(uint256 indexed requestId, uint256[] ciphertext, bytes4 callbackSelector);

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

    /**
     * @dev Get the current gateway address
     */
    function getGateway() internal view returns (address gateway) {
        bytes32 slot = GATEWAY_SLOT;
        assembly {
            gateway := sload(slot)
        }
    }

    /**
     * @dev Set the gateway address
     */
    function setGateway(address gateway) internal {
        bytes32 slot = GATEWAY_SLOT;
        assembly {
            sstore(slot, gateway)
        }
    }

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
     * @dev Request decryption of multiple ciphertext handles
     * @param cts Array of ciphertext handles to decrypt
     * @param callbackSelector The function selector for the callback
     * @param msgValue Any ETH value to send with the request
     * @param maxTimestamp Maximum timestamp for the request to be valid
     * @param passSignaturesToCaller Whether to pass signatures to caller
     * @return requestId The unique request identifier
     */
    function requestDecryption(
        uint256[] memory cts,
        bytes4 callbackSelector,
        uint256 msgValue,
        uint256 maxTimestamp,
        bool passSignaturesToCaller
    ) internal returns (uint256 requestId) {
        requestId = _generateRequestId();
        emit DecryptionRequested(requestId, cts, callbackSelector);
        
        // In production, this would call the actual gateway contract
        // For now, we emit an event that can be picked up by off-chain services
        (msgValue, maxTimestamp, passSignaturesToCaller); // silence unused warnings
    }
}
