// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title IWarp
 * @dev Interface for the Warp Messaging precompile
 *
 * This precompile enables cross-chain communication between Lux subnets.
 * It allows contracts to send and receive verified messages across chains.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000005
 *
 * Message Flow:
 * 1. Source chain: Call sendWarpMessage(payload)
 * 2. Validators sign the message using BLS aggregation
 * 3. Destination chain: Include signed message in transaction
 * 4. Destination chain: Call getVerifiedWarpMessage to retrieve
 *
 * Gas Costs:
 * - getBlockchainID: 2 gas
 * - sendWarpMessage: ~20,375 gas + 8 gas per payload byte
 * - getVerifiedWarpMessage: 2 gas base + dynamic cost
 */
interface IWarp {
    struct WarpMessage {
        bytes32 sourceChainID;
        address originSenderAddress;
        bytes payload;
    }

    struct WarpBlockHash {
        bytes32 sourceChainID;
        bytes32 blockHash;
    }

    event SendWarpMessage(address indexed sender, bytes32 indexed messageID, bytes message);

    function getBlockchainID() external view returns (bytes32 blockchainID);

    function getVerifiedWarpBlockHash(uint32 index)
        external
        view
        returns (WarpBlockHash memory warpBlockHash, bool valid);

    function getVerifiedWarpMessage(uint32 index)
        external
        view
        returns (WarpMessage memory message, bool valid);

    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID);
}

/**
 * @title WarpLib
 * @dev Library for interacting with the Warp Messaging precompile
 */
library WarpLib {
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000005;

    uint256 constant GET_BLOCKCHAIN_ID_GAS = 2;
    uint256 constant SEND_WARP_MESSAGE_BASE_GAS = 20375;
    uint256 constant SEND_WARP_MESSAGE_PER_BYTE_GAS = 8;

    error InvalidWarpMessage();
    error WarpMessageNotVerified();
    error WarpBlockHashNotVerified();

    function getBlockchainID() internal view returns (bytes32 blockchainID) {
        return IWarp(PRECOMPILE_ADDRESS).getBlockchainID();
    }

    function sendMessage(bytes memory payload) internal returns (bytes32 messageID) {
        return IWarp(PRECOMPILE_ADDRESS).sendWarpMessage(payload);
    }

    function getVerifiedMessageOrRevert(uint32 index)
        internal
        view
        returns (IWarp.WarpMessage memory message)
    {
        bool valid;
        (message, valid) = IWarp(PRECOMPILE_ADDRESS).getVerifiedWarpMessage(index);
        if (!valid) revert WarpMessageNotVerified();
    }

    function getVerifiedBlockHashOrRevert(uint32 index)
        internal
        view
        returns (IWarp.WarpBlockHash memory blockHash)
    {
        bool valid;
        (blockHash, valid) = IWarp(PRECOMPILE_ADDRESS).getVerifiedWarpBlockHash(index);
        if (!valid) revert WarpBlockHashNotVerified();
    }

    function estimateSendGas(uint256 payloadLength) internal pure returns (uint256 gas) {
        return SEND_WARP_MESSAGE_BASE_GAS + (payloadLength * SEND_WARP_MESSAGE_PER_BYTE_GAS);
    }

    function isFromChain(IWarp.WarpMessage memory message, bytes32 expectedChainID)
        internal
        pure
        returns (bool)
    {
        return message.sourceChainID == expectedChainID;
    }

    function isFromSender(IWarp.WarpMessage memory message, address expectedSender)
        internal
        pure
        returns (bool)
    {
        return message.originSenderAddress == expectedSender;
    }
}

/**
 * @title WarpMessenger
 * @dev Abstract contract for cross-chain messaging using Warp
 */
abstract contract WarpMessenger {
    event WarpMessageReceived(
        bytes32 indexed sourceChainID,
        address indexed originSender,
        bytes payload
    );

    function _sendWarpMessage(bytes memory payload) internal returns (bytes32 messageID) {
        return WarpLib.sendMessage(payload);
    }

    function _receiveWarpMessage(uint32 index)
        internal
        view
        returns (IWarp.WarpMessage memory message)
    {
        return WarpLib.getVerifiedMessageOrRevert(index);
    }

    function _getBlockchainID() internal view returns (bytes32 blockchainID) {
        return WarpLib.getBlockchainID();
    }
}

/**
 * @title TrustedSourceWarpReceiver
 * @dev Abstract contract for receiving warp messages from trusted sources only
 */
abstract contract TrustedSourceWarpReceiver is WarpMessenger {
    mapping(bytes32 => bool) public trustedChains;
    mapping(bytes32 => mapping(address => bool)) public trustedSenders;

    error UntrustedChain(bytes32 chainID);
    error UntrustedSender(bytes32 chainID, address sender);

    function _receiveTrustedMessage(uint32 index)
        internal
        view
        returns (IWarp.WarpMessage memory message)
    {
        message = _receiveWarpMessage(index);

        if (!trustedChains[message.sourceChainID]) {
            revert UntrustedChain(message.sourceChainID);
        }

        if (!trustedSenders[message.sourceChainID][message.originSenderAddress]) {
            revert UntrustedSender(message.sourceChainID, message.originSenderAddress);
        }
    }

    function _addTrustedChain(bytes32 chainID) internal {
        trustedChains[chainID] = true;
    }

    function _addTrustedSender(bytes32 chainID, address sender) internal {
        trustedSenders[chainID][sender] = true;
    }

    function _removeTrustedChain(bytes32 chainID) internal {
        trustedChains[chainID] = false;
    }

    function _removeTrustedSender(bytes32 chainID, address sender) internal {
        trustedSenders[chainID][sender] = false;
    }
}
