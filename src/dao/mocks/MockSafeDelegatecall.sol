// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockSafeDelegatecall
 * @dev Mock implementation of a Gnosis Safe for testing delegatecall functionality.
 * This mock focuses on the execTransaction functionality with delegatecall support.
 */
contract MockSafeDelegatecall {
    event ExecutionSuccess(bytes returnData);
    event ExecutionFailure();

    /**
     * @dev Execute a transaction from the Safe
     * @param to Destination address
     * @param value Ether value
     * @param data Data payload
     * @param operation Operation type (0: Call, 1: DelegateCall)
     * @return success Whether the transaction was successful
     */
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable returns (bool success) {
        bytes memory returnData;

        if (operation == 1) {
            // DelegateCall
            (success, returnData) = to.delegatecall(data);
        } else {
            // Call
            (success, returnData) = to.call{value: value}(data);
        }

        if (success) {
            emit ExecutionSuccess(returnData);
        } else {
            emit ExecutionFailure();
            // Bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /**
     * @dev Get the Safe's address (helper for tests)
     * @return The address of this Safe
     */
    function getAddress() external view returns (address) {
        return address(this);
    }

    // Allow receiving ETH
    receive() external payable {}
}
