// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

/// @notice Packed user operation.
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

/// @title ERC-4337 Account Interface
interface IERC4337 {
    /// @notice Validate user's signature and nonce
    /// @param userOp The user operation.
    /// @param userOpHash The user operation hash.
    /// @param missingAccountFunds Missing funds that must be deposited.
    /// @return validationData Packed validation data.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}
