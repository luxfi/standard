// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title IIdFactory — deterministic ONCHAINID deployer.
interface IIdFactory {
    event Deployed(address indexed _addr);
    event WalletLinked(address indexed wallet, address indexed identity);
    event TokenLinked(address indexed token, address indexed identity);
    event WalletUnlinked(address indexed wallet, address indexed identity);
    event TokenFactoryAdded(address indexed factory);
    event TokenFactoryRemoved(address indexed factory);

    function createIdentity(address _wallet, string memory _salt) external returns (address);
    function createIdentityWithManagementKeys(
        address _wallet,
        string memory _salt,
        bytes32[] memory _managementKeys
    ) external returns (address);
    function createTokenIdentity(address _token, address _tokenOwner, string memory _salt)
        external
        returns (address);

    function linkWallet(address _newWallet) external;
    function unlinkWallet(address _oldWallet) external;
    function addTokenFactory(address _factory) external;
    function removeTokenFactory(address _factory) external;

    function getIdentity(address _wallet) external view returns (address);
    function getWallets(address _identity) external view returns (address[] memory);
    function getToken(address _identity) external view returns (address);
    function isTokenFactory(address _factory) external view returns (bool);
    function isSaltTaken(string calldata _salt) external view returns (bool);
}
