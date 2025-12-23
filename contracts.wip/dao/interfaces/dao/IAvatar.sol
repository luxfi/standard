// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {Enum} from "@safe-global/safe-smart-account/interfaces/Enum.sol";

/**
 * @title IAvatar
 * @author Lux Industriesn Inc (adapted from Gnosis Guild)
 * @notice Interface for avatar contracts that can execute module transactions
 * @dev This is a local implementation that removes dependency on @gnosis-guild/zodiac
 * while maintaining the same functionality. An Avatar is typically a Safe or similar
 * smart account that can execute transactions on behalf of modules.
 */
interface IAvatar {
    /**
     * @notice Enables a module for the avatar
     * @param module Address of the module to enable
     * @dev Only authorized callers should be able to enable modules
     */
    function enableModule(address module) external;

    /**
     * @notice Disables a module for the avatar
     * @param prevModule Previous module in the modules linked list
     * @param module Module to be removed
     * @dev Only authorized callers should be able to disable modules
     */
    function disableModule(address prevModule, address module) external;

    /**
     * @notice Executes a transaction from a module
     * @param to Destination address of module transaction
     * @param value Ether value of module transaction
     * @param data Data payload of module transaction
     * @param operation Operation type of module transaction (Call or DelegateCall)
     * @return success True if transaction was successful
     * @dev Only enabled modules should be able to execute transactions
     */
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);

    /**
     * @notice Executes a transaction from a module and returns data
     * @param to Destination address of module transaction
     * @param value Ether value of module transaction
     * @param data Data payload of module transaction
     * @param operation Operation type of module transaction (Call or DelegateCall)
     * @return success True if transaction was successful
     * @return returnData Data returned by the call
     * @dev Only enabled modules should be able to execute transactions
     */
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData);

    /**
     * @notice Returns if a module is enabled
     * @param module Address to check
     * @return True if the module is enabled
     */
    function isModuleEnabled(address module) external view returns (bool);

    /**
     * @notice Returns array of modules
     * @param start Start of the page (address(0x1) for first page)
     * @param pageSize Maximum number of modules that should be returned
     * @return array Array of modules
     * @return next Start of the next page
     * @dev Pagination is implemented using linked list traversal
     */
    function getModulesPaginated(
        address start,
        uint256 pageSize
    ) external view returns (address[] memory array, address next);
}