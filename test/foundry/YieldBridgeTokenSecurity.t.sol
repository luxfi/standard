// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { YieldBearingBridgeToken } from "../../contracts/bridge/yield/YieldBearingBridgeToken.sol";

contract YieldBridgeTokenSecurity is Test {
    YieldBearingBridgeToken token;

    address bridge = address(0xB);
    address feeReceiver = address(0xFE);
    address owner;

    // Mirror contract constants
    uint256 constant VIRTUAL_SHARES = 1e8;
    uint256 constant VIRTUAL_ASSETS = 1;
    uint256 constant BASIS_POINTS = 10000;

    function setUp() public {
        owner = address(this);
        token = new YieldBearingBridgeToken(
            "Yield Test Token",
            "yTEST",
            "TEST",
            1,
            bridge,
            feeReceiver
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _deposit(address receiver, uint256 assets) internal returns (uint256 shares) {
        vm.prank(bridge);
        shares = token.deposit(assets, receiver);
    }

    /// @dev Bridge burns its own shares in withdraw(). In production, user transfers
    ///      shares to bridge before bridge calls withdraw. We simulate that here.
    function _withdraw(address from, uint256 shares, address receiver) internal returns (uint256 assets) {
        vm.prank(from);
        token.transfer(bridge, shares);
        vm.prank(bridge);
        assets = token.withdraw(shares, receiver);
    }

    function _yieldReport(uint256 totalAssets, uint256 yield_, uint256 ts, bytes32 id) internal {
        vm.prank(bridge);
        token.processYieldReport(totalAssets, yield_, ts, id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 1. FIRST-DEPOSITOR INFLATION ATTACK
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: attacker deposits 1 wei, donates large yield, victim deposits.
    ///         Virtual offset (VIRTUAL_SHARES=1e3, VIRTUAL_ASSETS=1) protects against
    ///         donations up to ~VIRTUAL_SHARES times the victim deposit.
    ///         The max rounding loss is bounded by: donation / (donation + VIRTUAL_ASSETS)
    ///         * (VIRTUAL_ASSETS / VIRTUAL_SHARES) -- roughly 1/VIRTUAL_SHARES of deposit.
    ///
    ///         With VIRTUAL_SHARES=1e3, victim loses at most ~0.1% when donation < victimDeposit.
    ///         Beyond that ratio, loss grows. This test bounds donation to the effective
    ///         protection range and verifies <0.2% loss.
    function testFuzz_firstDepositorAttack(uint256 donationAmount, uint256 victimDeposit) public {
        victimDeposit = bound(victimDeposit, 1e6, 1e30);
        // Virtual offset with VIRTUAL_SHARES=1e3 protects within this ratio.
        // donation <= victimDeposit ensures loss stays under ~0.1%.
        donationAmount = bound(donationAmount, 1e6, victimDeposit);

        address attacker = address(0xA1);
        address victim = address(0xA2);

        // Step 1: Attacker deposits 1 wei
        uint256 attackerShares = _deposit(attacker, 1);
        assertTrue(attackerShares > 0, "attacker got zero shares");

        // Step 2: Attacker "donates" via yield report (inflates exchange rate)
        uint256 newTotal = 1 + donationAmount;
        _yieldReport(newTotal, donationAmount, 1, keccak256("donation"));

        // Step 3: Victim deposits
        uint256 victimShares = _deposit(victim, victimDeposit);

        // Step 4: Victim withdraws immediately
        uint256 victimRecovered = _withdraw(victim, victimShares, victim);

        // Virtual offset (VIRTUAL_SHARES=1e3) bounds max extractable value.
        // Victim loss ≤ donation/VIRTUAL_SHARES + rounding.
        // When donation ≤ victimDeposit, loss is ≤ ~0.1% + rounding.
        uint256 victimLoss = victimDeposit > victimRecovered ? victimDeposit - victimRecovered : 0;
        uint256 maxLoss = donationAmount / 1e8 + victimDeposit / 1e8 + 2;
        assertLe(
            victimLoss,
            maxLoss,
            "victim lost more than virtual offset bound"
        );
    }

    /// @notice Demonstrate that virtual offset breaks down when donation >> victim deposit.
    ///         This is a known limitation of the (VIRTUAL_SHARES=1e3, VIRTUAL_ASSETS=1)
    ///         parametrization. ERC-4626 standard recommends higher offsets for production.
    function test_firstDepositorAttackLargeRatio() public {
        address attacker = address(0xA1);
        address victim = address(0xA2);
        uint256 victimDeposit = 1e18;
        uint256 donation = 1000e18; // 1000x victim deposit

        _deposit(attacker, 1);
        _yieldReport(1 + donation, donation, 1, keccak256("d"));
        uint256 victimShares = _deposit(victim, victimDeposit);
        uint256 recovered = _withdraw(victim, victimShares, victim);

        // With VIRTUAL_SHARES=1e8, even 1000x donation ratio causes negligible loss
        // Victim recovers nearly 100% of their deposit
        uint256 loss = victimDeposit > recovered ? victimDeposit - recovered : 0;
        uint256 lossBps = (loss * 10000) / victimDeposit;
        assertTrue(lossBps < 10, "loss should be <0.1% with 1e8 virtual offset");
        emit log_named_uint("loss_bps_at_1000x_ratio", lossBps);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2. DEPOSIT / WITHDRAW ROUND-TRIP
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: deposit X, withdraw all shares, get back ~X (minus rounding)
    function testFuzz_depositWithdrawRoundTrip(uint256 assets) public {
        assets = bound(assets, 1, 1e36);

        address user = address(0xABC);
        uint256 shares = _deposit(user, assets);
        assertTrue(shares > 0, "zero shares minted");

        uint256 recovered = _withdraw(user, shares, user);

        // Rounding loss should be at most 1 wei per operation + virtual offset cost
        // For a single user the virtual offset cost is negligible on large deposits
        assertLe(recovered, assets, "recovered more than deposited");

        // Max rounding loss: 2 wei for two divisions + virtual offset rounding
        // For assets >= VIRTUAL_SHARES the loss is bounded
        if (assets >= VIRTUAL_SHARES) {
            uint256 maxLoss = (assets / VIRTUAL_SHARES) + 2;
            assertGe(recovered, assets - maxLoss, "excessive rounding loss");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3. convertToShares / convertToAssets CONSISTENCY
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: convertToAssets(convertToShares(x)) <= x (no free tokens)
    function testFuzz_conversionNoInflation(uint256 assets) public {
        assets = bound(assets, 0, 1e36);

        uint256 shares = token.convertToShares(assets);
        uint256 backToAssets = token.convertToAssets(shares);
        assertLe(backToAssets, assets, "conversion inflated assets");
    }

    /// @notice Same check after deposits alter the exchange rate
    function testFuzz_conversionNoInflationAfterDeposits(uint256 seedDeposit, uint256 testAmount) public {
        seedDeposit = bound(seedDeposit, 1e3, 1e30);
        testAmount = bound(testAmount, 0, 1e36);

        _deposit(address(0xD1), seedDeposit);

        uint256 shares = token.convertToShares(testAmount);
        uint256 backToAssets = token.convertToAssets(shares);
        assertLe(backToAssets, testAmount, "conversion inflated assets after deposits");
    }

    /// @notice Same check after yield accrual
    function testFuzz_conversionNoInflationAfterYield(uint256 seedDeposit, uint256 yieldAmt, uint256 testAmount) public {
        seedDeposit = bound(seedDeposit, 1e6, 1e30);
        yieldAmt = bound(yieldAmt, 1, seedDeposit);
        testAmount = bound(testAmount, 0, 1e36);

        _deposit(address(0xD1), seedDeposit);
        _yieldReport(seedDeposit + yieldAmt, yieldAmt, 1, keccak256("y1"));

        uint256 shares = token.convertToShares(testAmount);
        uint256 backToAssets = token.convertToAssets(shares);
        assertLe(backToAssets, testAmount, "conversion inflated assets after yield");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4. pricePerShare MATCHES convertToAssets
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice pricePerShare() * shares / 1e18 == convertToAssets(shares) within 1 wei
    function testFuzz_pricePerShareMatchesConvertToAssets(uint256 seedDeposit, uint256 shares) public {
        seedDeposit = bound(seedDeposit, 1e6, 1e30);
        shares = bound(shares, 1, 1e30);

        _deposit(address(0xD1), seedDeposit);

        uint256 pps = token.pricePerShare();
        uint256 viaPrice = (pps * shares) / 1e18;
        uint256 viaConvert = token.convertToAssets(shares);

        // Both use same formula, difference is only multiplication order rounding.
        // Allow 1 wei tolerance per 1e18 of shares.
        uint256 tolerance = (shares / 1e18) + 1;
        assertApproxEqAbs(viaPrice, viaConvert, tolerance, "pricePerShare mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5. exchangeRate MATCHES convertToAssets
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice exchangeRate() == pricePerShare() (they use identical formulas)
    function testFuzz_exchangeRateMatchesPricePerShare(uint256 seedDeposit) public {
        seedDeposit = bound(seedDeposit, 1, 1e30);
        _deposit(address(0xD1), seedDeposit);

        uint256 er = token.exchangeRate();
        uint256 pps = token.pricePerShare();
        assertEq(er, pps, "exchangeRate != pricePerShare");
    }

    /// @notice exchangeRate * shares / 1e18 ~= convertToAssets(shares) within tolerance
    function testFuzz_exchangeRateConsistency(uint256 seedDeposit, uint256 yieldAmt, uint256 shares) public {
        seedDeposit = bound(seedDeposit, 1e6, 1e30);
        yieldAmt = bound(yieldAmt, 0, seedDeposit);
        shares = bound(shares, 1, 1e30);

        _deposit(address(0xD1), seedDeposit);
        if (yieldAmt > 0) {
            _yieldReport(seedDeposit + yieldAmt, yieldAmt, 1, keccak256("y"));
        }

        uint256 er = token.exchangeRate();
        uint256 viaRate = (er * shares) / 1e18;
        uint256 viaConvert = token.convertToAssets(shares);

        uint256 tolerance = (shares / 1e18) + 1;
        assertApproxEqAbs(viaRate, viaConvert, tolerance, "exchangeRate inconsistent with convertToAssets");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6. MULTI-USER PROPORTIONAL SHARES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice 5 users deposit random amounts. Each user's share of underlying
    ///         should be proportional to their share of totalSupply.
    function testFuzz_multiUserProportionalShares(
        uint256 a0,
        uint256 a1,
        uint256 a2,
        uint256 a3,
        uint256 a4
    ) public {
        uint256[5] memory amounts;
        amounts[0] = bound(a0, 1e6, 1e27);
        amounts[1] = bound(a1, 1e6, 1e27);
        amounts[2] = bound(a2, 1e6, 1e27);
        amounts[3] = bound(a3, 1e6, 1e27);
        amounts[4] = bound(a4, 1e6, 1e27);

        address[5] memory users;
        uint256[5] memory shares;
        uint256 totalDeposited;

        for (uint256 i = 0; i < 5; i++) {
            users[i] = address(uint160(0x1000 + i));
            shares[i] = _deposit(users[i], amounts[i]);
            totalDeposited += amounts[i];
        }

        uint256 ts = token.totalSupply();

        for (uint256 i = 0; i < 5; i++) {
            uint256 userAssets = token.convertToAssets(shares[i]);
            // Expected: amounts[i] * totalDeposited / totalDeposited = amounts[i]
            // But due to rounding, check proportionality via share ratio
            // userAssets / totalDeposited ~= shares[i] / totalSupply
            // Rearranged: userAssets * totalSupply ~= shares[i] * totalDeposited (within rounding)

            uint256 lhs = userAssets * ts;
            uint256 rhs = shares[i] * totalDeposited;

            // Tolerance: each user can lose at most 1 unit per rounding step
            // Scale tolerance to match the magnitude of the products
            uint256 tolerance = ts + totalDeposited;
            assertApproxEqAbs(lhs, rhs, tolerance, "proportional share violated");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7. distributeYield FEE MINTING
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Verify fee shares are minted correctly: totalSupply increases by exactly feeShares
    function testFuzz_distributeYieldFeeMinting(uint256 seedDeposit, uint256 yieldAmt) public {
        seedDeposit = bound(seedDeposit, 1e6, 1e30);
        yieldAmt = bound(yieldAmt, 1, 1e30);

        _deposit(address(0xD1), seedDeposit);

        uint256 newTotal = seedDeposit + yieldAmt;
        _yieldReport(newTotal, yieldAmt, 1, keccak256("y"));

        uint256 supplyBefore = token.totalSupply();
        uint256 feeReceiverBefore = token.balanceOf(feeReceiver);

        token.distributeYield();

        uint256 supplyAfter = token.totalSupply();
        uint256 feeReceiverAfter = token.balanceOf(feeReceiver);

        // totalSupply increased by exactly the fee shares minted
        assertEq(supplyAfter - supplyBefore, feeReceiverAfter - feeReceiverBefore, "supply delta != fee receiver delta");

        // No double counting: pendingYield should be 0 after distribution
        assertEq(token.pendingYield(), 0, "pendingYield not zeroed");

        // Second call should revert (no pending yield)
        vm.expectRevert("YieldBearingBridgeToken: no pending yield");
        token.distributeYield();
    }

    /// @notice feeReceiver = address(0) should still work (no fee minted)
    function test_distributeYieldZeroFeeReceiver() public {
        token.setFeeReceiver(address(0));

        _deposit(address(0xD1), 1e18);
        _yieldReport(2e18, 1e18, 1, keccak256("y"));

        uint256 supplyBefore = token.totalSupply();
        token.distributeYield();
        uint256 supplyAfter = token.totalSupply();

        // No shares minted when feeReceiver is zero
        assertEq(supplyAfter, supplyBefore, "shares minted to zero address");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8. processYieldReport ORDERING
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Stale reports (older timestamp) should be rejected
    function test_processYieldReportStaleRejected() public {
        _deposit(address(0xD1), 1e18);

        _yieldReport(2e18, 1e18, 100, keccak256("r1"));

        // Same timestamp should revert
        vm.prank(bridge);
        vm.expectRevert("YieldBearingBridgeToken: stale report");
        token.processYieldReport(3e18, 1e18, 100, keccak256("r2"));

        // Older timestamp should revert
        vm.prank(bridge);
        vm.expectRevert("YieldBearingBridgeToken: stale report");
        token.processYieldReport(3e18, 1e18, 50, keccak256("r3"));
    }

    /// @notice Duplicate report ID should be rejected
    function test_processYieldReportDuplicateRejected() public {
        _deposit(address(0xD1), 1e18);
        bytes32 reportId = keccak256("dup");

        _yieldReport(2e18, 1e18, 100, reportId);

        vm.prank(bridge);
        vm.expectRevert("YieldBearingBridgeToken: already processed");
        token.processYieldReport(3e18, 1e18, 200, reportId);
    }

    /// @notice Valid sequential reports should update state correctly
    function testFuzz_processYieldReportSequential(uint256 yield1, uint256 yield2) public {
        uint256 seed = 1e18;
        yield1 = bound(yield1, 0, 1e30);
        yield2 = bound(yield2, 0, 1e30);

        _deposit(address(0xD1), seed);

        uint256 total1 = seed + yield1;
        _yieldReport(total1, yield1, 100, keccak256("r1"));
        assertEq(token.totalUnderlyingAssets(), total1, "total assets mismatch after r1");

        uint256 total2 = total1 + yield2;
        _yieldReport(total2, yield2, 200, keccak256("r2"));
        assertEq(token.totalUnderlyingAssets(), total2, "total assets mismatch after r2");

        assertEq(token.pendingYield(), yield1 + yield2, "pending yield mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 9. INVARIANT: totalSupply * exchangeRate / 1e18 ~= totalUnderlyingAssets
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice The core vault invariant must hold after deposits + yield
    function testFuzz_invariantTotalValueMatchesUnderlying(
        uint256 deposit1,
        uint256 deposit2,
        uint256 yieldAmt
    ) public {
        deposit1 = bound(deposit1, 1e6, 1e30);
        deposit2 = bound(deposit2, 1e6, 1e30);
        yieldAmt = bound(yieldAmt, 0, 1e30);

        _deposit(address(0xD1), deposit1);
        _deposit(address(0xD2), deposit2);

        if (yieldAmt > 0) {
            uint256 newTotal = deposit1 + deposit2 + yieldAmt;
            _yieldReport(newTotal, yieldAmt, 1, keccak256("y"));
        }

        uint256 ts = token.totalSupply();
        uint256 er = token.exchangeRate();
        uint256 totalUnderlying = token.totalUnderlyingAssets();

        // ts * er / 1e18 should approximate totalUnderlying
        // But we must account for the virtual offset:
        // exchangeRate = (totalUnderlying + VIRTUAL_ASSETS) * 1e18 / (ts + VIRTUAL_SHARES)
        // So: ts * er / 1e18 = ts * (totalUnderlying + 1) / (ts + 1000)
        // This is NOT exactly totalUnderlying because of the virtual offset.
        //
        // The correct invariant with virtual offset:
        // (ts + VIRTUAL_SHARES) * er / 1e18 = totalUnderlying + VIRTUAL_ASSETS
        uint256 lhs = (ts + VIRTUAL_SHARES) * er / 1e18;
        uint256 rhs = totalUnderlying + VIRTUAL_ASSETS;

        // Rounding tolerance: 1 wei per 1e18 of the product + 1
        uint256 tolerance = VIRTUAL_SHARES + ((ts + VIRTUAL_SHARES) / 1e18) + 1;
        assertApproxEqAbs(lhs, rhs, tolerance, "vault invariant violated");
    }

    /// @notice Invariant after yield distribution (fee minting)
    function testFuzz_invariantAfterFeeDistribution(uint256 seedDeposit, uint256 yieldAmt) public {
        seedDeposit = bound(seedDeposit, 1e6, 1e30);
        yieldAmt = bound(yieldAmt, 1, 1e30);

        _deposit(address(0xD1), seedDeposit);
        _yieldReport(seedDeposit + yieldAmt, yieldAmt, 1, keccak256("y"));
        token.distributeYield();

        uint256 ts = token.totalSupply();
        uint256 er = token.exchangeRate();
        uint256 totalUnderlying = token.totalUnderlyingAssets();

        uint256 lhs = (ts + VIRTUAL_SHARES) * er / 1e18;
        uint256 rhs = totalUnderlying + VIRTUAL_ASSETS;

        uint256 tolerance = VIRTUAL_SHARES + ((ts + VIRTUAL_SHARES) / 1e18) + 1;
        assertApproxEqAbs(lhs, rhs, tolerance, "invariant violated after fee distribution");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Zero deposit should revert (zero shares)
    function test_zeroDepositReverts() public {
        vm.prank(bridge);
        vm.expectRevert("YieldBearingBridgeToken: zero shares");
        token.deposit(0, address(0xD1));
    }

    /// @notice Zero withdraw should revert (zero assets)
    function test_zeroWithdrawReverts() public {
        _deposit(bridge, 1e18);

        vm.prank(bridge);
        vm.expectRevert("YieldBearingBridgeToken: zero assets");
        token.withdraw(0, address(0xD1));
    }

    /// @notice Non-bridge cannot deposit
    function test_onlyBridgeDeposit() public {
        vm.expectRevert("YieldBearingBridgeToken: only bridge");
        token.deposit(1e18, address(this));
    }

    /// @notice Non-bridge cannot withdraw
    function test_onlyBridgeWithdraw() public {
        vm.expectRevert("YieldBearingBridgeToken: only bridge");
        token.withdraw(1, address(this));
    }

    /// @notice Non-bridge cannot process yield report
    function test_onlyBridgeYieldReport() public {
        vm.expectRevert("YieldBearingBridgeToken: only bridge");
        token.processYieldReport(1e18, 1e18, 1, keccak256("x"));
    }
}
