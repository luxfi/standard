// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IWarp
 * @author Lux Industries Inc
 * @notice Interface for the Lux Warp Messaging precompile
 * @dev Precompile at 0x0200000000000000000000000000000000000005
 *
 * The Warp Messenger enables cross-chain communication between
 * Lux Network chains using BLS aggregate signatures.
 *
 * Message Flow:
 * 1. Source chain: Call sendWarpMessage(payload)
 * 2. Validators sign the message using BLS aggregation
 * 3. Destination chain: Include signed message in transaction
 * 4. Destination chain: Call getVerifiedWarpMessage to retrieve
 */
interface IWarp {
    /// @notice Warp message structure
    struct WarpMessage {
        bytes32 sourceChainID;
        address originSenderAddress;
        bytes payload;
    }

    /// @notice Warp block hash structure
    struct WarpBlockHash {
        bytes32 sourceChainID;
        bytes32 blockHash;
    }

    /// @notice Emitted when a warp message is sent
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
     * @param payload The message payload to send (includes destination encoding)
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

    error WarpMessageNotVerified();
    error WarpBlockHashNotVerified();

    /**
     * @notice Get the current blockchain ID
     */
    function getBlockchainID() internal view returns (bytes32 blockchainID) {
        return IWarp(PRECOMPILE_ADDRESS).getBlockchainID();
    }

    /**
     * @notice Send a warp message
     */
    function sendMessage(bytes memory payload) internal returns (bytes32 messageID) {
        return IWarp(PRECOMPILE_ADDRESS).sendWarpMessage(payload);
    }

    /**
     * @notice Get a verified warp message and revert if invalid
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
}

// Legacy alias for backwards compatibility
interface IWarpMessenger is IWarp {}
