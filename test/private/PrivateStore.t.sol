// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/private/PrivateStore.sol";

contract PrivateStoreTest is Test {
    PrivateStore store;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    bytes32 tagA = keccak256("watchlist");

    function setUp() public {
        store = new PrivateStore(0); // 0 => default 48 KiB
    }

    function test_PutGet() public {
        bytes memory ct = hex"deadbeefcafebabe";
        vm.prank(alice);
        store.put(tagA, ct);
        assertEq(store.get(alice, tagA), ct);
    }

    function test_Isolation_AliceAndBobDontCollide() public {
        bytes memory ctA = hex"aa";
        bytes memory ctB = hex"bb";
        vm.prank(alice);
        store.put(tagA, ctA);
        vm.prank(bob);
        store.put(tagA, ctB);
        assertEq(store.get(alice, tagA), ctA);
        assertEq(store.get(bob, tagA), ctB);
    }

    function test_Overwrite() public {
        vm.prank(alice);
        store.put(tagA, hex"11");
        vm.prank(alice);
        store.put(tagA, hex"2222");
        assertEq(store.get(alice, tagA), hex"2222");
    }

    function test_Delete() public {
        vm.prank(alice);
        store.put(tagA, hex"cc");
        vm.prank(alice);
        store.del(tagA);
        vm.expectRevert(PrivateStore.NotFound.selector);
        store.get(alice, tagA);
    }

    function test_Delete_OnlyOwnerKeyspaceAffected() public {
        bytes memory ctA = hex"aa";
        vm.prank(alice);
        store.put(tagA, ctA);
        vm.prank(bob);
        vm.expectRevert(PrivateStore.NotFound.selector);
        store.del(tagA);
        assertEq(store.get(alice, tagA), ctA);
    }

    function test_EmptyPut_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(PrivateStore.EmptyCiphertext.selector);
        store.put(tagA, "");
    }

    function test_GetNonExistent_Reverts() public {
        vm.expectRevert(PrivateStore.NotFound.selector);
        store.get(alice, tagA);
    }

    function test_UpdatedAt() public {
        assertEq(store.updatedAt(alice, tagA), 0);
        vm.warp(1700000000);
        vm.prank(alice);
        store.put(tagA, hex"dd");
        assertEq(store.updatedAt(alice, tagA), 1700000000);
    }

    // Finding 11: unbounded ct size
    function test_Put_RejectsTooLarge() public {
        PrivateStore small = new PrivateStore(64); // 64-byte cap
        bytes memory ct = new bytes(65);
        ct[0] = 0x01;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PrivateStore.CiphertextTooLarge.selector, 65, 64));
        small.put(tagA, ct);
    }

    function test_Put_AcceptsAtCap() public {
        PrivateStore small = new PrivateStore(64);
        bytes memory ct = new bytes(64);
        ct[0] = 0x01;
        vm.prank(alice);
        small.put(tagA, ct);
        assertEq(small.get(alice, tagA).length, 64);
    }

    function test_DefaultMaxCtSize() public view {
        assertEq(store.maxCtSize(), 48 << 10);
    }
}
