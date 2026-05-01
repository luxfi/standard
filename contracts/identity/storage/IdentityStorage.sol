// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { Structs } from "./Structs.sol";

/// @title IdentityStorage — slot layout for upgradeable Identity contracts.
/// @dev Reserved 49-slot gap retained for forward compatibility.
contract IdentityStorage is Structs {
    uint256 internal _executionNonce;

    mapping(bytes32 => Key) internal _keys;
    mapping(uint256 => bytes32[]) internal _keysByPurpose;
    mapping(uint256 => Execution) internal _executions;
    mapping(bytes32 => Claim) internal _claims;
    mapping(uint256 => bytes32[]) internal _claimsByTopic;

    uint256[49] private __gap;
}
