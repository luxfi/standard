// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title LuxTimelock
 * @author Lux Industries Inc
 * @notice Timelock controller for Lux governance
 * @dev Thin wrapper around OpenZeppelin's TimelockController
 * 
 * Built on audited OpenZeppelin Contracts v5.1.0
 */
contract LuxTimelock is TimelockController {
    /// @notice Contract version
    string public constant VERSION = "1.0.0";

    /**
     * @notice Constructor
     * @param minDelay Minimum delay for proposal execution
     * @param proposers Addresses that can propose
     * @param executors Addresses that can execute (address(0) = anyone)
     * @param admin Admin address (address(0) = no admin)
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    /// @notice Returns the timelock version
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
