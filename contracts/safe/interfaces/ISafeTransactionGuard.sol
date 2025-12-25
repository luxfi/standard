// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {IERC165} from "./IERC165.sol";

/// @title Safe Transaction Guard Interface
interface ISafeTransactionGuard is IERC165 {
    /// @notice Check before a Safe transaction is executed.
    /// @dev This function reverts if the transaction is not allowed.
    /// @param to The address to which the transaction is intended.
    /// @param value The native token value of the transaction in Wei.
    /// @param data The transaction data.
    /// @param operation Operation type (0 for `CALL`, 1 for `DELEGATECALL`).
    /// @param safeTxGas Gas used for the transaction.
    /// @param baseGas The base gas for the transaction.
    /// @param gasPrice The price of gas in Wei for the transaction.
    /// @param gasToken The token used to pay for gas.
    /// @param refundReceiver The address which should receive the refund.
    /// @param signatures The signatures of the transaction.
    /// @param msgSender The address of the message sender.
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external;

    /// @notice Check after a Safe transaction is executed.
    /// @dev This function reverts if the transaction is not allowed.
    /// @param txHash The hash of the executed transaction.
    /// @param success The status of the transaction execution.
    function checkAfterExecution(bytes32 txHash, bool success) external;
}
