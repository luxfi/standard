// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import { SecurityToken } from "./SecurityToken.sol";
import { ComplianceRegistry } from "../compliance/ComplianceRegistry.sol";

/**
 * @title PartitionToken
 * @notice ERC-1400 inspired partitioned security token.
 *
 * Each partition represents a distinct tranche of the same security (e.g., Class A, Class B,
 * locked shares, vested shares). Partitions have independent balances but share the same
 * ComplianceRegistry and SecurityToken base.
 *
 * Simplified implementation covering the core partition mechanics; does not implement
 * the full ERC-1400 operator model.
 */
contract PartitionToken is SecurityToken {
    // ──────────────────────────────────────────────────────────────────────────
    // State
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice partition => account => balance
    mapping(bytes32 => mapping(address => uint256)) public partitionBalanceOf;

    /// @notice partition => total supply
    mapping(bytes32 => uint256) public partitionTotalSupply;

    /// @notice Ordered list of known partitions.
    bytes32[] private _partitions;
    mapping(bytes32 => bool) private _partitionExists;

    bytes32 public constant DEFAULT_PARTITION = keccak256("DEFAULT");

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event TransferByPartition(bytes32 indexed partition, address indexed from, address indexed to, uint256 value);
    event IssueByPartition(bytes32 indexed partition, address indexed to, uint256 value);
    event RedeemByPartition(bytes32 indexed partition, address indexed from, uint256 value);
    event PartitionCreated(bytes32 indexed partition);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error InsufficientPartitionBalance(bytes32 partition, address account, uint256 required, uint256 available);

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(string memory name_, string memory symbol_, address admin, ComplianceRegistry registry)
        SecurityToken(name_, symbol_, admin, registry)
    {
        _registerPartition(DEFAULT_PARTITION);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Partition queries
    // ──────────────────────────────────────────────────────────────────────────

    function partitions() external view returns (bytes32[] memory) {
        return _partitions;
    }

    function partitionCount() external view returns (uint256) {
        return _partitions.length;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Issue / Redeem / Transfer by partition
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Issue tokens into a specific partition.
     * @dev Also mints on the underlying ERC-20 to keep totalSupply consistent.
     */
    function issueByPartition(bytes32 partition, address to, uint256 value) external onlyRole(MINTER_ROLE) {
        _registerPartition(partition);
        partitionBalanceOf[partition][to] += value;
        partitionTotalSupply[partition] += value;
        _mint(to, value);
        emit IssueByPartition(partition, to, value);
    }

    /**
     * @notice Redeem (burn) tokens from a specific partition.
     */
    function redeemByPartition(bytes32 partition, uint256 value) external {
        address sender = _msgSender();
        uint256 bal = partitionBalanceOf[partition][sender];
        if (bal < value) revert InsufficientPartitionBalance(partition, sender, value, bal);

        partitionBalanceOf[partition][sender] = bal - value;
        partitionTotalSupply[partition] -= value;
        _burn(sender, value);
        emit RedeemByPartition(partition, sender, value);
    }

    /**
     * @notice Transfer tokens within a specific partition.
     * @dev Compliance is enforced by the _update hook in SecurityToken.
     */
    function transferByPartition(bytes32 partition, address to, uint256 value) external returns (bool) {
        address sender = _msgSender();
        uint256 bal = partitionBalanceOf[partition][sender];
        if (bal < value) revert InsufficientPartitionBalance(partition, sender, value, bal);

        partitionBalanceOf[partition][sender] = bal - value;
        partitionBalanceOf[partition][to] += value;
        // This triggers _update which enforces compliance
        _transfer(sender, to, value);
        emit TransferByPartition(partition, sender, to, value);
        return true;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal
    // ──────────────────────────────────────────────────────────────────────────

    function _registerPartition(bytes32 partition) internal {
        if (!_partitionExists[partition]) {
            _partitionExists[partition] = true;
            _partitions.push(partition);
            emit PartitionCreated(partition);
        }
    }
}
