// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { BridgeV4 } from "../../../contracts/bridge/v4/BridgeV4.sol";
import { BasketRegistry } from "../../../contracts/bridge/v4/BasketRegistry.sol";
import { BridgedUSDT } from "../../../contracts/bridge/collateral/USDT.sol";
import { MockP3QPrecompile, MockZChainBridge } from "./Mocks.sol";

contract ZHooksTest is Test {
    BridgeV4 internal bridge;
    BasketRegistry internal registry;
    BridgedUSDT internal usdt;
    MockP3QPrecompile internal precompile;
    MockZChainBridge internal zChain;

    address internal admin = makeAddr("admin");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal user = makeAddr("user");

    function setUp() public {
        vm.startPrank(admin);
        registry = new BasketRegistry(admin);
        bridge = new BridgeV4(admin, address(registry), feeReceiver);
        precompile = new MockP3QPrecompile();
        zChain = new MockZChainBridge();
        bridge.setPrecompileOverride(address(precompile));
        usdt = new BridgedUSDT();
        usdt.grantAdmin(address(bridge));
        usdt.grantMinter(address(bridge));
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, address(usdt), 0);
        vm.stopPrank();
    }

    function _envelope(uint64 nonce, address asset, uint256 amount, address recip)
        internal
        pure
        returns (bytes memory)
    {
        BridgeV4.BridgeEnvelope memory e = BridgeV4.BridgeEnvelope({
            srcChain: 1,
            srcTx: bytes32(uint256(nonce)),
            dstAsset: asset,
            amount: amount,
            recipient: recip,
            nonce: nonce,
            classical: false
        });
        return abi.encode(e);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  ZClaim — not configured by default
    // ─────────────────────────────────────────────────────────────────────

    function test_ZClaim_RevertsIfZChainNotSet() public {
        bytes memory env = _envelope(1, address(usdt), 1e6, address(0xABCD));
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZChainNotConfigured.selector);
        bridge.zClaim(env, hex"", bytes32(uint256(0x1234)));
    }

    function test_ZClaim_RoutesToZChain() public {
        vm.prank(admin);
        bridge.setZChainBridge(address(zChain));

        bytes memory env = _envelope(1, address(usdt), 1e6, address(0xABCD));
        bytes32 commit = keccak256("commitment");

        vm.prank(user);
        bytes32 cid = bridge.zClaim(env, hex"", commit);

        assertEq(zChain.mintsLength(), 1);
        (address asset, uint256 amount, bytes32 c, bytes32 cidOut) = zChain.mints(0);
        assertEq(asset, address(usdt));
        assertEq(amount, 1e6);
        assertEq(c, commit);
        assertEq(cidOut, cid);
        assertTrue(bridge.usedClaims(cid));
    }

    function test_ZClaim_DedupsByClaimId() public {
        vm.prank(admin);
        bridge.setZChainBridge(address(zChain));

        bytes memory env = _envelope(1, address(usdt), 1e6, address(0xABCD));
        bytes32 commit = keccak256("commitment");

        vm.prank(user);
        bridge.zClaim(env, hex"", commit);

        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ClaimAlreadyUsed.selector);
        bridge.zClaim(env, hex"", commit);
    }

    function test_ZClaim_P3QInvalid_Reverts() public {
        vm.prank(admin);
        bridge.setZChainBridge(address(zChain));
        precompile.setValid(false);

        bytes memory env = _envelope(1, address(usdt), 1e6, address(0xABCD));
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_EnvelopeInvalid.selector);
        bridge.zClaim(env, hex"", bytes32(uint256(0xCAFE)));
    }

    // ─────────────────────────────────────────────────────────────────────
    //  ZRedeem
    // ─────────────────────────────────────────────────────────────────────

    function test_ZRedeem_RevertsIfZChainNotSet() public {
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZChainNotConfigured.selector);
        bridge.zRedeem(bytes32(uint256(1)), address(usdt), 1e6, 1, hex"ab", hex"");
    }

    function test_ZRedeem_BlocksDoubleSpend() public {
        // Configure Z-Chain and pre-mint balance to the zChain mock (so V4 can burn from it)
        vm.prank(admin);
        bridge.setZChainBridge(address(zChain));
        bytes memory env = _envelope(1, address(usdt), 5e6, address(zChain));
        vm.prank(user);
        bridge.claim(env, hex"");
        // V4 must be approved by zChain to burn (the mock zChain doesn't approve — so we
        // grant LRC20B admin to V4 and use admin-burn rather than allowance-burn).
        // Bridge already holds admin on usdt; burn(address account, amount) takes onlyAdmin
        // gate plus allowance check. Bypass allowance check by burning from address(this) is
        // impossible here. Solution: have zChain pre-approve V4.
        vm.prank(address(zChain));
        usdt.approve(address(bridge), 5e6);

        bytes32 n1 = keccak256("nullifier-1");
        vm.prank(user);
        bridge.zRedeem(n1, address(usdt), 1e6, 1, hex"deadbeef", hex"");
        assertTrue(bridge.usedNullifiers(n1));

        // second attempt with same nullifier reverts
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_NullifierAlreadyUsed.selector);
        bridge.zRedeem(n1, address(usdt), 1e6, 1, hex"deadbeef", hex"");
    }

    function test_ZRedeem_FailsIfZChainRejectsProof() public {
        vm.prank(admin);
        bridge.setZChainBridge(address(zChain));
        zChain.setRejectSpend(true);

        vm.prank(user);
        vm.expectRevert(bytes("MockZ: bad proof"));
        bridge.zRedeem(bytes32(uint256(1)), address(usdt), 1e6, 1, hex"ab", hex"");
    }

    function test_SetZChainBridge_Toggles() public {
        vm.prank(admin);
        bridge.setZChainBridge(address(zChain));
        assertEq(bridge.zChainBridge(), address(zChain));

        vm.prank(admin);
        bridge.setZChainBridge(address(0));
        assertEq(bridge.zChainBridge(), address(0));

        // After unset, both hooks revert again
        bytes memory env = _envelope(1, address(usdt), 1e6, address(0xABCD));
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZChainNotConfigured.selector);
        bridge.zClaim(env, hex"", bytes32(uint256(1)));
    }
}
