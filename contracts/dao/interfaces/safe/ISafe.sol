// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {Enum} from "@gnosis.pm/safe-contracts/interfaces/Enum.sol";

interface ISafe {
    // --- View Functions ---

    function isOwner(address owner_) external view returns (bool isOwner);

    function nonce() external view returns (uint256 nonce);

    function checkSignatures(
        bytes32 dataHash_,
        bytes memory data_,
        bytes memory signatures_
    ) external view;

    function encodeTransactionData(
        address to_,
        uint256 value_,
        bytes calldata data_,
        Enum.Operation operation_,
        uint256 safeTxGas_,
        uint256 baseGas_,
        uint256 gasPrice_,
        address gasToken_,
        address refundReceiver_,
        uint256 nonce_
    ) external view returns (bytes memory encodedTransactionData);

    // --- State-Changing Functions ---

    function setGuard(address guard_) external;

    function enableModule(address module_) external;

    function execTransaction(
        address to_,
        uint256 value_,
        bytes calldata data_,
        Enum.Operation operation_,
        uint256 safeTxGas_,
        uint256 baseGas_,
        uint256 gasPrice_,
        address gasToken_,
        address payable refundReceiver_,
        bytes memory signatures_
    ) external payable returns (bool success);
}
