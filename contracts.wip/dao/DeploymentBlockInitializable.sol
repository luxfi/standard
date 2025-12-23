// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IDeploymentBlock} from "./interfaces/dao/IDeploymentBlock.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title DeploymentBlockInitializable
 * @author Lux Industriesn Inc
 * @notice Abstract implementation of deployment block tracking for initializable contracts
 * @dev This abstract contract implements IDeploymentBlock, providing a standard
 * way to record when initializable contracts are deployed.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability
 * - Records block number during initialization
 * - Deployment block is immutable once set
 * - Designed for UUPS and transparent proxy patterns
 * - Must be inherited by initializable contracts
 *
 * Usage:
 * - Call __DeploymentBlockInitializable_init() in the inheriting contract's initializer
 * - The deployment block is automatically set to the current block
 * - Query deploymentBlock() to get the recorded value
 *
 * Security considerations:
 * - Can only be set once during initialization
 * - Prevents reinitialization attacks
 * - Provides reliable deployment block number
 *
 * @custom:security-contact security@lux.network
 */
abstract contract DeploymentBlockInitializable is
    Initializable,
    IDeploymentBlock
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for DeploymentBlockInitializable following EIP-7201
     * @dev Stores the block number when the contract was deployed
     * @custom:storage-location erc7201:DAO.DeploymentBlockInitializable.main
     */
    struct DeploymentBlockInitializableStorage {
        /** @notice The block number when this contract was deployed */
        uint256 deploymentBlock;
    }

    /**
     * @dev Storage slot for DeploymentBlockInitializableStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.DeploymentBlockInitializable.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant DEPLOYMENT_BLOCK_INITIALIZABLE_STORAGE_LOCATION =
        0x8a73f35b9df1b6f9967ddd5a4ec6ec57f8bdee83334d4552823c6e36f981ab00;

    /**
     * @dev Returns the storage struct for DeploymentBlockInitializable
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for DeploymentBlockInitializable
     */
    function _getDeploymentBlockInitializableStorage()
        internal
        pure
        returns (DeploymentBlockInitializableStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := DEPLOYMENT_BLOCK_INITIALIZABLE_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    /**
     * @notice Initializes the deployment block tracking
     * @dev Must be called by inheriting contracts in their initializer.
     * Records the current block number as the deployment block.
     * Can only be called once due to the check for existing value.
     * @custom:throws DeploymentBlockAlreadySet if already initialized
     */
    function __DeploymentBlockInitializable_init() internal onlyInitializing {
        // solhint-disable-previous-line func-name-mixedcase
        DeploymentBlockInitializableStorage
            storage $ = _getDeploymentBlockInitializableStorage();
        if ($.deploymentBlock != 0) {
            revert DeploymentBlockAlreadySet();
        }

        $.deploymentBlock = block.number;
    }

    // ======================================================================
    // IDeploymentBlock
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IDeploymentBlock
     */
    function deploymentBlock() public view virtual override returns (uint256) {
        DeploymentBlockInitializableStorage
            storage $ = _getDeploymentBlockInitializableStorage();
        return $.deploymentBlock;
    }
}
