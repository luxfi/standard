// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {Enum} from "@gnosis.pm/safe-contracts/interfaces/Enum.sol";

/**
 * @title Transaction
 * @notice Struct representing a transaction to be executed by a Safe module
 * @dev This struct is used by DAO Protocol modules to encode transactions
 * that will be executed through Safe's module system. It provides a standard
 * format for specifying transaction details.
 *
 * Used in:
 * - ModuleGovernorV1 for executing passed proposals
 * - ModuleFractalV1 for parent-child DAO operations
 *
 * @param to The target address for the transaction
 * @param value The amount of native token (ETH) to send
 * @param data The encoded function call data
 * @param operation The type of call (Call or DelegateCall)
 */
struct Transaction {
    address to;
    uint256 value;
    bytes data;
    Enum.Operation operation;
}
