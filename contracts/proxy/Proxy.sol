// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title Proxy Re-exports
 * @author Lux Industries Inc
 * @notice OpenZeppelin proxy re-exports for @luxfi/standard
 * @dev Import from here - no need for @openzeppelin imports
 *
 * Usage:
 *   import {ERC1967Proxy} from "@luxfi/standard/proxy/Proxy.sol";
 *   import {UUPSUpgradeable} from "@luxfi/standard/proxy/Proxy.sol";
 */

// ERC1967
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

// Transparent
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Beacon
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

// Clones
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

// Base
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

// Upgradeable (from upgradeable contracts)
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
