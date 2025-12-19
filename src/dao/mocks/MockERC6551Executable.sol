// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockERC6551Executable
 * @dev Mock implementation of ERC6551 Executable for testing purposes.
 * Simulates a token-bound account that can execute transactions.
 */
contract MockERC6551Executable {
    // Event to track executions
    event Executed(
        address indexed target,
        uint256 value,
        bytes data,
        uint8 operation
    );

    /**
     * @dev Execute a transaction from the token-bound account
     * @param target The target address
     * @param value The ETH value to send
     * @param data The call data
     * @param operation The operation type (0 = call, 1 = delegatecall)
     * @return The return data
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable returns (bytes memory) {
        emit Executed(target, value, data, operation);

        // In real implementation, this would execute the call
        // For testing, we execute it to maintain realistic behavior
        if (operation == 0) {
            // Simulate successful call
            (bool success, bytes memory result) = target.call{value: value}(
                data
            );
            require(success, "Execute call failed");
            return result;
        } else {
            // Simulate successful delegatecall
            (bool success, bytes memory result) = target.delegatecall(data);
            require(success, "Execute delegatecall failed");
            return result;
        }
    }

    // Allow receiving ETH
    receive() external payable {}
}
