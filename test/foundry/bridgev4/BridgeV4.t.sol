// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { BridgeV4 } from "../../../contracts/bridge/v4/BridgeV4.sol";
import { BasketRegistry } from "../../../contracts/bridge/v4/BasketRegistry.sol";
import { BridgedUSDT } from "../../../contracts/bridge/collateral/USDT.sol";
import { BridgedDAI } from "../../../contracts/bridge/collateral/DAI.sol";
import { MockP3QPrecompile, MockZChainBridge } from "./Mocks.sol";

contract BridgeV4Test is Test {
    BridgeV4 internal bridge;
    BasketRegistry internal registry;
    BridgedUSDT internal usdt;
    BridgedDAI internal dai;
    MockP3QPrecompile internal precompile;
    MockZChainBridge internal zChain;

    address internal admin = makeAddr("admin");
    address internal mpc = makeAddr("mpc");
    address internal operator = makeAddr("operator");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal recipient = makeAddr("recipient");
    address internal user = makeAddr("user");

    function setUp() public {
        vm.startPrank(admin);

        registry = new BasketRegistry(admin);
        bridge = new BridgeV4(admin, address(registry), feeReceiver);

        // Mocks
        precompile = new MockP3QPrecompile();
        zChain = new MockZChainBridge();

        // Grant roles
        bridge.grantRole(bridge.MPC_ROLE(), mpc);
        bridge.grantRole(bridge.OPERATOR_ROLE(), operator);
        bridge.setPrecompileOverride(address(precompile));

        // Bridged tokens
        usdt = new BridgedUSDT();
        dai = new BridgedDAI();

        // Grant admin+minter to V4 so it can mint into recipient wallets
        usdt.grantAdmin(address(bridge));
        usdt.grantMinter(address(bridge));
        dai.grantAdmin(address(bridge));
        dai.grantMinter(address(bridge));

        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, address(usdt), 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, address(dai), 0);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  CLAIM (P3Q valid path)
    // ─────────────────────────────────────────────────────────────────────

    function _envelope(uint64 nonce, address asset, uint256 amount, address recip)
        internal
        view
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

    function test_ClaimWithValidP3Q_Mints() public {
        bytes memory env = _envelope(1, address(usdt), 1_000_000, recipient); // 1 USDT (6 dec)
        bytes32 expectedClaimId = keccak256(env);

        vm.expectEmit(true, true, true, true);
        emit BridgeV4.Claimed(expectedClaimId, 1, recipient, address(usdt), 990_000, 10_000); // 1% fee

        vm.prank(user);
        bytes32 cid = bridge.claim(env, hex"");
        assertEq(cid, expectedClaimId);

        assertEq(usdt.balanceOf(recipient), 990_000);
        assertEq(usdt.balanceOf(feeReceiver), 10_000);
        assertTrue(bridge.usedClaims(cid));
    }

    function test_ClaimReplayRejected() public {
        bytes memory env = _envelope(1, address(usdt), 1e6, recipient);
        vm.prank(user);
        bridge.claim(env, hex"");

        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ClaimAlreadyUsed.selector);
        bridge.claim(env, hex"");
    }

    function test_ClaimZeroAmount_Reverts() public {
        bytes memory env = _envelope(1, address(usdt), 0, recipient);
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZeroAmount.selector);
        bridge.claim(env, hex"");
    }

    function test_ClaimZeroRecipient_Reverts() public {
        bytes memory env = _envelope(1, address(usdt), 1e6, address(0));
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZeroAddress.selector);
        bridge.claim(env, hex"");
    }

    function test_P3QInvalid_RejectsClaim() public {
        precompile.setValid(false);
        bytes memory env = _envelope(1, address(usdt), 1e6, recipient);
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_EnvelopeInvalid.selector);
        bridge.claim(env, hex"");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  CLAIM (classical-compat path)
    // ─────────────────────────────────────────────────────────────────────

    function _classicalEnvelope(uint64 nonce, address asset, uint256 amount, address recip)
        internal
        view
        returns (bytes memory)
    {
        BridgeV4.BridgeEnvelope memory e = BridgeV4.BridgeEnvelope({
            srcChain: 1,
            srcTx: bytes32(uint256(nonce)),
            dstAsset: asset,
            amount: amount,
            recipient: recip,
            nonce: nonce,
            classical: true
        });
        return abi.encode(e);
    }

    function test_ClassicalDisabledByDefault() public {
        bytes memory env = _classicalEnvelope(1, address(usdt), 1e6, recipient);
        vm.prank(mpc); // even MPC can't replay without window enabled
        vm.expectRevert(BridgeV4.V4_ClassicalDisabled.selector);
        bridge.claim(env, hex"");
    }

    function test_EnableClassicalCompat_Allows_OnlyForMPCRole() public {
        vm.prank(admin);
        bridge.enableClassicalCompat(1 days);

        // user without MPC_ROLE still rejected
        bytes memory env1 = _classicalEnvelope(1, address(usdt), 1e6, recipient);
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ClassicalDisabled.selector);
        bridge.claim(env1, hex"");

        // mpc allowed inside window
        bytes memory env2 = _classicalEnvelope(2, address(usdt), 1e6, recipient);
        vm.prank(mpc);
        bridge.claim(env2, hex"");
        assertEq(usdt.balanceOf(recipient), 990_000);
    }

    function test_ClassicalCompatExpires() public {
        vm.prank(admin);
        bridge.enableClassicalCompat(1 hours);

        vm.warp(block.timestamp + 1 hours + 1);

        bytes memory env = _classicalEnvelope(1, address(usdt), 1e6, recipient);
        vm.prank(mpc);
        vm.expectRevert(BridgeV4.V4_ClassicalDisabled.selector);
        bridge.claim(env, hex"");
    }

    function test_ClassicalCompatWindowTooLong_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(BridgeV4.V4_WindowTooLong.selector);
        bridge.enableClassicalCompat(31 days);
    }

    function test_DisableClassicalCompat() public {
        vm.prank(admin);
        bridge.enableClassicalCompat(1 days);

        vm.prank(admin);
        bridge.disableClassicalCompat();

        bytes memory env = _classicalEnvelope(1, address(usdt), 1e6, recipient);
        vm.prank(mpc);
        vm.expectRevert(BridgeV4.V4_ClassicalDisabled.selector);
        bridge.claim(env, hex"");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  REDEEM
    // ─────────────────────────────────────────────────────────────────────

    function test_RedeemBurnsAndEmits() public {
        // first mint to user
        bytes memory env = _envelope(1, address(usdt), 5e6, user);
        vm.prank(user);
        bridge.claim(env, hex"");
        assertEq(usdt.balanceOf(user), 4_950_000);

        // approve burn
        vm.prank(user);
        usdt.approve(address(bridge), 1e6);

        bytes memory dstAddr = hex"deadbeef";
        vm.prank(user);
        bytes32 redeemHash = bridge.redeem(address(usdt), 1e6, 1, dstAddr);

        assertEq(usdt.balanceOf(user), 3_950_000);
        assertEq(bridge.redeemNonce(user), 1);

        // nonce ++
        vm.prank(user);
        usdt.approve(address(bridge), 1e6);
        vm.prank(user);
        bytes32 h2 = bridge.redeem(address(usdt), 1e6, 1, dstAddr);
        assertEq(bridge.redeemNonce(user), 2);
        assertTrue(redeemHash != h2);
    }

    function test_RedeemZeroAmount_Reverts() public {
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZeroAmount.selector);
        bridge.redeem(address(usdt), 0, 1, hex"ab");
    }

    function test_RedeemEmptyDstAddr_Reverts() public {
        vm.prank(user);
        vm.expectRevert(BridgeV4.V4_ZeroAddress.selector);
        bridge.redeem(address(usdt), 1e6, 1, hex"");
    }

    // ─────────────────────────────────────────────────────────────────────
    //  FEES
    // ─────────────────────────────────────────────────────────────────────

    function test_SetFeeBps_Caps() public {
        vm.prank(admin);
        vm.expectRevert(BridgeV4.V4_FeeAboveMax.selector);
        bridge.setFeeBps(501); // > MAX_FEE_BPS = 500

        vm.prank(admin);
        bridge.setFeeBps(500); // exactly at cap is fine
        assertEq(bridge.feeBps(), 500);
    }

    function test_NonGovernance_CannotChangeFee() public {
        vm.prank(user);
        vm.expectRevert();
        bridge.setFeeBps(50);
    }

    function test_FeeReceiver_Replaceable() public {
        address newRcv = makeAddr("newRcv");
        vm.prank(admin);
        bridge.setFeeReceiver(newRcv);
        assertEq(bridge.feeReceiver(), newRcv);

        // subsequent fees route there
        bytes memory env = _envelope(1, address(usdt), 1e6, recipient);
        vm.prank(user);
        bridge.claim(env, hex"");
        assertEq(usdt.balanceOf(newRcv), 10_000);
    }

    function test_DrainFees_OperatorOnly() public {
        // accumulate fees
        bytes memory env = _envelope(1, address(usdt), 1e8, recipient); // 100 USDT
        vm.prank(user);
        bridge.claim(env, hex"");
        assertEq(usdt.balanceOf(feeReceiver), 1e6); // 1%

        // feeReceiver must approve V4 first
        vm.prank(feeReceiver);
        usdt.approve(address(bridge), 1e6);

        address treasury = makeAddr("treasury");

        // non-operator can't drain
        vm.prank(user);
        vm.expectRevert();
        bridge.drainFees(address(usdt), 1e6, treasury);

        // operator can
        vm.prank(operator);
        bridge.drainFees(address(usdt), 1e6, treasury);
        assertEq(usdt.balanceOf(treasury), 1e6);
        assertEq(usdt.balanceOf(feeReceiver), 0);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  PAUSE
    // ─────────────────────────────────────────────────────────────────────

    function test_PauseBlocksClaim() public {
        vm.prank(admin);
        bridge.pause();

        bytes memory env = _envelope(1, address(usdt), 1e6, recipient);
        vm.prank(user);
        vm.expectRevert();
        bridge.claim(env, hex"");
    }

    function test_PauseBlocksRedeem() public {
        bytes memory env = _envelope(1, address(usdt), 1e6, user);
        vm.prank(user);
        bridge.claim(env, hex"");
        vm.prank(user);
        usdt.approve(address(bridge), 1e6);

        vm.prank(admin);
        bridge.pause();

        vm.prank(user);
        vm.expectRevert();
        bridge.redeem(address(usdt), 1e5, 1, hex"ab");
    }
}
