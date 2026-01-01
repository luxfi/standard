// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {Enum} from "@luxfi/contracts/governance/base/Enum.sol";

/**
 * @title IGuard
 * @author Lux Industries Inc
 * @notice Interface for transaction guards that can check transactions before/after execution
 * @dev Guards provide a hook system for pre/post transaction validation.
 * They can be used for:
 * - Access control
 * - Spending limits
 * - Time locks
 * - Freeze functionality
 * - Custom validation logic
 */
interface IGuard {
    /**
     * @notice Called before transaction execution
     * @dev Reverts if the transaction should be blocked
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Call or DelegateCall
     * @param safeTxGas Gas for Safe transaction
     * @param baseGas Base gas
     * @param gasPrice Gas price
     * @param gasToken Token used for gas payment
     * @param refundReceiver Address to receive refund
     * @param signatures Transaction signatures
     * @param msgSender Original message sender
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
     * @notice Called after transaction execution
     * @dev Reverts if post-execution check fails
     * @param txHash Hash of the executed transaction
     * @param success Whether the transaction succeeded
     */
    function checkAfterExecution(bytes32 txHash, bool success) external;
}
