// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AdapterRegistry
 * @notice Central registry for all external protocol adapters
 * @dev Manages allowlist, versioning, and metadata for adapters
 */
contract AdapterRegistry is AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    enum AdapterCategory { ORACLE, DEX, LENDING, BRIDGE, PERPS, AUTOMATION, MEV, RWA }
    enum AdapterStatus { INACTIVE, ACTIVE, DEPRECATED }

    struct AdapterInfo {
        string name;
        string version;
        AdapterCategory category;
        AdapterStatus status;
        address implementation;
        uint256 registeredAt;
        uint256 updatedAt;
        bytes32 configHash;
    }

    mapping(bytes32 => AdapterInfo) public adapters;
    mapping(AdapterCategory => bytes32[]) public adaptersByCategory;
    bytes32[] public allAdapterIds;

    event AdapterRegistered(bytes32 indexed id, string name, AdapterCategory category, address implementation);
    event AdapterUpdated(bytes32 indexed id, string version, AdapterStatus status);
    event AdapterDeprecated(bytes32 indexed id);

    error AdapterExists();
    error AdapterNotFound();
    error InvalidAddress();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function register(
        string calldata name,
        string calldata version,
        AdapterCategory category,
        address implementation
    ) external onlyRole(REGISTRAR_ROLE) returns (bytes32 id) {
        if (implementation == address(0)) revert InvalidAddress();

        id = keccak256(abi.encodePacked(name, category));
        if (adapters[id].registeredAt != 0) revert AdapterExists();

        adapters[id] = AdapterInfo({
            name: name,
            version: version,
            category: category,
            status: AdapterStatus.ACTIVE,
            implementation: implementation,
            registeredAt: block.timestamp,
            updatedAt: block.timestamp,
            configHash: bytes32(0)
        });

        adaptersByCategory[category].push(id);
        allAdapterIds.push(id);

        emit AdapterRegistered(id, name, category, implementation);
    }

    function updateVersion(bytes32 id, string calldata version, address implementation) external onlyRole(REGISTRAR_ROLE) {
        if (adapters[id].registeredAt == 0) revert AdapterNotFound();
        adapters[id].version = version;
        adapters[id].implementation = implementation;
        adapters[id].updatedAt = block.timestamp;
        emit AdapterUpdated(id, version, adapters[id].status);
    }

    function deprecate(bytes32 id) external onlyRole(REGISTRAR_ROLE) {
        if (adapters[id].registeredAt == 0) revert AdapterNotFound();
        adapters[id].status = AdapterStatus.DEPRECATED;
        adapters[id].updatedAt = block.timestamp;
        emit AdapterDeprecated(id);
    }

    function getAdapter(bytes32 id) external view returns (AdapterInfo memory) {
        return adapters[id];
    }

    function getActiveAdapters(AdapterCategory category) external view returns (bytes32[] memory) {
        bytes32[] memory all = adaptersByCategory[category];
        uint256 activeCount;
        for (uint256 i; i < all.length; i++) {
            if (adapters[all[i]].status == AdapterStatus.ACTIVE) activeCount++;
        }
        bytes32[] memory active = new bytes32[](activeCount);
        uint256 j;
        for (uint256 i; i < all.length; i++) {
            if (adapters[all[i]].status == AdapterStatus.ACTIVE) {
                active[j++] = all[i];
            }
        }
        return active;
    }

    function adapterCount() external view returns (uint256) {
        return allAdapterIds.length;
    }
}
