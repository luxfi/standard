// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

/**
 * @title GatewayCaller
 * @dev Base contract for contracts that need to call the FHE gateway for decryption
 * @notice Provides utilities for requesting decryption from the gateway
 */
abstract contract GatewayCaller {
    /// @dev Gateway address for decryption requests
    address public gateway;
    
    /// @dev Counter for generating unique request IDs
    uint256 private _requestCounter;

    /// @dev Emitted when a decryption is requested
    event DecryptionRequested(uint256 indexed requestId, bytes32[] handles);
    
    /// @dev Emitted when a decryption result is received
    event DecryptionResult(uint256 indexed requestId, uint256 result);

    /// @dev Only the gateway can call functions with this modifier
    modifier onlyGateway() {
        require(msg.sender == gateway, "GatewayCaller: only gateway");
        _;
    }

    /**
     * @dev Sets the gateway address
     * @param _gateway The address of the gateway contract
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
     * @dev Requests decryption of encrypted handles
     * @param handles Array of encrypted value handles to decrypt
     * @return requestId The ID of the decryption request
     */
    function _requestDecryption(bytes32[] memory handles) internal returns (uint256 requestId) {
        requestId = _generateRequestId();
        emit DecryptionRequested(requestId, handles);
    }
}
