// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {SimpleAccountFactory} from "@account-abstraction/accounts/SimpleAccountFactory.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

/**
 * @title EOAFactory
 * @author Lux Industries Inc
 * @notice Factory for deploying EOA smart wallets
 * @dev Extends eth-infinitism's SimpleAccountFactory
 *
 * Built on audited eth-infinitism/account-abstraction v0.9.0
 */
contract EOAFactory is SimpleAccountFactory {
    /// @notice Contract version
    string public constant VERSION = "1.0.0";

    /// @notice Constructor
    /// @param entryPoint The ERC-4337 EntryPoint contract
    constructor(IEntryPoint entryPoint) SimpleAccountFactory(entryPoint) {}

    /// @notice Returns the factory version
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
