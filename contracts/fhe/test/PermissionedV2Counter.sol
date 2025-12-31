// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {FHE, euint32, Euint32} from "../FHE.sol";
import {PermissionedV2, PermissionV2} from "../access/PermissionedV2.sol";

contract PermissionedV2Counter is PermissionedV2 {
    mapping(address => euint32) private userCounter;
    address public owner;

    constructor() PermissionedV2("COUNTER") {
        owner = msg.sender;
    }

    function add(Euint32 calldata encryptedValue) public {
        euint32 value = FHE.asEuint32(encryptedValue);
        userCounter[msg.sender] = FHE.add(userCounter[msg.sender], value);
    }

    function getCounter(address user) public view returns (uint32) {
        return FHE.getDecryptResult(userCounter[user]);
    }

    function getCounterPermit(
        PermissionV2 memory permission
    ) public view withPermission(permission) returns (uint32) {
        return FHE.getDecryptResult(userCounter[permission.issuer]);
    }

    function getCounterPermitSealed(
        PermissionV2 memory permission
    ) public view withPermission(permission) returns (bytes memory) {
        return FHE.sealoutput(
            userCounter[permission.issuer],
            permission.sealingKey
        );
    }
}
