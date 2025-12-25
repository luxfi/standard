// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.31;

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";
import {ISafe} from "@safe-global/safe-smart-account/interfaces/ISafe.sol";

/**
 * @title SafeModule
 * @notice Base module for Safe extensions
 * @dev Provides common functionality for Safe modules
 *
 * Built on audited Safe Global contracts v1.5.0
 */
abstract contract SafeModule {
    /// @notice The Safe this module is attached to
    address payable public immutable safe;

    /// @notice Module version
    string public constant VERSION = "1.0.0";

    /// @notice Emitted when the module executes a transaction
    event ModuleExecuted(address indexed to, uint256 value, bytes data, Enum.Operation operation);

    /// @notice Error when caller is not the Safe
    error OnlySafe();

    /// @notice Error when execution fails
    error ExecutionFailed();

    /// @notice Constructor
    /// @param _safe The Safe address this module is attached to
    constructor(address payable _safe) {
        safe = _safe;
    }

    /// @notice Modifier to restrict calls to the Safe only
    modifier onlySafe() {
        if (msg.sender != safe) revert OnlySafe();
        _;
    }

    /// @notice Execute a transaction through the Safe
    /// @param to Destination address
    /// @param value Ether value
    /// @param data Call data
    /// @param operation Call or DelegateCall
    /// @return success True if execution succeeded
    function _executeFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bool success) {
        success = ISafe(safe).execTransactionFromModule(to, value, data, operation);
        if (!success) revert ExecutionFailed();
        emit ModuleExecuted(to, value, data, operation);
    }

    /// @notice Returns the module version
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
