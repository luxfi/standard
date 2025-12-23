// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IHatsModuleFactory {
    error HatsModuleFactory_ModuleAlreadyDeployed(
        address implementation,
        uint256 hatId,
        bytes otherImmutableArgs,
        uint256 saltNonce
    );

    error BatchArrayLengthMismatch();

    event HatsModuleFactory_ModuleDeployed(
        address implementation,
        address instance,
        uint256 hatId,
        bytes otherImmutableArgs,
        bytes initData,
        uint256 saltNonce
    );

    function HATS() external view returns (address);

    function version() external view returns (string memory);

    function createHatsModule(
        address _implementation,
        uint256 _hatId,
        bytes calldata _otherImmutableArgs,
        bytes calldata _initData,
        uint256 _saltNonce
    ) external returns (address _instance);

    function batchCreateHatsModule(
        address[] calldata _implementations,
        uint256[] calldata _hatIds,
        bytes[] calldata _otherImmutableArgsArray,
        bytes[] calldata _initDataArray,
        uint256[] calldata _saltNonces
    ) external returns (bool success);

    function getHatsModuleAddress(
        address _implementation,
        uint256 _hatId,
        bytes calldata _otherImmutableArgs,
        uint256 _saltNonce
    ) external view returns (address);

    function deployed(
        address _implementation,
        uint256 _hatId,
        bytes calldata _otherImmutableArgs,
        uint256 _saltNonce
    ) external view returns (bool);
}
