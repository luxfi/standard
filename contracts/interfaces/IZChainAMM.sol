// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IZChainAMM
 * @notice Interface for Z-Chain AMM
 */
interface IZChainAMM {
    /// @notice Execute encrypted swap
    function swapEncrypted(
        bytes32 poolId,
        bytes32 encryptedAmount,
        bytes32 encryptedMinOutput,
        address recipient
    ) external returns (bytes32 outputCommitment);
    
    /// @notice Verify swap proof
    function verifySwapProof(
        bytes calldata proof,
        bytes32 commitment,
        bytes32 poolId
    ) external view returns (bool);
}
