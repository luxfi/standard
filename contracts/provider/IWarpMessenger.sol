// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Subset of the Lux Warp precompile interface that the regulated
///         provider bridge needs. Full IWarpMessenger lives under
///         contracts/precompile/interfaces/IWarp.sol — this minimal copy
///         keeps the provider directory self-contained.
interface IWarpMessenger {
    /// @notice Emit a cross-chain message to `destinationChainID`, addressed
    ///         to `destinationAddress` with `payload` as the message body.
    /// @return messageID 32-byte unique id for the message.
    function sendWarpMessage(bytes32 destinationChainID, address destinationAddress, bytes calldata payload)
        external
        returns (bytes32 messageID);

    /// @notice Read an inbound message by index, verifying the aggregated
    ///         BLS signature from the origin chain's validator set.
    function getVerifiedWarpMessage(uint32 index)
        external
        view
        returns (
            bytes32 sourceChainID,
            address originSenderAddress,
            address destinationAddress,
            bytes memory payload,
            bool valid
        );
}
