// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {Enum} from "../base/Enum.sol";

/**
 * @title IVault
 * @author Lux Industries Inc
 * @notice Interface for Safe-compatible vault that can execute transactions from modules
 * @dev Renamed from IAvatar (Zodiac) to align with Lux terminology.
 * A Vault is the Safe that holds assets and executes transactions.
 */
interface IVault {
    /**
     * @notice Enables a module on the vault
     * @param module The module to enable
     */
    function enableModule(address module) external;

    /**
     * @notice Disables a module on the vault
     * @param module The module to disable
     */
    function disableModule(address prevModule, address module) external;

    /**
     * @notice Executes a transaction from an enabled module
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Call or DelegateCall
     * @return success True if the transaction succeeded
     */
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);

    /**
     * @notice Executes a transaction from an enabled module and returns result data
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Call or DelegateCall
     * @return success True if the transaction succeeded
     * @return returnData The data returned by the call
     */
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData);

    /**
     * @notice Checks if a module is enabled
     * @param module The module address to check
     * @return True if the module is enabled
     */
    function isModuleEnabled(address module) external view returns (bool);

    /**
     * @notice Returns array of modules
     * @param start Start address (use address(1) for beginning)
     * @param pageSize Number of modules to return
     * @return array Array of module addresses
     * @return next Next start address for pagination
     */
    function getModulesPaginated(
        address start,
        uint256 pageSize
    ) external view returns (address[] memory array, address next);
}
