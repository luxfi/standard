// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {Markets} from "../../contracts/markets/Markets.sol";
import {AdaptiveCurveRateModel} from "../../contracts/markets/ratemodel/AdaptiveCurveRateModel.sol";
import {MockChainlinkOracle} from "../../contracts/mocks/MockChainlinkOracle.sol";
import {MarketParams, Position, Market, Id} from "../../contracts/markets/interfaces/IMarkets.sol";
import {IOracle} from "../../contracts/markets/interfaces/IOracle.sol";
import {MarketParamsLib} from "../../contracts/markets/libraries/MarketParamsLib.sol";
import {ILRC20} from "../../contracts/tokens/interfaces/ILRC20.sol";

// Shared test mocks
import {MockERC20Minimal as MockERC20} from "./TestMocks.sol";

/// @title MarketsTest
/// @notice Comprehensive test suite for Lux Markets lending protocol
contract MarketsTest is Test {
    using MarketParamsLib for MarketParams;

    // Contracts
    Markets public markets;
    AdaptiveCurveRateModel public rateModel;
    MockChainlinkOracle public oracle;

    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;

    // Test users
    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public liquidator = makeAddr("liquidator");
    address public feeRecipient = makeAddr("feeRecipient");

    // Market parameters
    MarketParams public ethMarket;
    MarketParams public btcMarket;
    Id public ethMarketId;
    Id public btcMarketId;

    // Constants
    uint256 constant ORACLE_PRICE_SCALE = 1e36;
    uint256 constant WAD = 1e18;
    uint256 constant LLTV_90 = 0.9e18; // 90% LTV
    uint256 constant LLTV_80 = 0.8e18; // 80% LTV
    uint256 constant LLTV_70 = 0.7e18; // 70% LTV

    // Events for testing
    event MarketCreated(Id indexed id, MarketParams marketParams);
    event Supply(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(Id indexed id, address indexed caller, address indexed onBehalf, address receiver, uint256 assets, uint256 shares);
    event Borrow(Id indexed id, address indexed caller, address indexed onBehalf, address receiver, uint256 assets, uint256 shares);
    event Repay(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);
    event SupplyCollateral(Id indexed id, address indexed caller, address indexed onBehalf, uint256 assets);
    event WithdrawCollateral(Id indexed id, address indexed caller, address indexed onBehalf, address receiver, uint256 assets);
    event Liquidate(Id indexed id, address indexed caller, address indexed borrower, uint256 repaidAssets, uint256 repaidShares, uint256 seizedAssets, uint256 badDebtAssets, uint256 badDebtShares);
    event AccrueInterest(Id indexed id, uint256 prevBorrowRate, uint256 interest, uint256 feeShares);

    function setUp() public {
        // Deploy Markets
        markets = new Markets(owner);

        // Deploy rate model
        rateModel = new AdaptiveCurveRateModel();

        // Deploy oracle (ETH price = $2000)
        // Oracle price = collateral_price / loan_price * 1e36 / 10^(collat_dec - loan_dec)
        // For WETH/USDC: 2000/1 * 1e36 / 10^(18-6) = 2000e24
        // This means 1 WETH (1e18) is worth 2000 USDC (2000e6)
        oracle = new MockChainlinkOracle(2000e24, 18);

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        // Enable rate model and LLTVs
        markets.enableRateModel(address(rateModel));
        markets.enableLltv(LLTV_90);
        markets.enableLltv(LLTV_80);
        markets.enableLltv(LLTV_70);

        // Set fee recipient
        markets.setFeeRecipient(feeRecipient);

        // Create ETH/USDC market
        ethMarket = MarketParams({
            loanToken: address(usdc),
            collateralToken: address(weth),
            oracle: address(oracle),
            rateModel: address(rateModel),
            lltv: LLTV_80
        });

        markets.createMarket(ethMarket);
        ethMarketId = ethMarket.id();

        // Create BTC/USDC market with different oracle
        // BTC = $40,000, WBTC has 8 decimals, USDC has 6 decimals
        // price = 40000 * 1e36 / 10^(8-6) = 40000e34
        MockChainlinkOracle btcOracle = new MockChainlinkOracle(40000e34, 18);
        btcMarket = MarketParams({
            loanToken: address(usdc),
            collateralToken: address(wbtc),
            oracle: address(btcOracle),
            rateModel: address(rateModel),
            lltv: LLTV_70
        });

        markets.createMarket(btcMarket);
        btcMarketId = btcMarket.id();

        // Mint tokens to test users
        usdc.mint(alice, 1_000_000e6); // 1M USDC
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(liquidator, 1_000_000e6);

        weth.mint(alice, 100e18); // 100 WETH
        weth.mint(bob, 100e18);

        wbtc.mint(alice, 10e8); // 10 BTC
        wbtc.mint(bob, 10e8);

        // Approve Markets
        vm.startPrank(alice);
        usdc.approve(address(markets), type(uint256).max);
        weth.approve(address(markets), type(uint256).max);
        wbtc.approve(address(markets), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(markets), type(uint256).max);
        weth.approve(address(markets), type(uint256).max);
        wbtc.approve(address(markets), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        usdc.approve(address(markets), type(uint256).max);
        weth.approve(address(markets), type(uint256).max);
        vm.stopPrank();
    }

    /* ============ DEPLOYMENT & ADMIN TESTS ============ */

    function test_Deployment() public view {
        assertEq(markets.owner(), owner);
        assertEq(markets.feeRecipient(), feeRecipient);
        assertTrue(markets.isRateModelEnabled(address(rateModel)));
        assertTrue(markets.isLltvEnabled(LLTV_80));
        assertTrue(markets.isLltvEnabled(LLTV_70));
        assertTrue(markets.isLltvEnabled(LLTV_90));
    }

    function test_SetOwner() public {
        address newOwner = makeAddr("newOwner");
        markets.setOwner(newOwner);
        assertEq(markets.owner(), newOwner);
    }

    function test_RevertWhen_SetOwner_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        markets.setOwner(alice);
    }

    function test_RevertWhen_SetOwner_ZeroAddress() public {
        vm.expectRevert();
        markets.setOwner(address(0));
    }

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        markets.setFeeRecipient(newRecipient);
        assertEq(markets.feeRecipient(), newRecipient);
    }

    function test_EnableRateModel() public {
        address newRateModel = makeAddr("newRateModel");
        markets.enableRateModel(newRateModel);
        assertTrue(markets.isRateModelEnabled(newRateModel));
    }

    function test_EnableLltv() public {
        uint256 newLltv = 0.85e18;
        markets.enableLltv(newLltv);
        assertTrue(markets.isLltvEnabled(newLltv));
    }

    function test_RevertWhen_EnableLltv_TooHigh() public {
        vm.expectRevert();
        markets.enableLltv(1e18); // 100% should fail
    }

    function test_SetFee() public {
        markets.setFee(ethMarket, 0.1e18); // 10% fee
        (,,,,, uint128 fee) = markets.market(ethMarketId);
        assertEq(fee, 0.1e18);
    }

    function test_RevertWhen_SetFee_TooHigh() public {
        vm.expectRevert();
        markets.setFee(ethMarket, 0.3e18); // 30% exceeds MAX_FEE (25%)
    }

    /* ============ MARKET CREATION TESTS ============ */

    function test_CreateMarket() public {
        assertTrue(markets.isMarketCreated(ethMarketId));
        assertTrue(markets.isMarketCreated(btcMarketId));
    }

    function test_RevertWhen_CreateMarket_AlreadyCreated() public {
        vm.expectRevert();
        markets.createMarket(ethMarket);
    }

    function test_RevertWhen_CreateMarket_RateModelNotEnabled() public {
        MarketParams memory badMarket = MarketParams({
            loanToken: address(usdc),
            collateralToken: address(weth),
            oracle: address(oracle),
            rateModel: makeAddr("badRateModel"),
            lltv: LLTV_80
        });
        vm.expectRevert();
        markets.createMarket(badMarket);
    }

    function test_RevertWhen_CreateMarket_LltvNotEnabled() public {
        MarketParams memory badMarket = MarketParams({
            loanToken: address(usdc),
            collateralToken: address(weth),
            oracle: address(oracle),
            rateModel: address(rateModel),
            lltv: 0.95e18 // Not enabled
        });
        vm.expectRevert();
        markets.createMarket(badMarket);
    }

    /* ============ SUPPLY TESTS ============ */

    function test_Supply() public {
        uint256 supplyAmount = 10_000e6; // 10,000 USDC

        vm.startPrank(alice);

        uint256 balanceBefore = usdc.balanceOf(alice);
        (uint256 assets, uint256 shares) = markets.supply(ethMarket, supplyAmount, 0, alice, "");
        uint256 balanceAfter = usdc.balanceOf(alice);

        assertEq(assets, supplyAmount);
        assertGt(shares, 0);
        assertEq(balanceBefore - balanceAfter, supplyAmount);
        assertEq(markets.supplyShares(ethMarketId, alice), shares);
        assertEq(markets.totalSupplyAssets(ethMarketId), supplyAmount);

        vm.stopPrank();
    }

    function test_Supply_OnBehalf() public {
        uint256 supplyAmount = 5_000e6;

        vm.startPrank(alice);
        markets.supply(ethMarket, supplyAmount, 0, bob, "");
        vm.stopPrank();

        assertGt(markets.supplyShares(ethMarketId, bob), 0);
    }

    function test_Supply_MultipleUsers() public {
        uint256 aliceSupply = 10_000e6;
        uint256 bobSupply = 20_000e6;

        vm.prank(alice);
        (uint256 aliceAssets, uint256 aliceShares) = markets.supply(ethMarket, aliceSupply, 0, alice, "");

        vm.prank(bob);
        (uint256 bobAssets, uint256 bobShares) = markets.supply(ethMarket, bobSupply, 0, bob, "");

        assertEq(aliceAssets, aliceSupply);
        assertEq(bobAssets, bobSupply);
        assertEq(markets.totalSupplyAssets(ethMarketId), aliceSupply + bobSupply);
    }

    function test_RevertWhen_Supply_ZeroAssets() public {
        vm.prank(alice);
        vm.expectRevert();
        markets.supply(ethMarket, 0, 0, alice, "");
    }

    function testFuzz_Supply(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000e6);

        vm.prank(alice);
        (uint256 assets, uint256 shares) = markets.supply(ethMarket, amount, 0, alice, "");

        assertEq(assets, amount);
        assertGt(shares, 0);
    }

    /* ============ WITHDRAW TESTS ============ */

    function test_Withdraw() public {
        uint256 supplyAmount = 10_000e6;

        vm.startPrank(alice);
        markets.supply(ethMarket, supplyAmount, 0, alice, "");

        uint256 balanceBefore = usdc.balanceOf(alice);
        (uint256 assets, uint256 shares) = markets.withdraw(ethMarket, supplyAmount, 0, alice, alice);
        uint256 balanceAfter = usdc.balanceOf(alice);

        assertEq(assets, supplyAmount);
        assertGt(shares, 0);
        assertEq(balanceAfter - balanceBefore, supplyAmount);
        assertEq(markets.supplyShares(ethMarketId, alice), 0);

        vm.stopPrank();
    }

    function test_Withdraw_Partial() public {
        uint256 supplyAmount = 10_000e6;
        uint256 withdrawAmount = 5_000e6;

        vm.startPrank(alice);
        markets.supply(ethMarket, supplyAmount, 0, alice, "");
        markets.withdraw(ethMarket, withdrawAmount, 0, alice, alice);

        assertGt(markets.supplyShares(ethMarketId, alice), 0);
        assertEq(markets.totalSupplyAssets(ethMarketId), supplyAmount - withdrawAmount);

        vm.stopPrank();
    }

    function test_RevertWhen_Withdraw_InsufficientLiquidity() public {
        // Alice supplies and withdraws
        vm.startPrank(alice);
        markets.supply(ethMarket, 10_000e6, 0, alice, "");
        vm.stopPrank();

        // Bob borrows all liquidity
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, ""); // 10 ETH collateral
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob);
        vm.stopPrank();

        // Alice tries to withdraw (should fail - no liquidity)
        vm.prank(alice);
        vm.expectRevert();
        markets.withdraw(ethMarket, 10_000e6, 0, alice, alice);
    }

    function test_RevertWhen_Withdraw_NotAuthorized() public {
        vm.prank(alice);
        markets.supply(ethMarket, 10_000e6, 0, alice, "");

        // Bob tries to withdraw Alice's funds
        vm.prank(bob);
        vm.expectRevert();
        markets.withdraw(ethMarket, 10_000e6, 0, alice, bob);
    }

    function test_Withdraw_WithAuthorization() public {
        vm.startPrank(alice);
        markets.supply(ethMarket, 10_000e6, 0, alice, "");
        markets.setAuthorization(bob, true);
        vm.stopPrank();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        // Bob can now withdraw on behalf of Alice
        vm.prank(bob);
        markets.withdraw(ethMarket, 5_000e6, 0, alice, bob);

        // Bob should have received 5,000 USDC
        assertEq(usdc.balanceOf(bob), bobBalanceBefore + 5_000e6);
    }

    /* ============ COLLATERAL TESTS ============ */

    function test_SupplyCollateral() public {
        uint256 collateralAmount = 5e18; // 5 ETH

        vm.prank(alice);
        markets.supplyCollateral(ethMarket, collateralAmount, alice, "");

        assertEq(markets.collateral(ethMarketId, alice), collateralAmount);
        assertEq(weth.balanceOf(address(markets)), collateralAmount);
    }

    function test_WithdrawCollateral() public {
        uint256 collateralAmount = 5e18;

        vm.startPrank(alice);
        markets.supplyCollateral(ethMarket, collateralAmount, alice, "");
        markets.withdrawCollateral(ethMarket, collateralAmount, alice, alice);
        vm.stopPrank();

        assertEq(markets.collateral(ethMarketId, alice), 0);
    }

    function test_RevertWhen_WithdrawCollateral_InsufficientCollateral() public {
        // Supply liquidity
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // Supply collateral and borrow
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, ""); // 10 ETH = $20,000
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob); // Borrow $10,000 (50% LTV)

        // Try to withdraw collateral that would make position unhealthy
        vm.expectRevert();
        markets.withdrawCollateral(ethMarket, 9e18, bob, bob); // Would leave only 1 ETH = $2,000
        vm.stopPrank();
    }

    /* ============ BORROW TESTS ============ */

    function test_Borrow() public {
        // Alice supplies liquidity
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // Bob supplies collateral and borrows
        uint256 collateralAmount = 10e18; // 10 ETH = $20,000
        uint256 borrowAmount = 10_000e6; // Borrow $10,000 (50% LTV, safe with 80% max)

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, collateralAmount, bob, "");

        uint256 balanceBefore = usdc.balanceOf(bob);
        (uint256 assets, uint256 shares) = markets.borrow(ethMarket, borrowAmount, 0, bob, bob);
        uint256 balanceAfter = usdc.balanceOf(bob);

        assertEq(assets, borrowAmount);
        assertGt(shares, 0);
        assertEq(balanceAfter - balanceBefore, borrowAmount);
        assertEq(markets.borrowShares(ethMarketId, bob), shares);
        assertEq(markets.totalBorrowAssets(ethMarketId), borrowAmount);

        vm.stopPrank();
    }

    function test_RevertWhen_Borrow_InsufficientCollateral() public {
        // Alice supplies liquidity
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // Bob tries to borrow too much
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, ""); // 10 ETH = $20,000
        vm.expectRevert();
        markets.borrow(ethMarket, 17_000e6, 0, bob, bob); // Try to borrow $17,000 (85% LTV, exceeds 80%)
        vm.stopPrank();
    }

    function test_RevertWhen_Borrow_NoLiquidity() public {
        // Bob tries to borrow without anyone supplying
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        vm.expectRevert();
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob);
        vm.stopPrank();
    }

    function test_Borrow_MaxLTV() public {
        // Alice supplies liquidity
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // Bob borrows at max LTV
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, ""); // 10 ETH = $20,000

        // Max borrow at 80% LTV = $16,000
        uint256 maxBorrow = 16_000e6;
        markets.borrow(ethMarket, maxBorrow, 0, bob, bob);

        assertEq(markets.totalBorrowAssets(ethMarketId), maxBorrow);
        vm.stopPrank();
    }

    /* ============ REPAY TESTS ============ */

    function test_Repay() public {
        // Setup: Alice supplies, Bob borrows
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob);

        // Bob repays
        uint256 balanceBefore = usdc.balanceOf(bob);
        (uint256 assets, uint256 shares) = markets.repay(ethMarket, 5_000e6, 0, bob, "");
        uint256 balanceAfter = usdc.balanceOf(bob);

        assertEq(assets, 5_000e6);
        assertGt(shares, 0);
        assertEq(balanceBefore - balanceAfter, 5_000e6);
        assertGt(markets.borrowShares(ethMarketId, bob), 0); // Still has debt

        vm.stopPrank();
    }

    function test_Repay_Full() public {
        // Setup: Alice supplies, Bob borrows
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob);

        // Bob repays in full
        markets.repay(ethMarket, 10_000e6, 0, bob, "");

        assertEq(markets.borrowShares(ethMarketId, bob), 0);
        assertEq(markets.totalBorrowAssets(ethMarketId), 0);

        vm.stopPrank();
    }

    /* ============ INTEREST ACCRUAL TESTS ============ */

    function test_InterestAccrual() public {
        // Setup: Alice supplies, Bob borrows
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // Bob has 10 ETH ($20,000), can borrow max 80% = $16,000
        // Borrow $10,000 (50% LTV, safe)
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob);
        vm.stopPrank();

        uint256 borrowBefore = markets.totalBorrowAssets(ethMarketId);
        uint256 supplyBefore = markets.totalSupplyAssets(ethMarketId);

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        // Trigger interest accrual
        vm.prank(alice);
        markets.supply(ethMarket, 1e6, 0, alice, "");

        uint256 borrowAfter = markets.totalBorrowAssets(ethMarketId);
        uint256 supplyAfter = markets.totalSupplyAssets(ethMarketId);

        // Borrow should have increased due to interest
        assertGt(borrowAfter, borrowBefore);
        assertGt(supplyAfter, supplyBefore);
    }

    function test_InterestAccrual_WithFee() public {
        // Set protocol fee
        markets.setFee(ethMarket, 0.1e18); // 10% fee

        // Setup: Alice supplies, Bob borrows at high utilization
        vm.prank(alice);
        markets.supply(ethMarket, 20_000e6, 0, alice, "");

        // Bob has 10 ETH ($20,000), can borrow max 80% = $16,000
        // Borrow $16,000 to maximize utilization (80% of supply)
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 16_000e6, 0, bob, bob);
        vm.stopPrank();

        // Fast forward and accrue (higher utilization = more interest)
        vm.warp(block.timestamp + 365 days);
        vm.prank(alice);
        markets.supply(ethMarket, 1e6, 0, alice, "");

        // Fee recipient should have shares (utilization is 80%, which generates meaningful interest)
        assertGt(markets.supplyShares(ethMarketId, feeRecipient), 0);
    }

    /* ============ LIQUIDATION TESTS ============ */

    function test_Liquidate() public {
        // Setup: Alice supplies, Bob borrows at max LTV
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, ""); // 10 ETH = $20,000
        markets.borrow(ethMarket, 15_900e6, 0, bob, bob); // ~79.5% LTV
        vm.stopPrank();

        // Price drops, making Bob's position liquidatable
        // ETH drops to $1,600 (20% drop): 1600e24
        oracle.setPrice(1600e24);
        // Collateral value: 10 * $1,600 = $16,000
        // Max borrow at 80% LTV: $12,800
        // Current borrow: $15,900 -> underwater!

        // Liquidator liquidates
        vm.startPrank(liquidator);
        uint256 wethBefore = weth.balanceOf(liquidator);

        markets.liquidate(ethMarket, bob, 5e18, 0, ""); // Liquidate 5 ETH collateral

        uint256 wethAfter = weth.balanceOf(liquidator);

        assertGt(wethAfter, wethBefore); // Liquidator receives collateral
        assertLt(markets.collateral(ethMarketId, bob), 10e18); // Bob's collateral reduced

        vm.stopPrank();
    }

    function test_RevertWhen_Liquidate_HealthyPosition() public {
        // Setup: Alice supplies, Bob borrows safely
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob); // Only 50% LTV
        vm.stopPrank();

        // Try to liquidate healthy position (should fail)
        vm.prank(liquidator);
        vm.expectRevert();
        markets.liquidate(ethMarket, bob, 1e18, 0, "");
    }

    function test_Liquidate_BadDebt() public {
        // Setup: Alice supplies, Bob borrows
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 15_900e6, 0, bob, bob);
        vm.stopPrank();

        // Extreme price crash
        // ETH crashes to $1,000 (50% drop): 1000e24
        oracle.setPrice(1000e24);
        // Collateral value: 10 * $1,000 = $10,000
        // Debt: $15,900 -> insolvent!

        // Liquidate entire position
        vm.prank(liquidator);
        markets.liquidate(ethMarket, bob, 10e18, 0, ""); // Liquidate all collateral

        // Bad debt should be written off
        assertEq(markets.collateral(ethMarketId, bob), 0);
        assertEq(markets.borrowShares(ethMarketId, bob), 0);
    }

    function test_Liquidation_Incentive() public {
        // Setup
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 15_900e6, 0, bob, bob);
        vm.stopPrank();

        // Price drops: 1600e24
        oracle.setPrice(1600e24);

        // Calculate expected liquidation incentive
        // LLTV = 80%, so incentive = 1 + (1 - 0.8) / 2 = 1.1 (10%)

        vm.startPrank(liquidator);
        uint256 usdcBefore = usdc.balanceOf(liquidator);
        uint256 wethBefore = weth.balanceOf(liquidator);

        markets.liquidate(ethMarket, bob, 5e18, 0, "");

        uint256 usdcAfter = usdc.balanceOf(liquidator);
        uint256 wethAfter = weth.balanceOf(liquidator);

        uint256 usdcPaid = usdcBefore - usdcAfter;
        uint256 wethReceived = wethAfter - wethBefore;

        // Liquidator should receive bonus (more value than they paid)
        // WETH value in USD: wethReceived (18 dec) * 1600 (price) / 1e18 = value in USD
        // USDC paid is 6 decimals, so we scale both to same base
        // wethReceivedValue = wethReceived * 1600 / 1e18 (in whole USD)
        // usdcPaid value = usdcPaid / 1e6 (in whole USD)
        // We want: wethValue > usdcValue, so: wethReceived * 1600 / 1e18 > usdcPaid / 1e6
        // Multiply both by 1e18: wethReceived * 1600 > usdcPaid * 1e12
        uint256 collateralValueScaled = wethReceived * 1600;
        uint256 usdcPaidScaled = usdcPaid * 1e12;
        assertGt(collateralValueScaled, usdcPaidScaled);

        vm.stopPrank();
    }

    /* ============ FLASH LOAN TESTS ============ */

    function test_FlashLoan() public {
        // Setup liquidity
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // Deploy flash loan borrower
        FlashLoanBorrower borrower = new FlashLoanBorrower(address(markets), address(usdc));
        usdc.mint(address(borrower), 1e6); // Give it some USDC for fee

        // Execute flash loan
        borrower.executeFlashLoan(50_000e6);

        // Verify flash loan succeeded
        assertTrue(borrower.flashLoanExecuted());
    }

    /* ============ HEALTH FACTOR TESTS ============ */

    function test_HealthFactor_Healthy() public {
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, ""); // $20,000 collateral
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob); // $10,000 borrowed (50% LTV)
        vm.stopPrank();

        // Position should be healthy (can withdraw some collateral)
        vm.prank(bob);
        markets.withdrawCollateral(ethMarket, 1e18, bob, bob);
    }

    function test_HealthFactor_Critical() public {
        vm.prank(alice);
        markets.supply(ethMarket, 100_000e6, 0, alice, "");

        // 10 ETH = $20,000 collateral, 80% LTV = $16,000 max borrow
        // Borrow exactly $16,000 (at the max)
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 16_000e6, 0, bob, bob);

        // Can't borrow any more (already at max LTV)
        vm.expectRevert();
        markets.borrow(ethMarket, 1e6, 0, bob, bob);

        vm.stopPrank();
    }

    /* ============ FUZZ TESTS ============ */

    function testFuzz_SupplyAndWithdraw(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000e6);

        vm.startPrank(alice);
        markets.supply(ethMarket, amount, 0, alice, "");
        markets.withdraw(ethMarket, amount, 0, alice, alice);
        vm.stopPrank();

        assertEq(markets.supplyShares(ethMarketId, alice), 0);
    }

    function testFuzz_CollateralOperations(uint256 amount) public {
        amount = bound(amount, 1e18, 100e18);

        vm.startPrank(alice);
        markets.supplyCollateral(ethMarket, amount, alice, "");
        markets.withdrawCollateral(ethMarket, amount, alice, alice);
        vm.stopPrank();

        assertEq(markets.collateral(ethMarketId, alice), 0);
    }

    function testFuzz_BorrowAndRepay(uint256 borrowAmount) public {
        // Setup
        vm.prank(alice);
        markets.supply(ethMarket, 1_000_000e6, 0, alice, "");

        borrowAmount = bound(borrowAmount, 1_000e6, 16_000e6); // Max $16k at 80% LTV on 10 ETH

        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, borrowAmount, 0, bob, bob);
        markets.repay(ethMarket, borrowAmount, 0, bob, "");
        vm.stopPrank();

        assertEq(markets.borrowShares(ethMarketId, bob), 0);
    }

    /* ============ MULTI-MARKET TESTS ============ */

    function test_MultipleMarkets() public {
        // Test ETH market
        vm.prank(alice);
        markets.supply(ethMarket, 10_000e6, 0, alice, "");

        // Test BTC market
        vm.prank(bob);
        markets.supply(btcMarket, 20_000e6, 0, bob, "");

        assertEq(markets.totalSupplyAssets(ethMarketId), 10_000e6);
        assertEq(markets.totalSupplyAssets(btcMarketId), 20_000e6);
    }

    function test_CrossMarketIsolation() public {
        // Supply to both markets
        vm.startPrank(alice);
        markets.supply(ethMarket, 50_000e6, 0, alice, "");
        markets.supply(btcMarket, 50_000e6, 0, alice, "");
        vm.stopPrank();

        // Borrow from ETH market
        vm.startPrank(bob);
        markets.supplyCollateral(ethMarket, 10e18, bob, "");
        markets.borrow(ethMarket, 10_000e6, 0, bob, bob);

        // BTC market liquidity should be unaffected
        assertEq(markets.totalBorrowAssets(btcMarketId), 0);

        vm.stopPrank();
    }
}

/// @title FlashLoanBorrower
/// @notice Mock contract for testing flash loans
contract FlashLoanBorrower {
    Markets public markets;
    ILRC20 public token;
    bool public flashLoanExecuted;

    constructor(address _markets, address _token) {
        markets = Markets(_markets);
        token = ILRC20(_token);
    }

    function executeFlashLoan(uint256 amount) external {
        markets.flashLoan(address(token), amount, "");
    }

    function onFlashLoan(uint256 amount, bytes calldata) external {
        require(msg.sender == address(markets), "Not markets");
        flashLoanExecuted = true;

        // Approve repayment
        token.approve(address(markets), amount);
    }
}
