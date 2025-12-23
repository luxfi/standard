// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title InitializerEventEmitter
 * @author Lux Industriesn Inc
 * @notice Abstract contract for emitting initialization data during contract deployment
 * @dev This abstract contract provides a standardized way to emit initialization
 * data for initializable contracts in the DAO ecosystem.
 *
 * Implementation details:
 * - Designed to be inherited by upgradeable contracts
 * - Emits raw initialization data for transparency and auditability
 * - Minimal gas overhead with single event emission
 * - Follows OpenZeppelin's initializer pattern
 * - Uses `onlyInitializing` modifier for security
 *
 * Usage:
 * - Inherit this contract in your upgradeable contract
 * - Call `__InitializerEventEmitter_init()` in your initializer function
 * - Pass the encoded initialization parameters as bytes
 *
 * Example:
 * ```solidity
 * contract MyContract is InitializerEventEmitter, OtherContracts {
 *     function initialize(address owner_, uint256 value_) public initializer {
 *         bytes memory initData = abi.encode(owner_, value_);
 *         __InitializerEventEmitter_init(initData);
 *         // ... rest of initialization
 *     }
 * }
 * ```
 *
 * @custom:security-contact security@lux.network
 */
abstract contract InitializerEventEmitter is Initializable {
    // ======================================================================
    // ERRORS
    // ======================================================================

    /**
     * @notice Thrown when attempting to initialize after already initialized
     * @dev Prevents reinitialization attacks on upgradeable contracts
     */
    error InitializeDataAlreadyEmitted();

    // ======================================================================
    // EVENTS
    // ======================================================================

    /**
     * @notice Emitted when a contract is initialized with data
     * @dev This event provides transparency for all initialization parameters
     * @param initData The raw initialization data passed to the contract
     */
    event InitializeData(bytes initData);

    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Storage struct for InitializerEventEmitter following EIP-7201
     * @dev Tracks whether initialization data has been emitted
     * @custom:storage-location erc7201:DAO.InitializerEventEmitter.main
     */
    struct InitializerEventEmitterStorage {
        /** @notice Whether the initialization data has been emitted */
        bool initialized;
    }

    /**
     * @dev Storage slot for InitializerEventEmitterStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.InitializerEventEmitter.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant INITIALIZER_EVENT_EMITTER_STORAGE_LOCATION =
        0xf7464a9b8e299d18ec8976df251e878e5204887b642c36b9e3e606b459323300;

    /**
     * @dev Returns the storage struct for InitializerEventEmitter
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for InitializerEventEmitter
     */
    function _getInitializerEventEmitterStorage()
        internal
        pure
        returns (InitializerEventEmitterStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := INITIALIZER_EVENT_EMITTER_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // INITIALIZERS
    // ======================================================================

    /**
     * @notice Initializes the event emitter and emits the initialization data
     * @dev Must be called by inheriting contracts in their initializer function.
     * Can only be called once - subsequent calls will revert.
     * @param initData The initialization data to emit
     * @custom:throws InitializeDataAlreadyEmitted if already initialized
     */
    function __InitializerEventEmitter_init(
        // solhint-disable-previous-line func-name-mixedcase
        bytes memory initData
    ) internal onlyInitializing {
        InitializerEventEmitterStorage
            storage $ = _getInitializerEventEmitterStorage();

        if ($.initialized) {
            revert InitializeDataAlreadyEmitted();
        }

        $.initialized = true;
        emit InitializeData(initData);
    }
}
