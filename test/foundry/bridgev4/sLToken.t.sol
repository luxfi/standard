// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { sLUSD } from "../../../contracts/staking/sLUSD.sol";
import { sLToken } from "../../../contracts/staking/sLToken.sol";
import { LiquidUSD } from "../../../contracts/liquid/tokens/LUSD.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockYieldStrategy } from "./Mocks.sol";

contract sLTokenTest is Test {
    sLUSD internal vault;
    LiquidUSD internal lusd;
    MockYieldStrategy internal strat;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.startPrank(admin);
        lusd = new LiquidUSD();
        vault = new sLUSD(IERC20(address(lusd)), admin);
        // strategy can be set later — give admin minter role on lusd so we can fund alice
        vm.stopPrank();

        // Mint LUSD to alice for staking — admin has DEFAULT_ADMIN_ROLE on lusd
        vm.prank(admin);
        lusd.grantMinter(admin);
        vm.prank(admin);
        lusd.mint(alice, 1_000e18);
        vm.prank(admin);
        lusd.mint(bob, 500e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  STAKE / SHARES
    // ─────────────────────────────────────────────────────────────────────

    function test_DepositMintsShares_1To1_Initially() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        uint256 shares = vault.deposit(100e18, alice);
        vm.stopPrank();
        assertEq(shares, 100e18); // first depositor: 1:1
        assertEq(vault.balanceOf(alice), 100e18);
        assertEq(vault.totalAssets(), 100e18);
    }

    function test_TwoUsers_Share() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        lusd.approve(address(vault), 50e18);
        uint256 bobShares = vault.deposit(50e18, bob);
        vm.stopPrank();

        // Bob also gets 1:1 since no yield has accrued
        assertEq(bobShares, 50e18);
        assertEq(vault.balanceOf(bob), 50e18);
        assertEq(vault.totalAssets(), 150e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  YIELD HARVEST INCREASES SHARE VALUE
    // ─────────────────────────────────────────────────────────────────────

    function test_HarvestIncreasesShareValue() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        // Attach strategy and pre-fund it with 10 LUSD as "yield"
        vm.startPrank(admin);
        strat = new MockYieldStrategy(address(lusd), address(vault));
        vault.setStrategy(strat);
        lusd.mint(address(strat), 10e18);
        strat.setYieldPerHarvest(10e18);
        vault.harvest();
        vm.stopPrank();

        // Alice has 100 shares; vault now has 100 + 10 = 110 LUSD.
        // previewRedeem(100 shares) should give 110 LUSD
        uint256 prev = vault.previewRedeem(100e18);
        // ERC4626 has a small offset; result should be very close to 110e18 (allowing for
        // the OZ v5 virtual-asset rounding of 1 wei).
        assertGe(prev, 109_999_999_999_999_999_990);
        assertLe(prev, 110e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  COOLDOWN UNSTAKE
    // ─────────────────────────────────────────────────────────────────────

    function test_RequestUnstake_StartsCooldown() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vault.requestUnstake(40e18);
        vm.stopPrank();

        (uint256 shares, uint256 cd) = vault.cooldownOf(alice);
        assertEq(shares, 40e18);
        assertEq(cd, block.timestamp + 7 days);
        assertEq(vault.balanceOf(alice), 60e18); // 40 in escrow
        assertEq(vault.balanceOf(address(vault)), 40e18);
    }

    function test_ClaimUnstake_RevertsBeforeCooldown() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vault.requestUnstake(40e18);
        vm.expectRevert(sLToken.sLToken_CooldownNotMet.selector);
        vault.claimUnstake();
        vm.stopPrank();
    }

    function test_ClaimUnstake_AfterCooldown_PaysOut() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vault.requestUnstake(40e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(alice);
        uint256 assets = vault.claimUnstake();
        assertEq(assets, 40e18);
        assertEq(lusd.balanceOf(alice), 900e18 + 40e18); // 900 unstaked (originally had 1000) + 40 just claimed
        assertEq(vault.balanceOf(alice), 60e18);
    }

    function test_ClaimUnstake_NoCooldown_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(sLToken.sLToken_NoCooldown.selector);
        vault.claimUnstake();
    }

    function test_CancelUnstake_ReturnsShares() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vault.requestUnstake(40e18);
        vault.cancelUnstake();
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 100e18);
        (uint256 shares,) = vault.cooldownOf(alice);
        assertEq(shares, 0);
    }

    function test_SecondRequest_ExtendsCooldown() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vault.requestUnstake(40e18);
        vm.warp(block.timestamp + 1 days);
        vault.requestUnstake(20e18);
        vm.stopPrank();
        (uint256 shares, uint256 cd) = vault.cooldownOf(alice);
        assertEq(shares, 60e18);
        // cooldown end is reset relative to second request
        assertEq(cd, block.timestamp + 7 days);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  PAUSE — exits always work, new stakes blocked
    // ─────────────────────────────────────────────────────────────────────

    function test_Pause_BlocksDeposit_NotExit() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vault.requestUnstake(40e18);
        vm.stopPrank();

        vm.prank(admin);
        vault.pause();

        // New deposits blocked
        vm.startPrank(bob);
        lusd.approve(address(vault), 50e18);
        vm.expectRevert();
        vault.deposit(50e18, bob);
        vm.stopPrank();

        // Existing claim still works after cooldown
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(alice);
        uint256 assets = vault.claimUnstake();
        assertEq(assets, 40e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  STRATEGY SWAP
    // ─────────────────────────────────────────────────────────────────────

    function test_SetStrategy_MismatchReverts() public {
        // strategy says it's for a different L token
        MockYieldStrategy bad = new MockYieldStrategy(address(0xBEEF), address(vault));
        vm.prank(admin);
        vm.expectRevert(sLToken.sLToken_StrategyMismatch.selector);
        vault.setStrategy(bad);
    }

    function test_DetachStrategy_DrainsBalance() public {
        vm.startPrank(alice);
        lusd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        vm.startPrank(admin);
        strat = new MockYieldStrategy(address(lusd), address(vault));
        vault.setStrategy(strat);
        vm.stopPrank();

        // Deploy 30 LUSD into the strategy
        vm.prank(address(vault));
        lusd.approve(address(strat), 30e18);
        vm.prank(admin);
        strat.deployFromVault(30e18);

        assertEq(lusd.balanceOf(address(vault)), 70e18);
        assertEq(strat.externalBalance(), 30e18);

        // Detach — should pull 30 back
        vm.prank(admin);
        uint256 drained = vault.detachStrategy();
        assertEq(drained, 30e18);
        assertEq(lusd.balanceOf(address(vault)), 100e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  COOLDOWN PERIOD SETTER
    // ─────────────────────────────────────────────────────────────────────

    function test_SetCooldownPeriod_Caps() public {
        vm.prank(admin);
        vm.expectRevert(sLToken.sLToken_CooldownTooLong.selector);
        vault.setCooldownPeriod(31 days);

        vm.prank(admin);
        vault.setCooldownPeriod(3 days);
        assertEq(vault.cooldownPeriod(), 3 days);
    }
}
