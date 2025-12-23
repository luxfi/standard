// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IDeploymentBlock} from "./interfaces/dao/IDeploymentBlock.sol";

/**
 * @title DeploymentBlockNonInitializable
 * @author Lux Industriesn Inc
 * @notice Abstract implementation of deployment block tracking for non-initializable contracts
 * @dev This abstract contract implements IDeploymentBlock, providing a standard
 * way to record when non-initializable contracts are deployed.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for consistency
 * - Records block number in constructor
 * - Deployment block is immutable once set
 * - Designed for singleton and utility contracts
 * - Must be inherited by non-initializable contracts
 *
 * Usage:
 * - Simply inherit this contract - no initialization needed
 * - The deployment block number is automatically set in the constructor
 * - Query deploymentBlock() to get the recorded value
 *
 * Differences from DeploymentBlockInitializable:
 * - No initializer pattern - uses constructor
 * - No reinitialization concerns
 * - Simpler implementation for non-initializable contracts
 *
 * @custom:security-contact security@lux.network
 */
abstract contract DeploymentBlockNonInitializable is IDeploymentBlock {
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    uint256 private immutable _deploymentBlock;

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    /**
     * @notice Records the deployment block during contract construction
     * @dev Automatically captures the current block number when the contract
     * is deployed. This happens once and the value is immutable.
     */
    constructor() {
        _deploymentBlock = block.number;
    }

    // ======================================================================
    // IDeploymentBlock
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IDeploymentBlock
     */
    function deploymentBlock() public view virtual override returns (uint256) {
        return _deploymentBlock;
    }
}
