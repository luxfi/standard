// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

interface ILightAccountFactory {
    /// @notice Calculate the counterfactual address of this account as it would be returned by `createAccount`.
    /// @param owner The owner of the account to be created.
    /// @param salt A salt, which can be changed to create multiple accounts with the same owner.
    /// @return account The address of the account that would be created with `createAccount`.
    function getAddress(
        address owner,
        uint256 salt
    ) external view returns (address account);
}
