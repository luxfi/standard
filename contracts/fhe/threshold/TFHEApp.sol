// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

/**
 * @title TFHEApp
 * @author Lux Network
 * @dev Base contract for TFHE-enabled applications
 * @notice Inherit from this to build apps that use FHE with T-Chain decryption.
 *
 * Usage:
 *   1. Inherit from TFHEApp
 *   2. Use TFHE.requestDecrypt() for decryption requests
 *   3. Implement a callback function with onlyGateway modifier
 *   4. T-Chain validators call your callback after threshold consensus
 *
 * Architecture:
 *   Your Contract → TFHE.requestDecrypt() → T-Chain → callback()
 */
abstract contract TFHEApp {
    /// @dev T-Chain gateway address for decryption requests
    address public gateway;

    /// @dev Counter for generating unique request IDs
    uint256 private _requestCounter;

    /// @dev Emitted when decryption is requested to T-Chain
    event DecryptionRequested(uint256 indexed requestId, bytes32[] handles);

    /// @dev Emitted when T-Chain delivers decryption result
    event DecryptionResult(uint256 indexed requestId, uint256 result);

    /// @dev Only T-Chain gateway can deliver decryption results
    modifier onlyGateway() {
        require(msg.sender == gateway, "TFHEApp: only gateway");
        _;
    }

    /**
     * @dev Sets the T-Chain gateway address
     * @param _gateway The address of the T-Chain gateway contract
     */
    function _setGateway(address _gateway) internal {
        gateway = _gateway;
    }

    /**
     * @dev Generates a unique request ID
     * @return The new request ID
     */
    function _generateRequestId() internal returns (uint256) {
        return ++_requestCounter;
    }

    /**
     * @dev Requests async decryption via T-Chain threshold validators
     * @param handles Array of encrypted value handles to decrypt
     * @return requestId The ID of the decryption request
     *
     * @notice Your contract must implement a callback to receive results.
     *         Use the onlyGateway modifier on your callback function.
     */
    function _requestDecryption(bytes32[] memory handles) internal returns (uint256 requestId) {
        requestId = _generateRequestId();
        emit DecryptionRequested(requestId, handles);
    }
}
