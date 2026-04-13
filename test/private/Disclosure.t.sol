// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/private/Disclosure.sol";

contract DisclosureTest is Test {
    Disclosure disc;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);
    address regulator = address(0x5EC);
    bytes32 doc1 = keccak256("disclosure-doc-1");

    function setUp() public {
        disc = new Disclosure();
    }

    // ================================================================
    // (a) Viewing Keys
    // ================================================================

    function test_ViewingKey_RegisterAndGet() public {
        bytes memory wrappedKey = hex"aabbccdd";
        vm.prank(alice);
        disc.registerViewingKey(doc1, bob, wrappedKey);

        bytes memory got = disc.getViewingKey(alice, doc1, bob);
        assertEq(got, wrappedKey);
    }

    function test_ViewingKey_DifferentViewersIsolated() public {
        vm.startPrank(alice);
        disc.registerViewingKey(doc1, bob, hex"11");
        disc.registerViewingKey(doc1, carol, hex"22");
        vm.stopPrank();

        assertEq(disc.getViewingKey(alice, doc1, bob), hex"11");
        assertEq(disc.getViewingKey(alice, doc1, carol), hex"22");
    }

    function test_ViewingKey_Revoke() public {
        vm.startPrank(alice);
        disc.registerViewingKey(doc1, bob, hex"aa");
        disc.revokeViewingKey(doc1, bob);
        vm.stopPrank();

        vm.expectRevert(Disclosure.ViewingKeyNotFound.selector);
        disc.getViewingKey(alice, doc1, bob);
    }

    function test_ViewingKey_RevokeNonexistentReverts() public {
        vm.prank(alice);
        vm.expectRevert(Disclosure.ViewingKeyNotFound.selector);
        disc.revokeViewingKey(doc1, bob);
    }

    function test_ViewingKey_EmptyKeyReverts() public {
        vm.prank(alice);
        vm.expectRevert(Disclosure.EmptyWrappedKey.selector);
        disc.registerViewingKey(doc1, bob, "");
    }

    function test_ViewingKey_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Disclosure.ViewingKeyRegistered(alice, doc1, bob);
        disc.registerViewingKey(doc1, bob, hex"ff");
    }

    // ================================================================
    // (b) Threshold Disclosure
    // ================================================================

    function test_Threshold_CreatePolicy() public {
        address[] memory parties = new address[](3);
        parties[0] = alice;
        parties[1] = bob;
        parties[2] = regulator;

        vm.prank(alice);
        disc.createThresholdPolicy(doc1, parties, 2, hex"aabb");

        (uint256 threshold, uint256 partyCount, bytes memory ct) = disc.getPolicy(alice, doc1);
        assertEq(threshold, 2);
        assertEq(partyCount, 3);
        assertEq(ct, hex"aabb");

        assertTrue(disc.isParty(alice, doc1, alice));
        assertTrue(disc.isParty(alice, doc1, bob));
        assertTrue(disc.isParty(alice, doc1, regulator));
        assertFalse(disc.isParty(alice, doc1, carol));
    }

    function test_Threshold_RequestAndSubmitShares() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = regulator;

        vm.prank(alice);
        disc.createThresholdPolicy(doc1, parties, 2, hex"cc");

        // Regulator requests disclosure.
        bytes32 reason = keccak256("SEC investigation 2026-001");
        vm.prank(regulator);
        bytes32 requestId = disc.requestDisclosure(alice, doc1, reason);

        // Both parties submit shares.
        vm.prank(alice);
        disc.submitShare(requestId, hex"aa01");

        vm.prank(regulator);
        disc.submitShare(requestId, hex"bb02");

        // Verify shares stored.
        assertEq(disc.getShare(requestId, 0), hex"aa01");
        assertEq(disc.getShare(requestId, 1), hex"bb02");

        // Verify request metadata.
        (bytes32 docId,, bytes32 reasonHash, address requester, uint256 shareCount) = disc.getRequest(requestId);
        assertEq(docId, doc1);
        assertEq(reasonHash, reason);
        assertEq(requester, regulator);
        assertEq(shareCount, 2);
    }

    function test_Threshold_UnauthorizedPartyCannotRequest() public {
        address[] memory parties = new address[](1);
        parties[0] = alice;

        vm.prank(alice);
        disc.createThresholdPolicy(doc1, parties, 1, hex"cc");

        vm.prank(carol);
        vm.expectRevert(Disclosure.NotAuthorizedParty.selector);
        disc.requestDisclosure(alice, doc1, keccak256("reason"));
    }

    function test_Threshold_RevokeParty() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        vm.prank(alice);
        disc.createThresholdPolicy(doc1, parties, 1, hex"cc");

        assertTrue(disc.isParty(alice, doc1, bob));

        vm.prank(alice);
        disc.revokeParty(doc1, bob);

        assertFalse(disc.isParty(alice, doc1, bob));

        (, uint256 partyCount,) = disc.getPolicy(alice, doc1);
        assertEq(partyCount, 1);
    }

    function test_Threshold_InvalidThresholdReverts() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        vm.prank(alice);
        vm.expectRevert(Disclosure.InvalidThreshold.selector);
        disc.createThresholdPolicy(doc1, parties, 3, hex"cc");

        vm.prank(alice);
        vm.expectRevert(Disclosure.InvalidThreshold.selector);
        disc.createThresholdPolicy(doc1, parties, 0, hex"cc");
    }

    function test_Threshold_DuplicatePolicyReverts() public {
        address[] memory parties = new address[](1);
        parties[0] = alice;

        vm.startPrank(alice);
        disc.createThresholdPolicy(doc1, parties, 1, hex"cc");

        vm.expectRevert(Disclosure.PolicyAlreadyExists.selector);
        disc.createThresholdPolicy(doc1, parties, 1, hex"dd02");
        vm.stopPrank();
    }

    // ================================================================
    // (c) Selective Disclosure (ZK Attestation)
    // ================================================================

    function test_Attest_EmitsEvent() public {
        bytes32 claimHash = keccak256("accredited-investor");
        bytes4 claimType = bytes4(0x00000002);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Disclosure.Attestation(alice, doc1, claimHash, claimType);
        disc.attest(doc1, claimHash, claimType, hex"deadbeef");
    }

    function test_Attest_EmptyProofReverts() public {
        vm.prank(alice);
        vm.expectRevert(Disclosure.EmptyProof.selector);
        disc.attest(doc1, bytes32(0), bytes4(0), "");
    }

    function test_VerifierRegistry_RegisterAndLookup() public {
        address verifierAddr = address(0xBEEF);
        bytes4 claimType = bytes4(0x00000001);

        disc.registerVerifier(claimType, verifierAddr);
        assertEq(disc.getVerifier(claimType), verifierAddr);
    }

    function test_VerifierRegistry_UnknownReturnsZero() public view {
        assertEq(disc.getVerifier(bytes4(0x99999999)), address(0));
    }

    // Finding 1: registerVerifier access control
    function test_VerifierRegistry_OnlyOwnerCanRegister() public {
        // Attacker (bob) tries to register a verifier — must revert.
        vm.prank(bob);
        vm.expectRevert(Disclosure.NotOwner.selector);
        disc.registerVerifier(bytes4(0x00000001), address(0xBEEF));

        // Owner (this contract deployed disc in setUp) succeeds.
        disc.registerVerifier(bytes4(0x00000001), address(0xBEEF));
        assertEq(disc.getVerifier(bytes4(0x00000001)), address(0xBEEF));
    }

    function test_VerifierRegistry_OwnerIsDeployer() public view {
        assertEq(disc.owner(), address(this));
    }

    // Finding 7: double share submission
    function test_Threshold_DoubleShareReverts() public {
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = regulator;

        vm.prank(alice);
        disc.createThresholdPolicy(doc1, parties, 2, hex"cc");

        vm.prank(regulator);
        bytes32 requestId = disc.requestDisclosure(alice, doc1, keccak256("reason"));

        // Alice submits once — OK.
        vm.prank(alice);
        disc.submitShare(requestId, hex"aa01");

        // Alice submits again — must revert.
        vm.prank(alice);
        vm.expectRevert(Disclosure.ShareAlreadySubmitted.selector);
        disc.submitShare(requestId, hex"aa02");

        // Share count should be 1, not 2.
        (,,,, uint256 shareCount) = disc.getRequest(requestId);
        assertEq(shareCount, 1);
    }
}
