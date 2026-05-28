// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { BasketRegistry } from "../../../contracts/bridge/v4/BasketRegistry.sol";
import { LiquidUSDPool } from "../../../contracts/liquid/pools/LiquidUSDPool.sol";
import { LiquidBTCPool } from "../../../contracts/liquid/pools/LiquidBTCPool.sol";
import { LiquidETHPool } from "../../../contracts/liquid/pools/LiquidETHPool.sol";
import { LiquidSOLPool } from "../../../contracts/liquid/pools/LiquidSOLPool.sol";
import { LiquidTONPool } from "../../../contracts/liquid/pools/LiquidTONPool.sol";
import { LiquidXRPPool } from "../../../contracts/liquid/pools/LiquidXRPPool.sol";
import { LiquidDOTPool } from "../../../contracts/liquid/pools/LiquidDOTPool.sol";
import { LiquidUSD } from "../../../contracts/liquid/tokens/LUSD.sol";
import { LiquidBTC } from "../../../contracts/liquid/tokens/LBTC.sol";
import { LiquidETH } from "../../../contracts/liquid/tokens/LETH.sol";
import { LiquidSOL } from "../../../contracts/liquid/tokens/LSOL.sol";
import { LiquidTON } from "../../../contracts/liquid/tokens/LTON.sol";
import { LiquidXRP } from "../../../contracts/liquid/tokens/LXRP.sol";
import { LiquidDOT } from "../../../contracts/liquid/tokens/LDOT.sol";
import { BridgedUSDT } from "../../../contracts/bridge/collateral/USDT.sol";
import { BridgedUSDC } from "../../../contracts/bridge/collateral/USDC.sol";
import { BridgedDAI } from "../../../contracts/bridge/collateral/DAI.sol";
import { BridgedFRAX } from "../../../contracts/bridge/collateral/FRAX.sol";
import { BridgedPYUSD } from "../../../contracts/bridge/collateral/PYUSD.sol";
import { BridgedRLUSD } from "../../../contracts/bridge/collateral/RLUSD.sol";
import { BridgedTUSD } from "../../../contracts/bridge/collateral/TUSD.sol";
import { BridgedBTC } from "../../../contracts/bridge/collateral/BTC.sol";
import { BridgedBTCB } from "../../../contracts/bridge/collateral/BTCB.sol";
import { BridgedtBTC } from "../../../contracts/bridge/collateral/tBTC.sol";
import { BridgedcbBTC } from "../../../contracts/bridge/collateral/cbBTC.sol";
import { BridgedNativeBTC } from "../../../contracts/bridge/collateral/NativeBTC.sol";
import { BridgedETH } from "../../../contracts/bridge/collateral/ETH.sol";
import { BridgedNativeETH } from "../../../contracts/bridge/collateral/NativeETH.sol";
import { BridgedstETH } from "../../../contracts/bridge/collateral/stETH.sol";
import { BridgedrETH } from "../../../contracts/bridge/collateral/rETH.sol";
import { BridgedNativeSOL } from "../../../contracts/bridge/collateral/NativeSOL.sol";
import { BridgedNativeTON } from "../../../contracts/bridge/collateral/NativeTON.sol";
import { BridgedNativeXRP } from "../../../contracts/bridge/collateral/NativeXRP.sol";
import { BridgedNativeDOT } from "../../../contracts/bridge/collateral/NativeDOT.sol";
import { LiquidPool } from "../../../contracts/liquid/pools/LiquidPool.sol";
import { PerAssetLedger } from "../../../contracts/bridge/v4/PerAssetLedger.sol";

contract LiquidPoolsTest is Test {
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal mpc = makeAddr("mpc");

    BasketRegistry internal registry;

    // USD universe
    LiquidUSDPool internal lusdPool;
    LiquidUSD internal lusd;
    BridgedUSDT internal usdt;
    BridgedDAI internal dai;

    // BTC universe
    LiquidBTCPool internal lbtcPool;
    LiquidBTC internal lbtc;
    BridgedNativeBTC internal nbtc;
    BridgedBTCB internal btcb;

    // ETH universe
    LiquidETHPool internal lethPool;
    LiquidETH internal leth;
    BridgedETH internal eth;
    BridgedstETH internal steth;

    // SOL/TON/XRP/DOT
    LiquidSOLPool internal lsolPool;
    LiquidSOL internal lsol;
    BridgedNativeSOL internal nsol;

    LiquidTONPool internal ltonPool;
    LiquidTON internal lton;
    BridgedNativeTON internal nton;

    LiquidXRPPool internal lxrpPool;
    LiquidXRP internal lxrp;
    BridgedNativeXRP internal nxrp;

    LiquidDOTPool internal ldotPool;
    LiquidDOT internal ldot;
    BridgedNativeDOT internal ndot;

    function setUp() public {
        vm.startPrank(admin);

        registry = new BasketRegistry(admin);

        // ─── USD ───
        lusd = new LiquidUSD();
        lusdPool = new LiquidUSDPool(admin, address(lusd), address(registry));
        // pool needs admin role on lusd to mint/burn (existing LiquidUSD uses onlyAdmin gating both)
        lusd.grantAdmin(address(lusdPool));
        lusd.grantMinter(address(lusdPool));

        usdt = new BridgedUSDT();
        dai = new BridgedDAI();
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, address(usdt), 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, address(dai), 0);
        // grant mint permission so MPC can fund test users
        usdt.grantAdmin(mpc);
        usdt.grantMinter(mpc);
        dai.grantAdmin(mpc);
        dai.grantMinter(mpc);

        // ─── BTC ───
        lbtc = new LiquidBTC();
        lbtcPool = new LiquidBTCPool(admin, address(lbtc), address(registry));
        lbtc.grantAdmin(address(lbtcPool));
        lbtc.grantMinter(address(lbtcPool));
        nbtc = new BridgedNativeBTC();
        btcb = new BridgedBTCB();
        registry.addAssetToBasket(BasketRegistry.BasketClass.BTC, address(nbtc), 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.BTC, address(btcb), 0);
        nbtc.grantAdmin(mpc);
        nbtc.grantMinter(mpc);
        btcb.grantAdmin(mpc);
        btcb.grantMinter(mpc);

        // ─── ETH ───
        leth = new LiquidETH();
        lethPool = new LiquidETHPool(admin, address(leth), address(registry));
        leth.grantAdmin(address(lethPool));
        leth.grantMinter(address(lethPool));
        eth = new BridgedETH();
        steth = new BridgedstETH();
        registry.addAssetToBasket(BasketRegistry.BasketClass.ETH, address(eth), 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.ETH, address(steth), 0);
        eth.grantAdmin(mpc);
        eth.grantMinter(mpc);
        steth.grantAdmin(mpc);
        steth.grantMinter(mpc);

        // ─── SOL / TON / XRP / DOT ───
        lsol = new LiquidSOL();
        lsolPool = new LiquidSOLPool(admin, address(lsol), address(registry));
        lsol.grantAdmin(address(lsolPool));
        lsol.grantMinter(address(lsolPool));
        nsol = new BridgedNativeSOL();
        registry.addAssetToBasket(BasketRegistry.BasketClass.SOL, address(nsol), 0);
        nsol.grantAdmin(mpc);
        nsol.grantMinter(mpc);

        lton = new LiquidTON();
        ltonPool = new LiquidTONPool(admin, address(lton), address(registry));
        lton.grantAdmin(address(ltonPool));
        lton.grantMinter(address(ltonPool));
        nton = new BridgedNativeTON();
        registry.addAssetToBasket(BasketRegistry.BasketClass.TON, address(nton), 0);
        nton.grantAdmin(mpc);
        nton.grantMinter(mpc);

        lxrp = new LiquidXRP();
        lxrpPool = new LiquidXRPPool(admin, address(lxrp), address(registry));
        lxrp.grantAdmin(address(lxrpPool));
        lxrp.grantMinter(address(lxrpPool));
        nxrp = new BridgedNativeXRP();
        registry.addAssetToBasket(BasketRegistry.BasketClass.XRP, address(nxrp), 0);
        nxrp.grantAdmin(mpc);
        nxrp.grantMinter(mpc);

        ldot = new LiquidDOT();
        ldotPool = new LiquidDOTPool(admin, address(ldot), address(registry));
        ldot.grantAdmin(address(ldotPool));
        ldot.grantMinter(address(ldotPool));
        ndot = new BridgedNativeDOT();
        registry.addAssetToBasket(BasketRegistry.BasketClass.DOT, address(ndot), 0);
        ndot.grantAdmin(mpc);
        ndot.grantMinter(mpc);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  USD pool — decimal normalization (6 USDT → 18 LUSD)
    // ─────────────────────────────────────────────────────────────────────

    function test_LUSD_DepositUSDT_NormalizesTo18() public {
        // Fund alice with 1000 USDT (6 dec)
        vm.prank(mpc);
        usdt.bridgeMint(alice, 1000e6);

        vm.startPrank(alice);
        usdt.approve(address(lusdPool), 1000e6);
        uint256 minted = lusdPool.deposit(address(usdt), 1000e6);
        vm.stopPrank();

        assertEq(minted, 1000e18);
        assertEq(lusd.balanceOf(alice), 1000e18);
        assertEq(lusdPool.assetReserve(address(usdt)), 1000e6);
        assertEq(lusdPool.totalReserveInBaseUnits(), 1000e18);
    }

    function test_LUSD_DepositDAI_18To18_NoScaling() public {
        vm.prank(mpc);
        dai.bridgeMint(alice, 500e18);

        vm.startPrank(alice);
        dai.approve(address(lusdPool), 500e18);
        uint256 minted = lusdPool.deposit(address(dai), 500e18);
        vm.stopPrank();

        assertEq(minted, 500e18);
        assertEq(lusd.balanceOf(alice), 500e18);
    }

    function test_LUSD_BurnFor_PreferredAsset() public {
        // Alice deposits 100 USDT + 100 DAI
        vm.prank(mpc);
        usdt.bridgeMint(alice, 100e6);
        vm.prank(mpc);
        dai.bridgeMint(alice, 100e18);

        vm.startPrank(alice);
        usdt.approve(address(lusdPool), 100e6);
        lusdPool.deposit(address(usdt), 100e6);
        dai.approve(address(lusdPool), 100e18);
        lusdPool.deposit(address(dai), 100e18);

        // Now alice has 200 LUSD, the pool has 100 USDT + 100 DAI reserves
        assertEq(lusd.balanceOf(alice), 200e18);

        // Burn 50 LUSD for DAI
        lusd.approve(address(lusdPool), 50e18);
        uint256 raw = lusdPool.burnFor(50e18, address(dai));
        vm.stopPrank();

        assertEq(raw, 50e18);
        assertEq(dai.balanceOf(alice), 50e18);
        assertEq(lusdPool.assetReserve(address(dai)), 50e18);
        assertEq(lusdPool.assetReserve(address(usdt)), 100e6); // unchanged
    }

    function test_LUSD_BurnFor_PreferredAsset_6Decimal() public {
        // alice deposits 100 DAI, then burns LUSD for USDT (impossible — USDT reserve is 0)
        vm.prank(mpc);
        dai.bridgeMint(alice, 100e18);
        vm.startPrank(alice);
        dai.approve(address(lusdPool), 100e18);
        lusdPool.deposit(address(dai), 100e18);

        // burn for USDT should revert (no reserve)
        lusd.approve(address(lusdPool), 50e18);
        vm.expectRevert(PerAssetLedger.PerAssetLedger_InsufficientReserve.selector);
        lusdPool.burnFor(50e18, address(usdt));
        vm.stopPrank();
    }

    function test_LUSD_BurnFor_USDT_DecimalDown() public {
        vm.prank(mpc);
        usdt.bridgeMint(alice, 100e6);
        vm.startPrank(alice);
        usdt.approve(address(lusdPool), 100e6);
        lusdPool.deposit(address(usdt), 100e6);
        // alice now has 100e18 LUSD; basket has 100e6 USDT reserve

        lusd.approve(address(lusdPool), 30e18);
        uint256 raw = lusdPool.burnFor(30e18, address(usdt));
        vm.stopPrank();
        assertEq(raw, 30e6); // 30 LUSD → 30 USDT raw
        assertEq(usdt.balanceOf(alice), 30e6);
    }

    function test_LUSD_NonBasketAsset_Reverts() public {
        // Deploy and seed FRAX as the test contract (owner of grantAdmin),
        // then grant mpc admin+minter so we can mint to alice.
        BridgedFRAX frax = new BridgedFRAX();
        frax.grantAdmin(mpc);
        vm.prank(mpc);
        frax.grantMinter(mpc);
        vm.prank(mpc);
        frax.bridgeMint(alice, 100e18);

        // FRAX is NOT registered in the USD basket here, so deposit should revert.
        vm.startPrank(alice);
        frax.approve(address(lusdPool), 100e18);
        vm.expectRevert(LiquidPool.LiquidPool_NotInBasket.selector);
        lusdPool.deposit(address(frax), 100e18);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────
    //  BTC pool — 8-dec → 18-dec scaling
    // ─────────────────────────────────────────────────────────────────────

    function test_LBTC_DepositNativeBTC_8To18() public {
        // 1 BTC raw = 1e8 (sats)
        vm.prank(mpc);
        nbtc.bridgeMint(alice, 1e8);

        vm.startPrank(alice);
        nbtc.approve(address(lbtcPool), 1e8);
        uint256 minted = lbtcPool.deposit(address(nbtc), 1e8);
        vm.stopPrank();

        assertEq(minted, 1e18); // 1 LBTC
        assertEq(lbtc.balanceOf(alice), 1e18);
    }

    function test_LBTC_DepositBTCB_18To18() public {
        vm.prank(mpc);
        btcb.bridgeMint(alice, 2e18);

        vm.startPrank(alice);
        btcb.approve(address(lbtcPool), 2e18);
        uint256 minted = lbtcPool.deposit(address(btcb), 2e18);
        vm.stopPrank();

        assertEq(minted, 2e18);
        assertEq(lbtc.balanceOf(alice), 2e18);
    }

    function test_LBTC_BurnFor_NativeBTC_18To8() public {
        vm.prank(mpc);
        nbtc.bridgeMint(alice, 5e8);
        vm.startPrank(alice);
        nbtc.approve(address(lbtcPool), 5e8);
        lbtcPool.deposit(address(nbtc), 5e8);
        // alice has 5e18 LBTC
        lbtc.approve(address(lbtcPool), 2e18);
        uint256 raw = lbtcPool.burnFor(2e18, address(nbtc));
        vm.stopPrank();
        assertEq(raw, 2e8);
        assertEq(nbtc.balanceOf(alice), 2e8);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  ETH pool — 1:1 (both 18 dec)
    // ─────────────────────────────────────────────────────────────────────

    function test_LETH_DepositETH_18To18() public {
        vm.prank(mpc);
        eth.bridgeMint(alice, 10e18);
        vm.startPrank(alice);
        eth.approve(address(lethPool), 10e18);
        uint256 minted = lethPool.deposit(address(eth), 10e18);
        vm.stopPrank();
        assertEq(minted, 10e18);
        assertEq(leth.balanceOf(alice), 10e18);
    }

    function test_LETH_DepositStETH_Then_BurnFor_StETH() public {
        vm.prank(mpc);
        steth.bridgeMint(alice, 3e18);
        vm.startPrank(alice);
        steth.approve(address(lethPool), 3e18);
        lethPool.deposit(address(steth), 3e18);
        leth.approve(address(lethPool), 1e18);
        uint256 raw = lethPool.burnFor(1e18, address(steth));
        vm.stopPrank();
        assertEq(raw, 1e18);
        assertEq(steth.balanceOf(alice), 1e18);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SOL pool — 9 → 18
    // ─────────────────────────────────────────────────────────────────────

    function test_LSOL_DepositNativeSOL_9To18() public {
        vm.prank(mpc);
        nsol.bridgeMint(alice, 5e9); // 5 SOL
        vm.startPrank(alice);
        nsol.approve(address(lsolPool), 5e9);
        uint256 minted = lsolPool.deposit(address(nsol), 5e9);
        vm.stopPrank();
        assertEq(minted, 5e18);
        assertEq(lsol.balanceOf(alice), 5e18);
    }

    function test_LSOL_RoundTrip() public {
        vm.prank(mpc);
        nsol.bridgeMint(alice, 10e9);
        vm.startPrank(alice);
        nsol.approve(address(lsolPool), 10e9);
        lsolPool.deposit(address(nsol), 10e9);
        lsol.approve(address(lsolPool), 10e18);
        uint256 raw = lsolPool.burnFor(10e18, address(nsol));
        vm.stopPrank();
        assertEq(raw, 10e9);
        assertEq(nsol.balanceOf(alice), 10e9);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  TON pool — 9 → 18
    // ─────────────────────────────────────────────────────────────────────

    function test_LTON_RoundTrip() public {
        vm.prank(mpc);
        nton.bridgeMint(alice, 100e9);
        vm.startPrank(alice);
        nton.approve(address(ltonPool), 100e9);
        ltonPool.deposit(address(nton), 100e9);
        assertEq(lton.balanceOf(alice), 100e18);
        lton.approve(address(ltonPool), 100e18);
        ltonPool.burnFor(100e18, address(nton));
        vm.stopPrank();
        assertEq(nton.balanceOf(alice), 100e9);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  XRP pool — 6 → 6 (parity, no scaling)
    // ─────────────────────────────────────────────────────────────────────

    function test_LXRP_NoDecimalScaling() public {
        vm.prank(mpc);
        nxrp.bridgeMint(alice, 50e6);
        vm.startPrank(alice);
        nxrp.approve(address(lxrpPool), 50e6);
        uint256 minted = lxrpPool.deposit(address(nxrp), 50e6);
        vm.stopPrank();
        assertEq(minted, 50e6); // no scaling — pool dec == asset dec
        assertEq(lxrp.balanceOf(alice), 50e6);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DOT pool — 10 → 10
    // ─────────────────────────────────────────────────────────────────────

    function test_LDOT_NoDecimalScaling() public {
        vm.prank(mpc);
        ndot.bridgeMint(alice, 5e10);
        vm.startPrank(alice);
        ndot.approve(address(ldotPool), 5e10);
        uint256 minted = ldotPool.deposit(address(ndot), 5e10);
        vm.stopPrank();
        assertEq(minted, 5e10);
        assertEq(ldot.balanceOf(alice), 5e10);
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Common: zero amount, pause
    // ─────────────────────────────────────────────────────────────────────

    function test_DepositZero_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(LiquidPool.LiquidPool_ZeroAmount.selector);
        lusdPool.deposit(address(usdt), 0);
    }

    function test_BurnForZero_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(LiquidPool.LiquidPool_ZeroAmount.selector);
        lusdPool.burnFor(0, address(usdt));
    }

    function test_Pause_BlocksDeposit() public {
        vm.prank(mpc);
        usdt.bridgeMint(alice, 100e6);
        vm.prank(admin);
        lusdPool.pause();

        vm.startPrank(alice);
        usdt.approve(address(lusdPool), 100e6);
        vm.expectRevert();
        lusdPool.deposit(address(usdt), 100e6);
        vm.stopPrank();
    }

    function testFuzz_USDDepositBurnRoundtrip(uint64 amount) public {
        amount = uint64(bound(amount, 1, 1_000_000_000e6)); // up to 1B USDT
        vm.prank(mpc);
        usdt.bridgeMint(alice, amount);
        vm.startPrank(alice);
        usdt.approve(address(lusdPool), amount);
        uint256 lMinted = lusdPool.deposit(address(usdt), amount);
        // For 6→18 normalization, lMinted = amount * 1e12 exactly
        assertEq(lMinted, uint256(amount) * 1e12);

        lusd.approve(address(lusdPool), lMinted);
        uint256 rawOut = lusdPool.burnFor(lMinted, address(usdt));
        vm.stopPrank();
        assertEq(rawOut, amount);
        assertEq(usdt.balanceOf(alice), amount);
        assertEq(lusdPool.assetReserve(address(usdt)), 0);
    }
}
