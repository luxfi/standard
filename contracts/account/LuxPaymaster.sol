// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BasePaymaster} from "@account-abstraction/core/BasePaymaster.sol";
import {IEntryPoint} from "@account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title LuxPaymaster
 * @author Lux Industries Inc
 * @notice Lux Network ERC-4337 paymaster implementation
 * @dev Extends eth-infinitism's BasePaymaster for gas sponsorship
 * 
 * Built on audited eth-infinitism/account-abstraction v0.9.0
 */
contract LuxPaymaster is BasePaymaster {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @notice Contract version
    string public constant VERSION = "1.0.0";

    /// @notice Signer for paymaster verification
    address public immutable verifyingSigner;

    /// @notice Constructor
    /// @param entryPoint The ERC-4337 EntryPoint contract
    /// @param owner The owner of the paymaster
    /// @param _verifyingSigner The signer address for paymaster verification
    constructor(
        IEntryPoint entryPoint,
        address owner,
        address _verifyingSigner
    ) BasePaymaster(entryPoint, owner) {
        verifyingSigner = _verifyingSigner;
    }

    /// @inheritdoc BasePaymaster
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal view override returns (bytes memory context, uint256 validationData) {
        (userOp, maxCost); // silence unused variable warning
        
        // Extract signature from paymasterAndData
        bytes calldata paymasterAndData = userOp.paymasterAndData;
        require(paymasterAndData.length >= 20 + 65, "LuxPaymaster: invalid signature length");
        
        bytes calldata signature = paymasterAndData[20:];
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        
        if (hash.recover(signature) != verifyingSigner) {
            return ("", 1); // SIG_VALIDATION_FAILED
        }
        
        return ("", 0); // Success
    }

    /// @notice Returns the paymaster version
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
