// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.31;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IFinder} from "./interfaces/IFinder.sol";

/**
 * @title Finder
 * @notice Provides addresses of the live contracts implementing certain interfaces.
 * @dev Examples of interfaces with implementations that Finder locates are the Oracle and Store interfaces.
 * This is a service locator pattern for discovering DVM components.
 */
contract Finder is IFinder, Ownable2Step {
    /// @notice Mapping of interface name to implementation address
    mapping(bytes32 => address) public interfacesImplemented;

    /// @notice Emitted when an interface implementation is changed
    event InterfaceImplementationChanged(bytes32 indexed interfaceName, address indexed newImplementationAddress);

    /**
     * @notice Constructs the Finder contract.
     * @param initialOwner The initial owner of the contract.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Updates the address of the contract that implements `interfaceName`.
     * @param interfaceName bytes32 of the interface name that is either changed or registered.
     * @param implementationAddress address of the implementation contract.
     */
    function changeImplementationAddress(
        bytes32 interfaceName,
        address implementationAddress
    ) external override onlyOwner {
        interfacesImplemented[interfaceName] = implementationAddress;
        emit InterfaceImplementationChanged(interfaceName, implementationAddress);
    }

    /**
     * @notice Gets the address of the contract that implements the given `interfaceName`.
     * @param interfaceName queried interface.
     * @return implementationAddress address of the defined interface.
     */
    function getImplementationAddress(bytes32 interfaceName) external view override returns (address) {
        address implementationAddress = interfacesImplemented[interfaceName];
        require(implementationAddress != address(0), "Finder: implementation not found");
        return implementationAddress;
    }
}
