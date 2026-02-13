// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {Enum} from "@gnosis.pm/safe-contracts/interfaces/Enum.sol";

/**
 * @title IGuard
 * @author Lux Industriesn Inc (adapted from Gnosis Guard Interface)
 * @notice Interface for guard contracts that check transactions
 * @dev Guards can be used to restrict the actions that can be performed by modules.
 * They implement pre- and post-transaction checks to ensure transactions meet
 * certain criteria before and after execution.
 */
interface IGuard {
    /**
     * @notice Checks a transaction before execution
     * @param to Destination address of module transaction
     * @param value Ether value of module transaction
     * @param data Data payload of module transaction
     * @param operation Operation type of module transaction
     * @param safeTxGas Gas that should be used for the safe transaction
     * @param baseGas Gas costs for data used to trigger the safe transaction
     * @param gasPrice Maximum gas price that should be used for this transaction
     * @param gasToken Token address (or 0 if ETH) that is used for the payment
     * @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin)
     * @param signatures Signature data that should be verified
     * @param msgSender Account that initiated the transaction
     * @dev Should revert if the transaction is not allowed
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external;

    /**
     * @notice Checks after a transaction execution
     * @param txHash Hash of the executed transaction
     * @param success Boolean indicating if the transaction was successful
     * @dev Should revert if the post-execution state is not allowed
     */
    function checkAfterExecution(bytes32 txHash, bool success) external;
}