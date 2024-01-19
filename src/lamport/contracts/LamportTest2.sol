// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./LamportLib.sol";
import "./LamportBase.sol";

/*
    @name LamportTest2
    @description Demonstrate how to use the LamportLib library to verify a signature while only storing the hash of a public key
    @author William Doyle
    @date October 3rd 2022
 */
contract LamportTest2 is LamportBase {
    event Message(string message);
    event MessageWithNumber(string message, uint256 number); // admittedly contrived example of how to use lamport system with multiple arguments
    event MessageWithNumberAndAddress(string message, uint256 number, address addr); 

    // publish a signed message to the blockchain ... the message is just text
    function broadcast(
        string memory messageToBroadcast,
        bytes32[2][256] calldata currentpub,
        bytes32 nextPKH,
        bytes[256] calldata sig
    )
        public
        onlyLamportOwner(
            currentpub,
            sig,
            nextPKH,
            abi.encodePacked(messageToBroadcast)
        )
    {
        emit Message(messageToBroadcast);
    }

    // publish a signed message to the blockchain ... the message is text and a number
    function broadcastWithNumber(
        string memory messageToBroadcast,
        uint256 numberToBroadcast,
        bytes32[2][256] calldata currentpub,
        bytes32 nextPKH,
        bytes[256] calldata sig
    )
        public
        onlyLamportOwner(
            currentpub,
            sig,
            nextPKH,
            abi.encodePacked(messageToBroadcast, numberToBroadcast)
        )
    {
        emit MessageWithNumber(messageToBroadcast, numberToBroadcast);
    }

    // publish a signed message to the blockchain ... the message is text, a number, and an address
    function broadcastWithNumberAndAddress(
        string memory messageToBroadcast,
        uint256 numberToBroadcast,
        address addrToBroadcast,
        bytes32[2][256] calldata currentpub,
        bytes32 nextPKH,
        bytes[256] calldata sig
    )
        public
        onlyLamportOwner(
            currentpub,
            sig,
            nextPKH,
            abi.encodePacked(messageToBroadcast, numberToBroadcast, addrToBroadcast)
        )
    {
        emit MessageWithNumberAndAddress(messageToBroadcast, numberToBroadcast, addrToBroadcast);
    }
}
