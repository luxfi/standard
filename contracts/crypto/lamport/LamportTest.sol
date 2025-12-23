// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LamportLib.sol";

/**
 * @title LamportTest
 * @notice Test contract for Lamport signature verification
 */
contract LamportTest {
    bytes32[2][256] public pubKey;
    bool public pubKeySet;

    event SignatureVerified(bytes32 message);

    function setPubKey(bytes32[2][256] memory _pubKey) external {
        pubKey = _pubKey;
        pubKeySet = true;
    }

    function doSomething(bytes32 message, bytes32[] memory signature) external {
        require(pubKeySet, "Public key not set");
        require(LamportLib.verify(message, signature, pubKey), "Invalid signature");
        emit SignatureVerified(message);
    }
}
