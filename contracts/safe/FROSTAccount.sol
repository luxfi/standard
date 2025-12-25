// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

import {FROST} from "./FROST.sol";
import {IERC4337, PackedUserOperation} from "./interfaces/IERC4337.sol";

/// @title FROST Account
/// @notice An ERC-4337 and ERC-7702 coompatible account.
contract FROSTAccount is IERC4337 {
    /// @notice The supported ERC-4337 entry point contract.
    address private immutable _ENTRY_POINT;

    /// @notice Attempt to call user operation validation or execution function
    /// from a caller other than the supported entry point.
    error UnsupportedEntryPoint();

    constructor(address entryPoint) {
        _ENTRY_POINT = entryPoint;
    }

    receive() external payable {}

    /// @notice Function must be called by the entry point.
    modifier onlyEntryPoint() {
        require(msg.sender == _ENTRY_POINT, UnsupportedEntryPoint());
        _;
    }

    /// @inheritdoc IERC4337
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        onlyEntryPoint
        returns (uint256 validationData)
    {
        if (missingAccountFunds != 0) {
            assembly ("memory-safe") {
                pop(call(gas(), caller(), missingAccountFunds, 0, 0, 0, 0))
            }
        }

        uint256 px;
        uint256 py;
        uint256 rx;
        uint256 ry;
        uint256 z;

        bytes calldata signature = userOp.signature;
        assembly ("memory-safe") {
            px := calldataload(signature.offset)
            py := calldataload(add(signature.offset, 0x20))
            rx := calldataload(add(signature.offset, 0x40))
            ry := calldataload(add(signature.offset, 0x60))
            z := calldataload(add(signature.offset, 0x80))
        }

        return FROST.verify(userOpHash, px, py, rx, ry, z) == address(this) ? 0 : 1;
    }

    /// @notice Execute a transaction.
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPoint {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, data.offset, data.length)

            if iszero(call(gas(), target, value, ptr, data.length, 0, 0)) {
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
        }
    }
}
