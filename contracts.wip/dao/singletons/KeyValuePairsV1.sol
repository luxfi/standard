// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    IKeyValuePairsV1
} from "../interfaces/dao/singletons/IKeyValuePairsV1.sol";
import {IVersion} from "../interfaces/dao/deployables/IVersion.sol";
import {IDeploymentBlock} from "../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockNonInitializable
} from "../DeploymentBlockNonInitializable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title KeyValuePairsV1
 * @author Lux Industriesn Inc
 * @notice Implementation of on-chain metadata storage via events
 * @dev This contract implements IKeyValuePairsV1, providing a stateless
 * metadata storage service through event emission.
 *
 * Implementation details:
 * - Deployed once per chain as a singleton
 * - Non-upgradeable deployment pattern
 * - Zero storage usage - all data in events
 * - Permissionless - any address can emit metadata
 * - Gas efficient for metadata publication
 *
 * Event-based storage pattern:
 * - Metadata is stored in events, not contract storage
 * - Off-chain services index events to build current state
 * - Updates overwrite previous values for same key/sender
 * - Historical data preserved in event logs
 *
 * Common usage:
 * - DAO names, descriptions, and links
 * - Configuration parameters for frontends
 * - Any metadata that should be publicly queryable
 *
 * @custom:security-contact security@lux.network
 */
contract KeyValuePairsV1 is
    IKeyValuePairsV1,
    IVersion,
    DeploymentBlockNonInitializable,
    ERC165
{
    // ======================================================================
    // IKeyValuePairs
    // ======================================================================

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IKeyValuePairsV1
     * @dev Iterates through the array and emits an event for each pair.
     */
    function updateValues(
        KeyValuePair[] calldata keyValuePairs_
    ) public virtual override {
        for (uint256 i; i < keyValuePairs_.length; ) {
            KeyValuePair memory keyValuePair = keyValuePairs_[i];

            emit ValueUpdated(msg.sender, keyValuePair.key, keyValuePair.value);

            unchecked {
                ++i;
            }
        }
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
     * @dev Supports IKeyValuePairsV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IKeyValuePairsV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
