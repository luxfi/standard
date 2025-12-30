// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.31;

/**
 * @title Enum
 * @author Lux Industries Inc (adapted from Gnosis Safe)
 * @notice Enum library for Safe/governance operation types
 */
library Enum {
    /**
     * @notice Operation type for transaction execution
     * @dev Call is a regular external call
     * @dev DelegateCall executes code in the context of the caller
     */
    enum Operation {
        Call,
        DelegateCall
    }
}
