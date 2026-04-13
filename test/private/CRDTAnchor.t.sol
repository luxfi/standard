// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/private/CRDTAnchor.sol";

contract CRDTAnchorTest is Test {
    CRDTAnchor anchor;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    bytes32 doc1 = keccak256("document-1");

    function setUp() public {
        anchor = new CRDTAnchor(0); // 0 => default 2^32
    }

    function test_Checkpoint_StoresAndReads() public {
        bytes32 root = keccak256("state-root-1");
        vm.warp(1700000000);
        vm.prank(alice);
        anchor.checkpoint(doc1, root, 1);

        (bytes32 gotRoot, uint64 gotOp, uint64 gotTs) = anchor.latest(alice, doc1);
        assertEq(gotRoot, root);
        assertEq(gotOp, 1);
        assertEq(gotTs, 1700000000);
    }

    function test_Checkpoint_MonotonicOpCount() public {
        vm.startPrank(alice);
        anchor.checkpoint(doc1, bytes32(uint256(1)), 5);
        anchor.checkpoint(doc1, bytes32(uint256(2)), 10);

        (bytes32 root, uint64 opCount,) = anchor.latest(alice, doc1);
        assertEq(root, bytes32(uint256(2)));
        assertEq(opCount, 10);
        vm.stopPrank();
    }

    function test_Checkpoint_RejectsRollback() public {
        vm.startPrank(alice);
        anchor.checkpoint(doc1, bytes32(uint256(1)), 10);

        vm.expectRevert(abi.encodeWithSelector(CRDTAnchor.OpCountNotMonotonic.selector, 10, 5));
        anchor.checkpoint(doc1, bytes32(uint256(2)), 5);
        vm.stopPrank();
    }

    function test_Checkpoint_RejectsEqualOpCount() public {
        vm.startPrank(alice);
        anchor.checkpoint(doc1, bytes32(uint256(1)), 10);

        vm.expectRevert(abi.encodeWithSelector(CRDTAnchor.OpCountNotMonotonic.selector, 10, 10));
        anchor.checkpoint(doc1, bytes32(uint256(2)), 10);
        vm.stopPrank();
    }

    function test_Checkpoint_RejectsZeroOpCount() public {
        vm.prank(alice);
        vm.expectRevert(CRDTAnchor.ZeroOpCount.selector);
        anchor.checkpoint(doc1, bytes32(uint256(1)), 0);
    }

    function test_Isolation_AliceAndBobIndependent() public {
        bytes32 rootA = keccak256("alice-root");
        bytes32 rootB = keccak256("bob-root");

        vm.prank(alice);
        anchor.checkpoint(doc1, rootA, 1);

        vm.prank(bob);
        anchor.checkpoint(doc1, rootB, 1);

        (bytes32 gotA,,) = anchor.latest(alice, doc1);
        (bytes32 gotB,,) = anchor.latest(bob, doc1);
        assertEq(gotA, rootA);
        assertEq(gotB, rootB);
    }

    function test_Latest_ReturnsZerosForUnknown() public view {
        (bytes32 root, uint64 opCount, uint64 ts) = anchor.latest(alice, doc1);
        assertEq(root, bytes32(0));
        assertEq(opCount, 0);
        assertEq(ts, 0);
    }

    function test_Checkpoint_EmitsEvent() public {
        bytes32 root = keccak256("event-root");
        vm.warp(1700000000);
        vm.prank(alice);

        vm.expectEmit(true, true, false, true);
        emit CRDTAnchor.CheckpointEvent(alice, doc1, root, 42, 1700000000);
        anchor.checkpoint(doc1, root, 42);
    }

    // Finding 12: gap attack mitigation
    function test_Checkpoint_RejectsGapAttack() public {
        CRDTAnchor small = new CRDTAnchor(100); // max jump = 100
        vm.startPrank(alice);
        small.checkpoint(doc1, bytes32(uint256(1)), 1);

        // Jump of 101 should be rejected.
        vm.expectRevert(abi.encodeWithSelector(CRDTAnchor.OpCountJumpTooLarge.selector, 102, 100));
        small.checkpoint(doc1, bytes32(uint256(2)), 103);

        // Jump of exactly 100 should succeed.
        small.checkpoint(doc1, bytes32(uint256(3)), 101);
        vm.stopPrank();
    }

    function test_DefaultMaxOpCountJump() public view {
        assertEq(anchor.maxOpCountJump(), uint64(1) << 32);
    }
}
