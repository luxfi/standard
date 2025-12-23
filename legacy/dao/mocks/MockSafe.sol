// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {ISafe} from "../interfaces/safe/ISafe.sol";
import {Enum} from "./safe-smart-account/common/Enum.sol";

contract MockSafe is ISafe {
    address private _owner;
    address private _guard;
    mapping(bytes32 => bool) private _validSignatures;
    mapping(bytes32 => bool) private _shouldRevertOnCheckSignatures;

    constructor() {
        _owner = msg.sender;
    }

    function setOwner(address owner) external {
        _owner = owner;
    }

    function setValidSignature(bytes32 signatureHash, bool isValid) external {
        _validSignatures[signatureHash] = isValid;
    }

    function setShouldRevertOnCheckSignatures(
        bytes32 txHash,
        bool shouldRevert
    ) external {
        _shouldRevertOnCheckSignatures[txHash] = shouldRevert;
    }

    function encodeTransactionData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external pure returns (bytes memory) {
        return
            abi.encode(
                to,
                value,
                data,
                operation,
                safeTxGas,
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                _nonce
            );
    }

    function checkSignatures(
        bytes32 txHash,
        bytes calldata,
        bytes calldata signatures
    ) external view {
        if (_shouldRevertOnCheckSignatures[txHash]) {
            revert("Invalid signatures");
        }

        bytes32 signaturesHash = keccak256(signatures);
        require(_validSignatures[signaturesHash], "Invalid signatures");
    }

    function nonce() external pure returns (uint256) {
        return 0;
    }

    function getThreshold() external pure returns (uint256) {
        return 1;
    }

    function getOwners() external view returns (address[] memory) {
        address[] memory owners = new address[](1);
        owners[0] = _owner;
        return owners;
    }

    function isOwner(address owner) external view returns (bool) {
        return owner == _owner;
    }

    function setGuard(address guard) external {
        _guard = guard;
    }

    function enableModule(address module) external {}

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success) {
        bytes memory txData = this.encodeTransactionData(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            0
        );
        bytes32 txHash = keccak256(txData);
        this.checkSignatures(txHash, "", signatures);

        if (operation == Enum.Operation.Call) {
            (success, ) = to.call{value: value}(data);
        } else {
            success = true;
        }

        return success;
    }

    receive() external payable {}
}
