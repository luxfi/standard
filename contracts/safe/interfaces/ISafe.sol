// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

/// @title Safe Smart Account Interface
interface ISafe {
    /// @notice Compute the Safe transaction hash for the given parameters.
    /// @param to The address to which the transaction is intended.
    /// @param value The native token value of the transaction in Wei.
    /// @param data The transaction data.
    /// @param operation Operation type (0 for `CALL`, 1 for `DELEGATECALL`).
    /// @param safeTxGas Gas used for the transaction.
    /// @param baseGas The base gas for the transaction.
    /// @param gasPrice The price of gas in Wei for the transaction.
    /// @param gasToken The token used to pay for gas.
    /// @param refundReceiver The address which should receive the refund.
    /// @param nonce The transaction nonce.
    /// @return safeTxHash The Safe transaction hash.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) external view returns (bytes32 safeTxHash);

    /// @notice Returns the Safe nonce.
    /// @return The current Safe nonce.
    function nonce() external view returns (uint256);
}
