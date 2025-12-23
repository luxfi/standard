// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context.
 * Used by LRC20 and other Lux contracts.
 */
library Context {
    function msgSender() internal view returns (address) {
        return msg.sender;
    }

    function msgData() internal pure returns (bytes calldata) {
        return msg.data;
    }
}
