// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    ISystemDeployerEventEmitterV1
} from "../interfaces/dao/singletons/ISystemDeployerEventEmitterV1.sol";
import {IVersion} from "../interfaces/dao/deployables/IVersion.sol";
import {IDeploymentBlock} from "../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockNonInitializable
} from "../DeploymentBlockNonInitializable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title SystemDeployerEventEmitterV1
 * @author Lux Industriesn Inc
 * @notice Implementation of event emission service for DAO deployments
 * @dev This contract implements ISystemDeployerEventEmitterV1, providing a
 * singleton event emission service for consistent deployment tracking.
 *
 * Implementation details:
 * - Deployed once per chain as a singleton
 * - Non-upgradeable deployment pattern
 * - Inherits from DeploymentBlockNonInitializable to track deployment
 * - Emits events from a consistent address for indexing
 * - Called by SystemDeployerV1 during DAO deployment
 * - Minimal gas overhead for event emission
 *
 * Event emission pattern:
 * - SystemDeployerV1 is called via delegatecall from Safe
 * - SystemDeployerV1 calls this contract directly
 * - Events are emitted from this contract's address
 * - msg.sender (the Safe) is included in the event
 *
 * @custom:security-contact security@lux.network
 */
contract SystemDeployerEventEmitterV1 is
    ISystemDeployerEventEmitterV1,
    IVersion,
    DeploymentBlockNonInitializable,
    ERC165
{
    // ======================================================================
    // ISystemDeployerEventEmitter
    // ======================================================================

    // --- State-Changing Functions ---

    /**
     * @inheritdoc ISystemDeployerEventEmitterV1
     * @dev The msg.sender is the newly deployed Safe proxy, which becomes
     * the indexed safeProxy parameter in the event.
     */
    function emitSystemDeployed(
        address safeProxyFactory_,
        bytes32 salt_,
        bytes calldata initData_
    ) public virtual override {
        emit SystemDeployed(msg.sender, safeProxyFactory_, salt_, initData_);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports ISystemDeployerEventEmitterV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(ISystemDeployerEventEmitterV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
