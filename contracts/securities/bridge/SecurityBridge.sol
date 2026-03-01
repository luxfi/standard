// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SecurityToken} from "../token/SecurityToken.sol";

/**
 * @title SecurityBridge
 * @notice Cross-chain mint/burn/teleport bridge for security tokens.
 *
 * Implements a lock-and-mint / burn-and-release pattern for moving security tokens
 * across Lux chains (C-Chain, Liquidity L2, Zoo EVM, subnets).
 *
 * The bridge operator (BRIDGE_ROLE) is expected to be a multisig or relay contract
 * that verifies cross-chain messages before executing mint/release.
 */
contract SecurityBridge is AccessControl {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    SecurityToken public immutable token;

    /// @notice Nonce for deduplication of cross-chain messages.
    mapping(bytes32 => bool) public processedNonces;

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event BridgeLock(
        address indexed sender,
        uint256 amount,
        uint256 indexed destinationChainId,
        address indexed destinationAddress,
        bytes32 nonce
    );
    event BridgeMint(address indexed recipient, uint256 amount, uint256 indexed sourceChainId, bytes32 nonce);
    event BridgeBurn(address indexed sender, uint256 amount, uint256 indexed destinationChainId, bytes32 nonce);
    event BridgeRelease(address indexed recipient, uint256 amount, uint256 indexed sourceChainId, bytes32 nonce);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error ZeroAmount();
    error NonceAlreadyProcessed(bytes32 nonce);

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address admin, SecurityToken _token) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(_token) == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ROLE, admin);
        token = _token;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Source chain: lock or burn
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Lock tokens on this chain to bridge to another chain.
     *         Tokens are transferred to this contract (locked).
     */
    function lock(uint256 amount, uint256 destinationChainId, address destinationAddress) external {
        if (amount == 0) revert ZeroAmount();
        if (destinationAddress == address(0)) revert ZeroAddress();

        address sender = _msgSender();
        bytes32 nonce = keccak256(abi.encodePacked(sender, amount, destinationChainId, block.timestamp, block.number));

        // Transfer tokens to this contract (lock)
        token.transferFrom(sender, address(this), amount);

        emit BridgeLock(sender, amount, destinationChainId, destinationAddress, nonce);
    }

    /**
     * @notice Burn tokens on this chain to bridge to another chain.
     *         Used when this chain is the "wrapped" side.
     */
    function burn(uint256 amount, uint256 destinationChainId) external {
        if (amount == 0) revert ZeroAmount();

        address sender = _msgSender();
        bytes32 nonce = keccak256(abi.encodePacked(sender, amount, destinationChainId, block.timestamp, block.number));

        token.burnFrom(sender, amount);

        emit BridgeBurn(sender, amount, destinationChainId, nonce);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Destination chain: mint or release (bridge operator only)
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Mint tokens on this chain after verifying a lock on the source chain.
     */
    function bridgeMint(address recipient, uint256 amount, uint256 sourceChainId, bytes32 nonce)
        external
        onlyRole(BRIDGE_ROLE)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (processedNonces[nonce]) revert NonceAlreadyProcessed(nonce);

        processedNonces[nonce] = true;
        token.mint(recipient, amount);

        emit BridgeMint(recipient, amount, sourceChainId, nonce);
    }

    /**
     * @notice Release locked tokens on this chain after verifying a burn on the source chain.
     */
    function bridgeRelease(address recipient, uint256 amount, uint256 sourceChainId, bytes32 nonce)
        external
        onlyRole(BRIDGE_ROLE)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (processedNonces[nonce]) revert NonceAlreadyProcessed(nonce);

        processedNonces[nonce] = true;
        token.transfer(recipient, amount);

        emit BridgeRelease(recipient, amount, sourceChainId, nonce);
    }
}
