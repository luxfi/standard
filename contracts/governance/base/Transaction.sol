// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {Enum} from "./Enum.sol";

/**
 * @title Transaction
 * @author Lux Industries Inc
 * @notice Transaction struct for governance proposals
 */

/**
 * @notice Represents a single transaction in a proposal
 * @param to Destination address
 * @param value Ether value to send
 * @param data Calldata to execute
 * @param operation Call or DelegateCall
 */
struct Transaction {
    address to;
    uint256 value;
    bytes data;
    Enum.Operation operation;
}
