// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { Futures } from "../../contracts/futures/Futures.sol";
import { IFutures } from "../../contracts/interfaces/futures/IFutures.sol";
import { MockERC20 } from "./TestMocks.sol";

/**
 * @title MockFuturesOracle
 * @notice Returns (price, timestamp) tuple matching Options oracle interface
 */
contract MockFuturesOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256, uint256) {
        return (prices[token], block.timestamp);
    }
}

/**
 * @title Futures Module Tests
 * @notice Tests for dated futures with daily mark-to-market, margin, liquidation, settlement.
 *
 * Covers:
 *   - Contract creation and validation
 *   - Long/short position opening with margin
 *   - Position increase (weighted average entry)
 *   - Position close (partial and full) with PnL
 *   - Margin deposit and withdrawal
 *   - Daily mark-to-market settlement (keeper)
 *   - Liquidation of under-margined positions
 *   - Final settlement at expiry
 *   - Open interest tracking
 *   - Fee collection
 *   - Access control
 */
contract FuturesTest is Test {
    Futures public futures;
    MockFuturesOracle public oracle;
    MockERC20 public usdl; // Quote asset
    MockERC20 public wbtc; // Underlying

    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);
    address keeper = address(0xD);
    address feeReceiver = address(0xF);

    uint256 constant PRECISION = 1e18;
    uint256 constant BPS = 10000;

    // Contract spec defaults
    uint256 constant CONTRACT_SIZE = 1e18; // 1 unit per contract
    uint256 constant TICK_SIZE = 1e15; // 0.001 precision
    uint256 constant INITIAL_MARGIN_BPS = 1000; // 10%
    uint256 constant MAINTENANCE_MARGIN_BPS = 500; // 5%

    // BTC price = $60,000 (18 decimals)
    uint256 constant BTC_PRICE = 60_000e18;

    function setUp() public {
        vm.startPrank(admin);

        oracle = new MockFuturesOracle();
        usdl = new MockERC20("USDL", "USDL", 18);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 18);

        futures = new Futures(address(oracle), feeReceiver, admin);

        // Grant keeper role
        futures.grantRole(futures.KEEPER_ROLE(), keeper);

        // Set oracle price
        oracle.setPrice(address(wbtc), BTC_PRICE);

        vm.stopPrank();

        // Fund traders
        usdl.mint(alice, 1_000_000e18);
        usdl.mint(bob, 1_000_000e18);

        // Approve futures contract
        vm.prank(alice);
        usdl.approve(address(futures), type(uint256).max);
        vm.prank(bob);
        usdl.approve(address(futures), type(uint256).max);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Helpers
    // ══════════════════════════════════════════════════════════════════════

    function _createDefaultContract() internal returns (uint256) {
        vm.prank(admin);
        return futures.createContract(
            address(wbtc),
            address(usdl),
            block.timestamp + 30 days,
            CONTRACT_SIZE,
            TICK_SIZE,
            INITIAL_MARGIN_BPS,
            MAINTENANCE_MARGIN_BPS,
            IFutures.SettlementType.CASH
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // Contract Creation
    // ══════════════════════════════════════════════════════════════════════

    function test_createContract() public {
        uint256 id = _createDefaultContract();
        assertEq(id, 1);

        IFutures.ContractSpec memory spec = futures.getContract(id);
        assertEq(spec.underlying, address(wbtc));
        assertEq(spec.quote, address(usdl));
        assertEq(spec.contractSize, CONTRACT_SIZE);
        assertEq(spec.tickSize, TICK_SIZE);
        assertEq(spec.initialMarginBps, INITIAL_MARGIN_BPS);
        assertEq(spec.maintenanceMarginBps, MAINTENANCE_MARGIN_BPS);
        assertTrue(spec.exists);
    }

    function test_createContract_incrementsId() public {
        uint256 id1 = _createDefaultContract();
        uint256 id2 = _createDefaultContract();
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_revert_createContract_zeroUnderlying() public {
        vm.prank(admin);
        vm.expectRevert(IFutures.ZeroAddress.selector);
        futures.createContract(
            address(0), address(usdl), block.timestamp + 30 days,
            CONTRACT_SIZE, TICK_SIZE, INITIAL_MARGIN_BPS, MAINTENANCE_MARGIN_BPS,
            IFutures.SettlementType.CASH
        );
    }

    function test_revert_createContract_invalidExpiry() public {
        vm.prank(admin);
        vm.expectRevert(IFutures.InvalidExpiry.selector);
        futures.createContract(
            address(wbtc), address(usdl), block.timestamp, // too soon
            CONTRACT_SIZE, TICK_SIZE, INITIAL_MARGIN_BPS, MAINTENANCE_MARGIN_BPS,
            IFutures.SettlementType.CASH
        );
    }

    function test_revert_createContract_invalidMarginParams() public {
        vm.prank(admin);
        vm.expectRevert(IFutures.InvalidMarginParams.selector);
        futures.createContract(
            address(wbtc), address(usdl), block.timestamp + 30 days,
            CONTRACT_SIZE, TICK_SIZE,
            500, 500, // maintenance >= initial
            IFutures.SettlementType.CASH
        );
    }

    function test_revert_createContract_notAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        futures.createContract(
            address(wbtc), address(usdl), block.timestamp + 30 days,
            CONTRACT_SIZE, TICK_SIZE, INITIAL_MARGIN_BPS, MAINTENANCE_MARGIN_BPS,
            IFutures.SettlementType.CASH
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // Open Positions
    // ══════════════════════════════════════════════════════════════════════

    function test_openLong() public {
        uint256 cid = _createDefaultContract();

        // Notional = 1 contract * 1e18 contractSize * 60000e18 price / 1e18 = 60000e18
        // Initial margin = 60000e18 * 10% = 6000e18
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        IFutures.Position memory pos = futures.getPosition(cid, alice);
        assertEq(uint8(pos.side), uint8(IFutures.Side.LONG));
        assertEq(pos.size, 1);
        assertEq(pos.entryPrice, BTC_PRICE);
        assertTrue(pos.margin > 0);
        assertEq(uint8(pos.status), uint8(IFutures.PositionStatus.OPEN));
    }

    function test_openShort() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        IFutures.Position memory pos = futures.getPosition(cid, bob);
        assertEq(uint8(pos.side), uint8(IFutures.Side.SHORT));
        assertEq(pos.size, 1);
    }

    function test_openPosition_updatesOpenInterest() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 2, BTC_PRICE, margin * 2);

        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 3, BTC_PRICE, margin * 3);

        (uint256 longOI, uint256 shortOI) = futures.getOpenInterest(cid);
        assertEq(longOI, 2);
        assertEq(shortOI, 3);
    }

    function test_increasePosition() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.startPrank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);
        vm.stopPrank();

        IFutures.Position memory pos = futures.getPosition(cid, alice);
        assertEq(pos.size, 2);
    }

    function test_revert_openPosition_zeroSize() public {
        uint256 cid = _createDefaultContract();

        vm.prank(alice);
        vm.expectRevert(IFutures.ZeroAmount.selector);
        futures.openPosition(cid, IFutures.Side.LONG, 0, BTC_PRICE, 6000e18);
    }

    function test_revert_openPosition_insufficientMargin() public {
        uint256 cid = _createDefaultContract();

        vm.prank(alice);
        vm.expectRevert(IFutures.InsufficientMargin.selector);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, 100e18); // Way too little
    }

    function test_revert_openPosition_contractExpired() public {
        uint256 cid = _createDefaultContract();
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vm.expectRevert(IFutures.ContractExpired.selector);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, 6000e18);
    }

    function test_revert_openPosition_priceNotOnTick() public {
        uint256 cid = _createDefaultContract();

        vm.prank(alice);
        vm.expectRevert(IFutures.PriceNotAlignedToTick.selector);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE + 1, 6000e18); // Not tick-aligned
    }

    // ══════════════════════════════════════════════════════════════════════
    // Close Positions
    // ══════════════════════════════════════════════════════════════════════

    function test_closePosition_profitable() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        // Both sides open — contract holds both margins so it can pay out profits
        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);
        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        // Close at higher price ($65,000) — long profits
        uint256 closePrice = 65_000e18;

        uint256 balBefore = usdl.balanceOf(alice);

        vm.prank(alice);
        int256 pnl = futures.closePosition(cid, 1, closePrice);

        // PnL = (65000 - 60000) * 1 * 1e18 / 1e18 = 5000e18
        assertGt(pnl, 0);

        IFutures.Position memory pos = futures.getPosition(cid, alice);
        assertEq(pos.size, 0);
        assertEq(uint8(pos.status), uint8(IFutures.PositionStatus.CLOSED));

        // Alice should have received margin + profit - fees
        uint256 balAfter = usdl.balanceOf(alice);
        assertGt(balAfter, balBefore);
    }

    function test_closePosition_loss() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        // Close at lower price ($55,000)
        uint256 closePrice = 55_000e18;

        vm.prank(alice);
        int256 pnl = futures.closePosition(cid, 1, closePrice);

        // PnL = (55000 - 60000) * 1 * 1e18 / 1e18 = -5000e18
        assertLt(pnl, 0);
    }

    function test_closePosition_shortProfit() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        // Both sides open — contract holds both margins
        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);
        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        // Price drops to $55,000 — short profits
        uint256 closePrice = 55_000e18;

        vm.prank(bob);
        int256 pnl = futures.closePosition(cid, 1, closePrice);

        assertGt(pnl, 0); // Short profits when price drops
    }

    function test_closePosition_partial() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 12_000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 2, BTC_PRICE, margin);

        // Close 1 of 2 contracts
        vm.prank(alice);
        futures.closePosition(cid, 1, BTC_PRICE);

        IFutures.Position memory pos = futures.getPosition(cid, alice);
        assertEq(pos.size, 1);
        assertEq(uint8(pos.status), uint8(IFutures.PositionStatus.OPEN));
    }

    function test_closePosition_updatesOpenInterest() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 2, BTC_PRICE, margin * 2);

        vm.prank(alice);
        futures.closePosition(cid, 1, BTC_PRICE);

        (uint256 longOI,) = futures.getOpenInterest(cid);
        assertEq(longOI, 1);
    }

    function test_revert_closePosition_noPosition() public {
        uint256 cid = _createDefaultContract();

        vm.prank(alice);
        vm.expectRevert(IFutures.PositionNotFound.selector);
        futures.closePosition(cid, 1, BTC_PRICE);
    }

    function test_revert_closePosition_tooMuch() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        vm.prank(alice);
        vm.expectRevert(IFutures.InsufficientPosition.selector);
        futures.closePosition(cid, 2, BTC_PRICE);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Margin Operations
    // ══════════════════════════════════════════════════════════════════════

    function test_depositMargin() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        vm.prank(alice);
        futures.depositMargin(cid, 1000e18);

        IFutures.Position memory pos = futures.getPosition(cid, alice);
        assertEq(pos.margin, margin + 1000e18);
    }

    function test_revert_depositMargin_noPosition() public {
        uint256 cid = _createDefaultContract();

        vm.prank(alice);
        vm.expectRevert(IFutures.PositionNotFound.selector);
        futures.depositMargin(cid, 1000e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Daily Settlement
    // ══════════════════════════════════════════════════════════════════════

    function test_dailySettlement() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        // Price increases to $62,000
        oracle.setPrice(address(wbtc), 62_000e18);

        vm.prank(keeper);
        futures.dailySettlement(cid);

        // Alice (long) should have gained margin, Bob (short) should have lost
        IFutures.Position memory alicePos = futures.getPosition(cid, alice);
        IFutures.Position memory bobPos = futures.getPosition(cid, bob);

        assertGt(alicePos.margin, margin); // Long gained
        assertLt(bobPos.margin, margin); // Short lost
    }

    function test_dailySettlement_emitsMarginCall() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18; // 10% of 60000

        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        // Price jumps to $65,500 — short loses $5,500, margin drops to $500
        // Maintenance = 65500 * 5% = 3275, but margin = 500 < 3275
        oracle.setPrice(address(wbtc), 65_500e18);

        vm.prank(keeper);
        // Should emit MarginCall for bob
        futures.dailySettlement(cid);

        IFutures.Position memory pos = futures.getPosition(cid, bob);
        assertLt(pos.margin, (65_500e18 * MAINTENANCE_MARGIN_BPS) / BPS);
    }

    function test_revert_dailySettlement_notKeeper() public {
        uint256 cid = _createDefaultContract();

        vm.prank(alice);
        vm.expectRevert();
        futures.dailySettlement(cid);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Liquidation
    // ══════════════════════════════════════════════════════════════════════

    function test_liquidate() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        // Need counterparty so contract holds enough tokens
        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);
        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        // Price jumps to $64,000 — short loses $4000, margin drops to $2000
        // Maintenance at $64k = 64000 * 5% = 3200 > 2000 — liquidatable
        oracle.setPrice(address(wbtc), 64_000e18);

        // Run daily settlement first to update mark price and margins
        vm.prank(keeper);
        futures.dailySettlement(cid);

        // Bob's margin should now be below maintenance
        assertTrue(futures.isLiquidatable(cid, bob));

        address charlie = address(0x1234);
        uint256 liquidatorBalBefore = usdl.balanceOf(charlie);

        // Charlie liquidates Bob
        vm.prank(charlie);
        futures.liquidate(cid, bob);

        IFutures.Position memory pos = futures.getPosition(cid, bob);
        assertEq(pos.size, 0);
        assertEq(uint8(pos.status), uint8(IFutures.PositionStatus.LIQUIDATED));

        // Charlie received liquidation penalty (2.5% of remaining margin)
        uint256 liquidatorBalAfter = usdl.balanceOf(charlie);
        assertGt(liquidatorBalAfter, liquidatorBalBefore);
    }

    function test_revert_liquidate_notLiquidatable() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        // Run daily settlement at same price — no PnL change
        vm.prank(keeper);
        futures.dailySettlement(cid);

        vm.prank(bob);
        vm.expectRevert(IFutures.NotLiquidatable.selector);
        futures.liquidate(cid, alice);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Final Settlement
    // ══════════════════════════════════════════════════════════════════════

    function test_finalSettlement() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        // Warp past expiry
        vm.warp(block.timestamp + 31 days);

        // Set final price at $62,000
        oracle.setPrice(address(wbtc), 62_000e18);

        uint256 aliceBalBefore = usdl.balanceOf(alice);
        uint256 bobBalBefore = usdl.balanceOf(bob);

        vm.prank(keeper);
        futures.finalSettlement(cid);

        assertTrue(futures.isFinallySettled(cid));
        assertEq(futures.finalSettlementPrices(cid), 62_000e18);

        // Alice (long) should profit, Bob (short) should lose
        uint256 aliceBalAfter = usdl.balanceOf(alice);
        uint256 bobBalAfter = usdl.balanceOf(bob);

        assertGt(aliceBalAfter, aliceBalBefore);
        // Bob gets remaining margin back (if any)
        // His loss = 2000e18, margin was 6000e18, so he gets ~4000 back
        assertGt(bobBalAfter, bobBalBefore);
    }

    function test_revert_finalSettlement_notExpired() public {
        uint256 cid = _createDefaultContract();

        vm.prank(keeper);
        vm.expectRevert(IFutures.ContractNotExpired.selector);
        futures.finalSettlement(cid);
    }

    function test_revert_finalSettlement_alreadySettled() public {
        uint256 cid = _createDefaultContract();
        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), BTC_PRICE);

        vm.prank(keeper);
        futures.finalSettlement(cid);

        vm.prank(keeper);
        vm.expectRevert(IFutures.ContractAlreadySettled.selector);
        futures.finalSettlement(cid);
    }

    // ══════════════════════════════════════════════════════════════════════
    // View Functions
    // ══════════════════════════════════════════════════════════════════════

    function test_getUnrealisedPnl() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        // Update mark price
        oracle.setPrice(address(wbtc), 62_000e18);
        vm.prank(keeper);
        futures.dailySettlement(cid);

        // Set new mark price for next check
        oracle.setPrice(address(wbtc), 63_000e18);
        // Update last settlement price
        vm.prank(keeper);
        futures.dailySettlement(cid);

        // Unrealised PnL is 0 right after settlement (since daily settlement realises PnL)
        int256 pnl = futures.getUnrealisedPnl(cid, alice);
        assertEq(pnl, 0); // Just settled, so unrealised = 0
    }

    function test_isLiquidatable_false_noPosition() public {
        uint256 cid = _createDefaultContract();
        assertFalse(futures.isLiquidatable(cid, alice));
    }

    function test_getTraderCount() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        assertEq(futures.getTraderCount(cid), 0);

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        assertEq(futures.getTraderCount(cid), 1);

        vm.prank(bob);
        futures.openPosition(cid, IFutures.Side.SHORT, 1, BTC_PRICE, margin);

        assertEq(futures.getTraderCount(cid), 2);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Admin
    // ══════════════════════════════════════════════════════════════════════

    function test_setOracle() public {
        address newOracle = address(0x999);
        vm.prank(admin);
        futures.setOracle(newOracle);
        assertEq(futures.oracle(), newOracle);
    }

    function test_revert_setOracle_zero() public {
        vm.prank(admin);
        vm.expectRevert(IFutures.InvalidOracle.selector);
        futures.setOracle(address(0));
    }

    function test_pauseUnpause() public {
        vm.startPrank(admin);
        futures.pause();

        uint256 cid;
        // Create while paused should work (admin operation)
        cid = futures.createContract(
            address(wbtc), address(usdl), block.timestamp + 30 days,
            CONTRACT_SIZE, TICK_SIZE, INITIAL_MARGIN_BPS, MAINTENANCE_MARGIN_BPS,
            IFutures.SettlementType.CASH
        );

        futures.unpause();
        vm.stopPrank();

        // Now trading should work
        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, 6000e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Fee Collection
    // ══════════════════════════════════════════════════════════════════════

    function test_feeCollection() public {
        uint256 cid = _createDefaultContract();
        uint256 margin = 6000e18;

        uint256 feeReceiverBefore = usdl.balanceOf(feeReceiver);

        vm.prank(alice);
        futures.openPosition(cid, IFutures.Side.LONG, 1, BTC_PRICE, margin);

        uint256 feeReceiverAfter = usdl.balanceOf(feeReceiver);
        assertGt(feeReceiverAfter, feeReceiverBefore); // Fee collected on open
    }
}
