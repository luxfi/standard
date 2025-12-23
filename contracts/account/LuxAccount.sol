// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleAccount} from "@account-abstraction/accounts/SimpleAccount.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";

/**
 * @title LuxAccount
 * @author Lux Industries Inc
 * @notice Lux Network ERC-4337 smart account implementation
 * @dev Extends eth-infinitism's SimpleAccount with Lux-specific features
 * 
 * Built on audited eth-infinitism/account-abstraction v0.9.0
 * See: https://github.com/eth-infinitism/account-abstraction
 */
contract LuxAccount is SimpleAccount {
    /// @notice Contract version
    string public constant VERSION = "1.0.0";

    /// @notice Constructor
    /// @param anEntryPoint The ERC-4337 EntryPoint contract
    constructor(IEntryPoint anEntryPoint) SimpleAccount(anEntryPoint) {}

    /// @notice Returns the account implementation version
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
