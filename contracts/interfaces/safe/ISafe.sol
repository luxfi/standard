// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {Enum} from "@luxfi/contracts/governance/base/Enum.sol";

/// @title Safe Smart Account Interface
/// @notice Extended interface for Safe integration with module support
interface ISafe {
    /// @notice Compute the Safe transaction hash for the given parameters.
    /// @param to The address to which the transaction is intended.
    /// @param value The native token value of the transaction in Wei.
    /// @param data The transaction data.
    /// @param operation Operation type (Call or DelegateCall).
    /// @param safeTxGas Gas used for the transaction.
    /// @param baseGas The base gas for the transaction.
    /// @param gasPrice The price of gas in Wei for the transaction.
    /// @param gasToken The token used to pay for gas.
    /// @param refundReceiver The address which should receive the refund.
    /// @param nonce The transaction nonce.
    /// @return safeTxHash The Safe transaction hash.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) external view returns (bytes32 safeTxHash);

    /// @notice Returns the Safe nonce.
    /// @return The current Safe nonce.
    function nonce() external view returns (uint256);

    /// @notice Execute a transaction from an enabled module.
    /// @param to Destination address of the module transaction.
    /// @param value Native token value of the module transaction.
    /// @param data Data payload of the module transaction.
    /// @param operation Operation type (Call or DelegateCall).
    /// @return success Boolean flag indicating if the call succeeded.
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success);

    /// @notice Execute a transaction from an enabled module and return data.
    /// @param to Destination address of the module transaction.
    /// @param value Native token value of the module transaction.
    /// @param data Data payload of the module transaction.
    /// @param operation Operation type (Call or DelegateCall).
    /// @return success Boolean flag indicating if the call succeeded.
    /// @return returnData Data returned by the call.
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData);

    /// @notice Returns whether a module is enabled.
    /// @param module The module address to check.
    /// @return True if the module is enabled, false otherwise.
    function isModuleEnabled(address module) external view returns (bool);
}
