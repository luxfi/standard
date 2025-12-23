// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title ISystemDeployerEventEmitterV1
 * @notice Singleton contract for emitting DAO deployment events
 * @dev This contract works in conjunction with SystemDeployerV1 to emit deployment
 * events that can be indexed off-chain. Since SystemDeployerV1 is called via
 * delegatecall from the Safe during setup, events would normally be emitted from
 * the Safe's address. This separate contract ensures events are emitted from a
 * consistent address across all deployments.
 *
 * Key features:
 * - Singleton deployment per chain
 * - Consistent event emission address
 * - Enables efficient indexing of all DAO deployments
 * - Captures deployment parameters for reconstruction
 *
 * Workflow:
 * 1. SystemDeployerV1 is called via delegatecall from Safe
 * 2. SystemDeployerV1 calls this contract to emit the event
 * 3. Event is emitted from this contract's address
 * 4. Off-chain indexers can watch this single address
 *
 * Use cases:
 * - Indexing all DAO deployments on a chain
 * - Tracking deployment parameters and configurations
 * - Building deployment analytics and dashboards
 * - Reconstructing deployment transactions
 */
interface ISystemDeployerEventEmitterV1 {
    // --- Events ---

    /**
     * @notice Emitted when a new DAO system is deployed
     * @dev This event captures all the information needed to reconstruct
     * a DAO deployment. The safeProxy is indexed as msg.sender since
     * this function is called by the newly deployed Safe.
     * @param safeProxy The deployed Safe proxy address (msg.sender)
     * @param safeProxyFactory The factory used to deploy the Safe
     * @param salt The salt used for deterministic deployment
     * @param initData The initialization data passed to the Safe
     */
    event SystemDeployed(
        address indexed safeProxy,
        address indexed safeProxyFactory,
        bytes32 salt,
        bytes initData
    );

    // --- State-Changing Functions ---

    /**
     * @notice Emits a SystemDeployed event for a new DAO deployment
     * @dev Called by SystemDeployerV1 after successfully deploying a DAO system.
     * The msg.sender (the newly deployed Safe) is included in the event as safeProxy.
     * This design ensures all deployment events come from a single address for
     * efficient indexing.
     * @param safeProxyFactory_ The Safe proxy factory contract used
     * @param salt_ The salt used for deterministic Safe deployment
     * @param initData_ The complete initialization data for the Safe
     * @custom:emits SystemDeployed with msg.sender as safeProxy
     */
    function emitSystemDeployed(
        address safeProxyFactory_,
        bytes32 salt_,
        bytes calldata initData_
    ) external;
}
