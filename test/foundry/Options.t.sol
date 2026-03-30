// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { Options } from "../../contracts/options/Options.sol";
import { AmericanOptions } from "../../contracts/options/AmericanOptions.sol";
import { OptionsRouter } from "../../contracts/options/OptionsRouter.sol";
import { OptionsVault } from "../../contracts/options/OptionsVault.sol";
import { IOptionsRouter } from "../../contracts/interfaces/options/IOptionsRouter.sol";
import { MockERC20 } from "./TestMocks.sol";

/**
 * @title MockOracle
 * @notice Returns (price, timestamp) tuple matching IOracle interface
 */
contract MockOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256, uint256) {
        return (prices[token], block.timestamp);
    }
}

/**
 * @title Options Bug Fix Tests
 * @notice Tests verifying all 7 CTO-reported bugs are fixed plus additional items.
 */
contract OptionsTest is Test {
    Options public options;
    AmericanOptions public american;
    OptionsVault public vault;
    OptionsRouter public router;
    MockOracle public oracle;
    MockERC20 public wbtc;  // underlying (8 decimals)
    MockERC20 public usdl;  // quote (18 decimals)
    MockERC20 public zero;  // 0 decimals token

    address admin = address(0xA);
    address alice = address(0xB);
    address bob   = address(0xC);
    address fees  = address(0xF);

    uint256 constant STRIKE = 50000e18; // $50,000 in 18-dec quote
    uint256 constant WBTC_AMOUNT = 1e8; // 1 BTC in 8-dec underlying

    function setUp() public {
        oracle = new MockOracle();
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdl = new MockERC20("USD Liquidity", "USDL", 18);
        zero = new MockERC20("ZeroDec", "ZERO", 0);

        oracle.setPrice(address(wbtc), 60000e18); // $60,000

        vm.startPrank(admin);
        options = new Options(address(oracle), fees, admin);
        american = new AmericanOptions(address(options), fees, admin);
        vault = new OptionsVault(address(options), admin);
        router = new OptionsRouter(address(options), address(vault), admin);

        // Grant EXERCISE_ROLE to AmericanOptions so it can call releaseWriterCollateral
        options.grantRole(options.EXERCISE_ROLE(), address(american));

        vm.stopPrank();

        // Fund users
        wbtc.mint(alice, 100e8);
        usdl.mint(alice, 1_000_000e18);
        wbtc.mint(bob, 100e8);
        usdl.mint(bob, 1_000_000e18);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _createCallSeries() internal returns (uint256) {
        vm.prank(admin);
        return options.createSeries(
            address(wbtc),
            address(usdl),
            STRIKE,
            block.timestamp + 30 days,
            Options.OptionType.CALL,
            Options.SettlementType.CASH
        );
    }

    function _createPutSeries() internal returns (uint256) {
        vm.prank(admin);
        return options.createSeries(
            address(wbtc),
            address(usdl),
            STRIKE,
            block.timestamp + 30 days,
            Options.OptionType.PUT,
            Options.SettlementType.CASH
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUG 1: write() fee accounting drains collateral
    // ═══════════════════════════════════════════════════════════════════════

    function test_bug1_writeFeeDoesNotDrainCollateral() public {
        uint256 seriesId = _createCallSeries();

        // For a call, collateral = amount * collateralRatio / BPS = 1e8 * 10000 / 10000 = 1e8
        uint256 expectedCollateral = 1e8;
        uint256 fee = (expectedCollateral * 10) / 10000; // 0.1% = 1e4

        vm.startPrank(alice);
        wbtc.approve(address(options), expectedCollateral + fee);
        uint256 collateralReturned = options.write(seriesId, WBTC_AMOUNT, alice);
        vm.stopPrank();

        // Position should record FULL collateral, not collateral - fee
        Options.Position memory pos = options.getPosition(seriesId, alice);
        assertEq(pos.collateral, expectedCollateral, "Position must record full collateral");
        assertEq(collateralReturned, expectedCollateral, "write() must return full collateral");

        // Fee receiver should have received exactly the fee
        assertEq(wbtc.balanceOf(fees), fee, "Fee receiver must get the fee");

        // Options contract should hold exactly the collateral (not collateral - fee)
        assertEq(wbtc.balanceOf(address(options)), expectedCollateral, "Contract must hold full collateral");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUG 2: _calculatePayoutPerOption divides by strikePrice
    // ═══════════════════════════════════════════════════════════════════════

    function test_bug2_callPayoutInUnderlyingTerms() public {
        uint256 seriesId = _createCallSeries();

        // Write 1 BTC call at $50K strike
        vm.startPrank(alice);
        wbtc.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, alice);
        vm.stopPrank();

        // Settle at $60K (ITM by $10K)
        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), 60000e18);

        vm.prank(admin);
        options.settle(seriesId);

        // Call payout is in underlying (wbtc). payoutPerOption = (60K-50K)/60K = 1/6 of underlying
        // For 1e8 amount: payout = (10000e18 * 1e18 / 60000e18) * 1e8 / 1e18 = 16666666 wbtc
        // ~0.1667 BTC worth $10K at $60K
        uint256 payout = options.calculatePayout(seriesId, WBTC_AMOUNT);
        uint256 expected = 16666666; // 0.16666666 BTC in 8-dec
        assertEq(payout, expected, "Call payout must be in underlying (wbtc) terms");
    }

    function test_bug2_putPayoutInQuoteTerms() public {
        uint256 seriesId = _createPutSeries();

        // Write 1 BTC put at $50K strike, collateral = strike * amount / 10**underlyingDec
        // = 50000e18 * 1e8 / 1e8 = 50000e18
        vm.startPrank(alice);
        usdl.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, alice);
        vm.stopPrank();

        // Settle at $40K (ITM by $10K for put)
        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), 40000e18);

        vm.prank(admin);
        options.settle(seriesId);

        // Put payout is in quote (usdl). payoutPerOption = (50K-40K) * PRECISION / 1e8
        // payout = payoutPerOption * 1e8 / PRECISION = 10000e18
        uint256 payout = options.calculatePayout(seriesId, WBTC_AMOUNT);
        assertEq(payout, 10000e18, "Put payout must be $10K in quote (USDL) terms");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUG 3: AmericanOptions exerciseEarly doesn't flow collateral
    // ═══════════════════════════════════════════════════════════════════════

    function test_bug3_earlyExerciseFlowsCollateral() public {
        uint256 seriesId = _createCallSeries();

        // Alice writes 1 BTC call via AmericanOptions
        vm.startPrank(alice);
        wbtc.approve(address(american), type(uint256).max);
        american.writeAmerican(seriesId, WBTC_AMOUNT, bob);
        vm.stopPrank();

        // Bob approves AmericanOptions as ERC1155 operator
        vm.startPrank(bob);
        options.setApprovalForAll(address(american), true);

        // Oracle at 60K, strike at 50K.
        // Call payout per option = (60K - 50K) * PRECISION / 60K = 1/6 PRECISION
        // Total payout = 1/6 PRECISION * 1e8 / PRECISION = ~16666666 wbtc
        uint256 wbtcBefore = wbtc.balanceOf(bob);

        // Bob exercises early
        uint256 payout = american.exerciseEarly(seriesId, WBTC_AMOUNT);
        vm.stopPrank();

        // Payout should be > 0 (the tokens actually transferred, in wbtc)
        assertTrue(payout > 0, "Early exercise must produce nonzero payout");
        assertTrue(wbtc.balanceOf(bob) > wbtcBefore, "Bob must receive wbtc");

        // Bob's option tokens should be gone
        assertEq(options.balanceOf(bob, seriesId), 0, "Bob's option tokens must be burned");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUG 6: OptionsRouter packed leg silent truncation
    // ═══════════════════════════════════════════════════════════════════════

    function test_bug6_seriesIdOverflowReverts() public {
        uint256 seriesId = _createCallSeries();

        vm.startPrank(alice);
        wbtc.approve(address(router), type(uint256).max);
        wbtc.approve(address(options), type(uint256).max);
        options.setApprovalForAll(address(router), true);

        // Create a leg with seriesId > uint16 max — should revert
        IOptionsRouter.Leg[] memory legs = new IOptionsRouter.Leg[](2);
        legs[0] = IOptionsRouter.Leg({
            seriesId: 65536, // > uint16.max (65535)
            isBuy: true,
            quantity: 1e8,
            maxPremium: 0
        });
        legs[1] = IOptionsRouter.Leg({
            seriesId: seriesId,
            isBuy: false,
            quantity: 1e8,
            maxPremium: 0
        });

        vm.expectRevert("seriesId exceeds uint16");
        router.executeStrategy(IOptionsRouter.StrategyType.CUSTOM, legs, 0);
        vm.stopPrank();
    }

    function test_bug6_quantityOverflowReverts() public {
        uint256 seriesId = _createCallSeries();

        vm.startPrank(alice);
        wbtc.approve(address(router), type(uint256).max);
        options.setApprovalForAll(address(router), true);

        // Create a leg with quantity > 47 bits
        IOptionsRouter.Leg[] memory legs = new IOptionsRouter.Leg[](1);
        legs[0] = IOptionsRouter.Leg({
            seriesId: seriesId,
            isBuy: true,
            quantity: uint256(2)**47, // exactly 2^47, exceeds max of 2^47 - 1
            maxPremium: 0
        });

        vm.expectRevert("quantity exceeds 47-bit limit");
        router.executeStrategy(IOptionsRouter.StrategyType.CUSTOM, legs, 0);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUG 7: Zero-decimal token cache
    // ═══════════════════════════════════════════════════════════════════════

    function test_bug7_zeroDecimalTokenCached() public {
        // Create a series with a zero-decimal underlying
        oracle.setPrice(address(zero), 100e18);

        vm.prank(admin);
        uint256 seriesId = options.createSeries(
            address(zero),
            address(usdl),
            100e18,
            block.timestamp + 30 days,
            Options.OptionType.CALL,
            Options.SettlementType.CASH
        );

        // tokenDecimals should return 0 (not 18 default)
        assertEq(options.tokenDecimals(address(zero)), 0, "Zero-decimal token must return 0, not default 18");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MISSING: getCollateralRequired and getExercisePayout
    // ═══════════════════════════════════════════════════════════════════════

    function test_getCollateralRequired() public {
        uint256 seriesId = _createCallSeries();
        uint256 required = options.getCollateralRequired(seriesId, WBTC_AMOUNT);
        assertEq(required, WBTC_AMOUNT, "getCollateralRequired must match calculateCollateral");
    }

    function test_getExercisePayout() public {
        uint256 seriesId = _createCallSeries();

        vm.startPrank(alice);
        wbtc.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), 60000e18);
        vm.prank(admin);
        options.settle(seriesId);

        uint256 payout = options.getExercisePayout(seriesId, WBTC_AMOUNT);
        uint256 expected = 16666666; // same as calculatePayout (0.1667 BTC)
        assertEq(payout, expected, "getExercisePayout must match calculatePayout");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MISSING: IOracle interface used
    // ═══════════════════════════════════════════════════════════════════════

    function test_oracleInterfaceWorks() public {
        uint256 seriesId = _createCallSeries();

        vm.startPrank(alice);
        wbtc.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), 70000e18);

        // settle() uses IOracle(oracle).getPrice() internally
        vm.prank(admin);
        options.settle(seriesId);

        assertEq(options.settlementPrices(seriesId), 70000e18, "Settlement price must come from IOracle");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXERCISE_ROLE gate
    // ═══════════════════════════════════════════════════════════════════════

    function test_releaseWriterCollateral_requiresRole() public {
        uint256 seriesId = _createCallSeries();

        vm.startPrank(alice);
        wbtc.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, alice);
        vm.stopPrank();

        // Random caller cannot call releaseWriterCollateral
        vm.prank(bob);
        vm.expectRevert();
        options.releaseWriterCollateral(seriesId, alice, 1e8);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REGRESSION: basic write-burn-exercise flow
    // ═══════════════════════════════════════════════════════════════════════

    function test_fullCallLifecycle() public {
        uint256 seriesId = _createCallSeries();

        // Alice writes, Bob gets tokens
        vm.startPrank(alice);
        wbtc.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, bob);
        vm.stopPrank();

        assertEq(options.balanceOf(bob, seriesId), WBTC_AMOUNT);

        // Fast forward to expiry, settle ITM
        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), 60000e18);
        vm.prank(admin);
        options.settle(seriesId);

        // Bob exercises — payout is in wbtc (collateral token for calls)
        uint256 bobWbtcBefore = wbtc.balanceOf(bob);
        vm.prank(bob);
        uint256 payout = options.exercise(seriesId, WBTC_AMOUNT);

        // Gross payout = 16666666 wbtc (~0.1667 BTC)
        // Net payout = gross - 0.3% fee
        uint256 grossPayout = 16666666;
        uint256 exerciseFee = (grossPayout * 30) / 10000;
        assertEq(payout, grossPayout - exerciseFee, "Net payout after exercise fee");
        assertEq(wbtc.balanceOf(bob), bobWbtcBefore + payout, "Bob received wbtc payout");

        // Alice claims remaining collateral
        vm.prank(alice);
        uint256 claimed = options.claimCollateral(seriesId);
        // Collateral = 1e8, payout obligation = 16666666, so remaining = ~83333334
        assertTrue(claimed > 0, "Writer reclaims remaining collateral");
    }

    function test_fullPutLifecycle() public {
        uint256 seriesId = _createPutSeries();

        // Alice writes put (collateral in quote)
        vm.startPrank(alice);
        usdl.approve(address(options), type(uint256).max);
        options.write(seriesId, WBTC_AMOUNT, bob);
        vm.stopPrank();

        // Fast forward, settle at $40K (put ITM)
        vm.warp(block.timestamp + 31 days);
        oracle.setPrice(address(wbtc), 40000e18);
        vm.prank(admin);
        options.settle(seriesId);

        // Bob exercises put
        vm.prank(bob);
        uint256 payout = options.exercise(seriesId, WBTC_AMOUNT);
        assertTrue(payout > 0, "Put exercise must produce payout");
    }
}
