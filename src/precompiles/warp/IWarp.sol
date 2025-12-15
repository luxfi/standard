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
 * Features:
 * - Send messages to other chains via sendWarpMessage
 * - Receive verified messages via getVerifiedWarpMessage
 * - Receive verified block hashes via getVerifiedWarpBlockHash
 * - Query the current blockchain ID
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
 * - getVerifiedWarpBlockHash: 2 gas base + dynamic cost
 *
 * Note: No allow list - anyone can send and receive warp messages.
 */
interface IWarp {
    /**
     * @notice Warp message structure
     */
    struct WarpMessage {
        bytes32 sourceChainID;
        address originSenderAddress;
        bytes payload;
    }

    /**
     * @notice Warp block hash structure
     */
    struct WarpBlockHash {
        bytes32 sourceChainID;
        bytes32 blockHash;
    }

    /**
     * @notice Emitted when a warp message is sent
     * @param sender The address that sent the message
     * @param messageID The unique ID of the message
     * @param message The raw unsigned warp message bytes
     */
    event SendWarpMessage(address indexed sender, bytes32 indexed messageID, bytes message);

    /**
     * @notice Get the blockchain ID of the current chain
     * @return blockchainID The 32-byte blockchain identifier
     */
    function getBlockchainID() external view returns (bytes32 blockchainID);

    /**
     * @notice Get a verified warp block hash by index
     * @param index The index of the warp block hash in the transaction
     * @return warpBlockHash The verified block hash structure
     * @return valid True if the block hash is valid and verified
     */
    function getVerifiedWarpBlockHash(uint32 index)
        external
        view
        returns (WarpBlockHash memory warpBlockHash, bool valid);

    /**
     * @notice Get a verified warp message by index
     * @param index The index of the warp message in the transaction
     * @return message The verified warp message structure
     * @return valid True if the message is valid and verified
     */
    function getVerifiedWarpMessage(uint32 index)
        external
        view
        returns (WarpMessage memory message, bool valid);

    /**
     * @notice Send a warp message to other chains
     * @param payload The message payload to send
     * @return messageID The unique ID of the sent message
     */
    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID);
}

/**
 * @title WarpLib
 * @dev Library for interacting with the Warp Messaging precompile
 */
library WarpLib {
    /// @dev The address of the Warp precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000005;

    /// @dev Gas costs
    uint256 constant GET_BLOCKCHAIN_ID_GAS = 2;
    uint256 constant SEND_WARP_MESSAGE_BASE_GAS = 20375;
    uint256 constant SEND_WARP_MESSAGE_PER_BYTE_GAS = 8;

    error InvalidWarpMessage();
    error WarpMessageNotVerified();
    error WarpBlockHashNotVerified();

    /**
     * @notice Get the current blockchain ID
     * @return blockchainID The 32-byte blockchain identifier
     */
    function getBlockchainID() internal view returns (bytes32 blockchainID) {
        return IWarp(PRECOMPILE_ADDRESS).getBlockchainID();
    }

    /**
     * @notice Send a warp message
     * @param payload The message payload
     * @return messageID The unique message ID
     */
    function sendMessage(bytes memory payload) internal returns (bytes32 messageID) {
        return IWarp(PRECOMPILE_ADDRESS).sendWarpMessage(payload);
    }

    /**
     * @notice Get a verified warp message and revert if invalid
     * @param index The message index
     * @return message The verified message
     */
    function getVerifiedMessageOrRevert(uint32 index)
        internal
        view
        returns (IWarp.WarpMessage memory message)
    {
        bool valid;
        (message, valid) = IWarp(PRECOMPILE_ADDRESS).getVerifiedWarpMessage(index);
        if (!valid) revert WarpMessageNotVerified();
    }

    /**
     * @notice Get a verified warp block hash and revert if invalid
     * @param index The block hash index
     * @return blockHash The verified block hash
     */
    function getVerifiedBlockHashOrRevert(uint32 index)
        internal
        view
        returns (IWarp.WarpBlockHash memory blockHash)
    {
        bool valid;
        (blockHash, valid) = IWarp(PRECOMPILE_ADDRESS).getVerifiedWarpBlockHash(index);
        if (!valid) revert WarpBlockHashNotVerified();
    }

    /**
     * @notice Estimate gas for sending a warp message
     * @param payloadLength The length of the payload in bytes
     * @return gas The estimated gas cost
     */
    function estimateSendGas(uint256 payloadLength) internal pure returns (uint256 gas) {
        return SEND_WARP_MESSAGE_BASE_GAS + (payloadLength * SEND_WARP_MESSAGE_PER_BYTE_GAS);
    }

    /**
     * @notice Check if a message is from a specific chain
     * @param message The warp message
     * @param expectedChainID The expected source chain ID
     * @return True if the message is from the expected chain
     */
    function isFromChain(IWarp.WarpMessage memory message, bytes32 expectedChainID)
        internal
        pure
        returns (bool)
    {
        return message.sourceChainID == expectedChainID;
    }

    /**
     * @notice Check if a message is from a specific sender
     * @param message The warp message
     * @param expectedSender The expected sender address
     * @return True if the message is from the expected sender
     */
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
    using WarpLib for *;

    /// @dev Event emitted when a cross-chain message is received
    event WarpMessageReceived(
        bytes32 indexed sourceChainID,
        address indexed originSender,
        bytes payload
    );

    /**
     * @notice Send a cross-chain message
     * @param payload The message payload
     * @return messageID The unique message ID
     */
    function _sendWarpMessage(bytes memory payload) internal returns (bytes32 messageID) {
        return WarpLib.sendMessage(payload);
    }

    /**
     * @notice Receive and process a cross-chain message
     * @param index The message index in the transaction
     * @return message The verified warp message
     */
    function _receiveWarpMessage(uint32 index)
        internal
        view
        returns (IWarp.WarpMessage memory message)
    {
        return WarpLib.getVerifiedMessageOrRevert(index);
    }

    /**
     * @notice Get the current blockchain ID
     * @return blockchainID The blockchain identifier
     */
    function _getBlockchainID() internal view returns (bytes32 blockchainID) {
        return WarpLib.getBlockchainID();
    }
}

/**
 * @title TrustedSourceWarpReceiver
 * @dev Abstract contract for receiving warp messages from trusted sources only
 */
abstract contract TrustedSourceWarpReceiver is WarpMessenger {
    /// @dev Mapping of trusted source chain IDs
    mapping(bytes32 => bool) public trustedChains;

    /// @dev Mapping of trusted source addresses per chain
    mapping(bytes32 => mapping(address => bool)) public trustedSenders;

    error UntrustedChain(bytes32 chainID);
    error UntrustedSender(bytes32 chainID, address sender);

    /**
     * @notice Receive a message from a trusted source only
     * @param index The message index
     * @return message The verified message
     */
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

    /**
     * @notice Add a trusted chain
     * @param chainID The chain ID to trust
     */
    function _addTrustedChain(bytes32 chainID) internal {
        trustedChains[chainID] = true;
    }

    /**
     * @notice Add a trusted sender for a chain
     * @param chainID The source chain ID
     * @param sender The sender address to trust
     */
    function _addTrustedSender(bytes32 chainID, address sender) internal {
        trustedSenders[chainID][sender] = true;
    }

    /**
     * @notice Remove a trusted chain
     * @param chainID The chain ID to remove
     */
    function _removeTrustedChain(bytes32 chainID) internal {
        trustedChains[chainID] = false;
    }

    /**
     * @notice Remove a trusted sender
     * @param chainID The source chain ID
     * @param sender The sender address to remove
     */
    function _removeTrustedSender(bytes32 chainID, address sender) internal {
        trustedSenders[chainID][sender] = false;
    }
}
