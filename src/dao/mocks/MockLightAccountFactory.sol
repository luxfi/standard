// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    ILightAccountFactory
} from "../interfaces/light-account/ILightAccountFactory.sol";

contract MockLightAccountFactory is ILightAccountFactory {
    mapping(address => mapping(uint256 => address)) private _accountAddresses; // owner => salt => account
    mapping(address => bool) private _isDeployed; // account => isDeployed. Keep for testing flexibility if needed elsewhere.
    mapping(address => address) private _accountOwners; // account => owner. Keep for testing flexibility.

    constructor() {}

    // --- ILightAccountFactory implementation ---
    function getAddress(
        address _owner,
        uint256 _salt
    ) external view override returns (address) {
        return _accountAddresses[_owner][_salt];
    }

    // --- Mock-specific setters for testing ---
    // These are not part of ILightAccountFactory but are useful for tests.
    function setAccountAddress(
        address _owner,
        uint256 _salt,
        address _accountAddress
    ) external {
        _accountAddresses[_owner][_salt] = _accountAddress;
    }

    function setIsDeployed(address _account, bool _deployed) external {
        _isDeployed[_account] = _deployed;
    }

    function getAccountOwner(address _account) external view returns (address) {
        return _accountOwners[_account];
    }

    function setAccountOwner(address _account, address _owner) external {
        _accountOwners[_account] = _owner;
    }
}
