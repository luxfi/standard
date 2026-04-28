// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AccessControl } from "@luxfi/oz/access/AccessControl.sol";
import { SafeERC20 } from "@luxfi/oz/token/ERC20/utils/SafeERC20.sol";
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { IWarp, WarpLib, TrustedSourceWarpReceiver } from "../../precompile/interfaces/IWarp.sol";

/// @title SecurityBridge
/// @notice Teleport-enabled bridge for ERC-3643 security tokens via Warp.
/// @dev Source-chain: locks (canonical) or burns (wrapped) and emits a Warp message.
///      Destination-chain: verifies the Warp message and mints (wrapped) or releases (canonical).
///      The bridge holds the T-REX agent role on the wrapped token to mint/burn.
contract SecurityBridge is AccessControl, TrustedSourceWarpReceiver {
    using SafeERC20 for IToken;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    enum Action {
        LOCK,
        BURN
    }

    IToken public immutable TOKEN;

    /// @dev Replay protection on consumed Warp message indices.
    mapping(uint32 => bool) public consumedWarpIndex;

    event Teleport(
        Action indexed action,
        address indexed sender,
        uint256 amount,
        bytes32 indexed destinationChainID,
        address recipient,
        bytes32 messageID
    );
    event TeleportClaim(
        Action indexed action,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed sourceChainID,
        uint32 warpIndex
    );

    error ZeroAddress();
    error ZeroAmount();
    error WarpAlreadyConsumed(uint32 index);
    error InvalidWarpPayload();

    constructor(address admin, IToken _token) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(_token) == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        TOKEN = _token;
    }

    // ── Source chain ────────────────────────────────────────────────────────

    /// @notice Lock tokens on this (canonical) chain and emit a Warp message.
    function lock(uint256 amount, bytes32 destinationChainID, address recipient) external returns (bytes32 messageID) {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        messageID = _send(Action.LOCK, msg.sender, amount, destinationChainID, recipient);
    }

    /// @notice Burn tokens on this (wrapped) chain and emit a Warp message.
    function teleport(uint256 amount, bytes32 destinationChainID, address recipient)
        external
        returns (bytes32 messageID)
    {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        TOKEN.burn(msg.sender, amount);
        messageID = _send(Action.BURN, msg.sender, amount, destinationChainID, recipient);
    }

    // ── Destination chain ───────────────────────────────────────────────────

    /// @notice Mint tokens on this (wrapped) chain after verifying the source-chain LOCK.
    function claimMint(uint32 warpIndex) external {
        (Action action, address recipient, uint256 amount, bytes32 sourceChainID) = _consume(warpIndex);
        if (action != Action.LOCK) revert InvalidWarpPayload();
        TOKEN.mint(recipient, amount);
        emit TeleportClaim(action, recipient, amount, sourceChainID, warpIndex);
    }

    /// @notice Release locked tokens on this (canonical) chain after verifying the source-chain BURN.
    function claimRelease(uint32 warpIndex) external {
        (Action action, address recipient, uint256 amount, bytes32 sourceChainID) = _consume(warpIndex);
        if (action != Action.BURN) revert InvalidWarpPayload();
        TOKEN.safeTransfer(recipient, amount);
        emit TeleportClaim(action, recipient, amount, sourceChainID, warpIndex);
    }

    // ── Admin: trusted-chain registry ───────────────────────────────────────

    function addTrustedChain(bytes32 chainID) external onlyRole(ADMIN_ROLE) {
        _addTrustedChain(chainID);
    }

    function removeTrustedChain(bytes32 chainID) external onlyRole(ADMIN_ROLE) {
        _removeTrustedChain(chainID);
    }

    function addTrustedSender(bytes32 chainID, address sender) external onlyRole(ADMIN_ROLE) {
        _addTrustedSender(chainID, sender);
    }

    function removeTrustedSender(bytes32 chainID, address sender) external onlyRole(ADMIN_ROLE) {
        _removeTrustedSender(chainID, sender);
    }

    // ── Internals ───────────────────────────────────────────────────────────

    function _send(Action action, address sender, uint256 amount, bytes32 destChainID, address recipient)
        internal
        returns (bytes32 messageID)
    {
        bytes memory payload = abi.encode(action, recipient, amount);
        messageID = WarpLib.sendMessage(payload);
        emit Teleport(action, sender, amount, destChainID, recipient, messageID);
    }

    function _consume(uint32 warpIndex)
        internal
        returns (Action action, address recipient, uint256 amount, bytes32 sourceChainID)
    {
        if (consumedWarpIndex[warpIndex]) revert WarpAlreadyConsumed(warpIndex);
        consumedWarpIndex[warpIndex] = true;

        IWarp.WarpMessage memory message = _receiveTrustedMessage(warpIndex);
        sourceChainID = message.sourceChainID;
        (action, recipient, amount) = abi.decode(message.payload, (Action, address, uint256));
    }
}
