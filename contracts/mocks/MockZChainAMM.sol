// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IZChainAMM.sol";

/**
 * @title MockZChainAMM
 * @notice Simplified mock for testing PrivateTeleport
 * @dev The full ZChainAMM with FHE requires specialized infrastructure
 */
contract MockZChainAMM is IZChainAMM {
    address public admin;
    bytes public fhePublicKey;
    
    mapping(bytes32 => bool) public poolExists;
    mapping(bytes32 => bool) public swapProofValid;
    
    event PrivateSwap(bytes32 indexed poolId, bytes32 inputNullifier, bytes32 outputCommitment);
    event PoolCreated(bytes32 indexed poolId, bytes32 assetA, bytes32 assetB, uint16 feeRate);
    
    constructor(bytes memory _fhePublicKey, address _admin) {
        fhePublicKey = _fhePublicKey;
        admin = _admin;
        // Create a default pool for testing
        poolExists[bytes32(0)] = true;
    }
    
    /// @notice Create a mock pool
    function createPool(
        bytes32 assetA,
        bytes32 assetB,
        bytes calldata, /* encryptedInitialA */
        bytes calldata, /* encryptedInitialB */
        uint16 feeRate
    ) external returns (bytes32 poolId) {
        poolId = keccak256(abi.encodePacked(assetA, assetB, block.timestamp));
        poolExists[poolId] = true;
        emit PoolCreated(poolId, assetA, assetB, feeRate);
        return poolId;
    }
    
    /// @notice Mock swap for testing - implements IZChainAMM
    function swapEncrypted(
        bytes32 poolId,
        bytes32 encryptedAmount,
        bytes32, /* encryptedMinOutput */
        address recipient
    ) external override returns (bytes32 outputCommitment) {
        // Generate mock output commitment
        outputCommitment = keccak256(abi.encodePacked(
            recipient,
            encryptedAmount,
            block.timestamp
        ));
        
        emit PrivateSwap(poolId, encryptedAmount, outputCommitment);
        return outputCommitment;
    }
    
    /// @notice Set swap proof validity for testing
    function setSwapProofValid(bytes32 commitment, bool valid) external {
        swapProofValid[commitment] = valid;
    }
    
    /// @notice Verify swap proof for PrivateTeleport - implements IZChainAMM
    function verifySwapProof(
        bytes calldata proof,
        bytes32 commitment,
        bytes32 poolId
    ) external view override returns (bool) {
        if (proof.length < 64) return false;
        if (commitment == bytes32(0)) return false;
        return swapProofValid[commitment] || true; // Default to valid for testing
    }
    
    /// @notice Check if pool is active
    function isPoolActive(bytes32 poolId) external view returns (bool) {
        return poolExists[poolId];
    }
}
