// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { PerAssetLedger } from "../../../contracts/bridge/v4/PerAssetLedger.sol";

contract TestLedger is PerAssetLedger {
    function recordDeposit(address asset, uint256 raw, uint256 baseUnits) external {
        _recordDeposit(asset, raw, baseUnits);
    }

    function recordWithdraw(address asset, uint256 raw, uint256 baseUnits) external {
        _recordWithdraw(asset, raw, baseUnits);
    }
}

contract PerAssetLedgerTest is Test {
    TestLedger internal ledger;
    address internal usdt = makeAddr("usdt");
    address internal dai = makeAddr("dai");

    function setUp() public {
        ledger = new TestLedger();
    }

    function test_DepositTracksReserve() public {
        ledger.recordDeposit(usdt, 1_000_000, 1e18); // 1 USDT (6) → 1e18 base unit
        assertEq(ledger.assetReserve(usdt), 1_000_000);
        assertEq(ledger.totalReserveInBaseUnits(), 1e18);
    }

    function test_MultipleAssets() public {
        ledger.recordDeposit(usdt, 1_000_000, 1e18);
        ledger.recordDeposit(dai, 5e18, 5e18);
        assertEq(ledger.assetReserve(usdt), 1_000_000);
        assertEq(ledger.assetReserve(dai), 5e18);
        assertEq(ledger.totalReserveInBaseUnits(), 6e18);
    }

    function test_WithdrawSubtracts() public {
        ledger.recordDeposit(usdt, 5_000_000, 5e18);
        ledger.recordWithdraw(usdt, 2_000_000, 2e18);
        assertEq(ledger.assetReserve(usdt), 3_000_000);
        assertEq(ledger.totalReserveInBaseUnits(), 3e18);
    }

    function test_WithdrawOverReserve_Reverts() public {
        ledger.recordDeposit(usdt, 1_000_000, 1e18);
        vm.expectRevert(PerAssetLedger.PerAssetLedger_InsufficientReserve.selector);
        ledger.recordWithdraw(usdt, 2_000_000, 2e18);
    }

    function test_WithdrawUnknownAsset_Reverts() public {
        vm.expectRevert(PerAssetLedger.PerAssetLedger_InsufficientReserve.selector);
        ledger.recordWithdraw(usdt, 1, 1);
    }

    function testFuzz_DepositWithdrawRoundtrip(uint64 raw, uint64 base) public {
        vm.assume(raw > 0 && base > 0);
        ledger.recordDeposit(usdt, raw, base);
        ledger.recordWithdraw(usdt, raw, base);
        assertEq(ledger.assetReserve(usdt), 0);
        assertEq(ledger.totalReserveInBaseUnits(), 0);
    }

    function testFuzz_MultipleDepositsAccumulate(uint16 n) public {
        n = uint16(bound(n, 1, 200));
        uint256 sumBase;
        for (uint16 i = 0; i < n; i++) {
            ledger.recordDeposit(usdt, 1_000_000, 1e18);
            sumBase += 1e18;
        }
        assertEq(ledger.totalReserveInBaseUnits(), sumBase);
        assertEq(ledger.assetReserve(usdt), uint256(n) * 1_000_000);
    }
}
