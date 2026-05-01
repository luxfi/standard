// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title Structs — ONCHAINID Key/Execution/Claim record types.
contract Structs {
    struct Key {
        uint256[] purposes;
        uint256 keyType;
        bytes32 key;
    }

    struct Execution {
        address to;
        uint256 value;
        bytes data;
        bool approved;
        bool executed;
    }

    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }
}
