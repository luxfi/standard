// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

import {DIDRegistry} from "../../contracts/identity/DIDRegistry.sol";
import {DIDResolver} from "../../contracts/identity/DIDResolver.sol";

/**
 * @title IdentityMinimalTest
 * @notice Minimal test to verify Identity contracts compile
 */
contract IdentityMinimalTest is Test {
    DIDRegistry public registry;
    DIDResolver public resolver;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.startPrank(admin);
        registry = new DIDRegistry(admin, "lux", true);
        resolver = new DIDResolver(admin, address(registry));
        vm.stopPrank();
    }

    function test_BasicDIDCreation() public {
        vm.prank(alice);
        string memory did = registry.createDID("lux", "alice");

        assertEq(did, "did:lux:alice", "DID should match");
        assertTrue(registry.didExists(did), "DID should exist");
    }
}
