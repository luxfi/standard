// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IDeploymentBlock
 * @notice Interface for tracking contract deployment block numbers
 * @dev This interface provides a standard way to record and query when a contract
 * was deployed. This information is useful for:
 * - Off-chain indexing services to know when to start scanning
 * - Analytics to track contract age and deployment patterns
 * - Frontend applications to optimize historical queries
 *
 * The deployment block is set once during initialization and cannot be changed,
 * providing an immutable record of when the contract became active.
 */
interface IDeploymentBlock {
    // --- Errors ---

    /** @notice Thrown when attempting to set deployment block after it's already set */
    error DeploymentBlockAlreadySet();

    // --- View Functions ---

    /**
     * @notice Returns the block number when this contract was deployed
     * @dev Set during contract initialization and immutable thereafter.
     * Useful for off-chain services to know where to start indexing events.
     * @return blockNumber The block number of contract deployment
     */
    function deploymentBlock() external view returns (uint256 blockNumber);
}
