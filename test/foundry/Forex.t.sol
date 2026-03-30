// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PriceOracle } from "../../contracts/oracle/PriceOracle.sol";
import { ForexPair } from "../../contracts/forex/ForexPair.sol";
import { ForexForward } from "../../contracts/forex/ForexForward.sol";
import { IForexPair } from "../../contracts/interfaces/forex/IForexPair.sol";
import { IForexForward } from "../../contracts/interfaces/forex/IForexForward.sol";

// ═══════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════

/// @dev Mock ERC20 for testing
contract MockERC20 is ERC20 {
    uint8 private _dec;

    constructor(string memory name_, string memory symbol_, uint8 dec_) ERC20(name_, symbol_) {
        _dec = dec_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mock Chainlink AggregatorV3 feed
contract MockFeed {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public feedDecimals;

    constructor(int256 _answer, uint8 _decimals) {
        answer = _answer;
        updatedAt = block.timestamp;
        feedDecimals = _decimals;
    }

    function setPrice(int256 _answer) external {
        answer = _answer;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _ts) external {
        updatedAt = _ts;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, updatedAt, 1);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST SUITE
// ═══════════════════════════════════════════════════════════════════════════

contract ForexTest is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════

    PriceOracle public oracle;
    ForexPair public forexPair;
    ForexForward public forexForward;

    MockERC20 public eur;
    MockERC20 public usd;
    MockERC20 public gbp;

    MockFeed public eurFeed;
    MockFeed public usdFeed;
    MockFeed public gbpFeed;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ACCOUNTS
    // ═══════════════════════════════════════════════════════════════════════

    address public admin = address(this);
    address public feeReceiver = makeAddr("feeReceiver");
    address public trader1 = makeAddr("trader1");
    address public trader2 = makeAddr("trader2");
    address public keeper = makeAddr("keeper");

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 constant PRECISION = 1e18;
    uint256 constant EUR_USD_RATE = 1.08e18; // EUR/USD = 1.08
    uint256 constant GBP_USD_RATE = 1.27e18; // GBP/USD = 1.27
    uint256 constant USD_USD_RATE = 1e18;    // USD/USD = 1.00

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy mock tokens
        eur = new MockERC20("Euro Token", "EUR", 18);
        usd = new MockERC20("USD Token", "USD", 18);
        gbp = new MockERC20("British Pound", "GBP", 18);

        // Deploy mock feeds (8 decimal Chainlink style)
        eurFeed = new MockFeed(int256(EUR_USD_RATE / 1e10), 8); // 1.08e8
        usdFeed = new MockFeed(int256(USD_USD_RATE / 1e10), 8); // 1.00e8
        gbpFeed = new MockFeed(int256(GBP_USD_RATE / 1e10), 8); // 1.27e8

        // Deploy oracle
        oracle = new PriceOracle(admin);
        oracle.setPriceFeed(address(eur), address(eurFeed), address(0), 1 hours, 8);
        oracle.setPriceFeed(address(usd), address(usdFeed), address(0), 1 hours, 8);
        oracle.setPriceFeed(address(gbp), address(gbpFeed), address(0), 1 hours, 8);

        // Deploy ForexPair
        forexPair = new ForexPair(address(oracle), feeReceiver, admin);

        // Deploy ForexForward
        forexForward = new ForexForward(address(forexPair), address(oracle), feeReceiver, admin);

        // Grant keeper role
        forexForward.grantRole(forexForward.KEEPER_ROLE(), keeper);

        // Mint tokens
        eur.mint(trader1, 1_000_000e18);
        usd.mint(trader1, 1_000_000e18);
        eur.mint(trader2, 1_000_000e18);
        usd.mint(trader2, 1_000_000e18);

        // Fund ForexPair contract with liquidity reserves
        eur.mint(address(forexPair), 10_000_000e18);
        usd.mint(address(forexPair), 10_000_000e18);

        // Approvals
        vm.startPrank(trader1);
        eur.approve(address(forexPair), type(uint256).max);
        usd.approve(address(forexPair), type(uint256).max);
        eur.approve(address(forexForward), type(uint256).max);
        usd.approve(address(forexForward), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(trader2);
        eur.approve(address(forexPair), type(uint256).max);
        usd.approve(address(forexPair), type(uint256).max);
        eur.approve(address(forexForward), type(uint256).max);
        usd.approve(address(forexForward), type(uint256).max);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PRICE ORACLE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Oracle_GetPrice() public view {
        (uint256 price, uint256 ts) = oracle.getPrice(address(eur));
        assertEq(price, EUR_USD_RATE, "EUR price mismatch");
        assertEq(ts, block.timestamp, "Timestamp mismatch");
    }

    function test_Oracle_GetRate_EURUSD() public view {
        (uint256 rate,) = oracle.getRate(address(eur), address(usd));
        // EUR/USD = price(EUR) / price(USD) = 1.08 / 1.00 = 1.08
        assertEq(rate, EUR_USD_RATE, "EUR/USD rate mismatch");
    }

    function test_Oracle_GetRate_CrossRate() public view {
        // EUR/GBP = price(EUR) / price(GBP) = 1.08 / 1.27
        (uint256 rate,) = oracle.getRate(address(eur), address(gbp));
        uint256 expected = (EUR_USD_RATE * PRECISION) / GBP_USD_RATE;
        assertEq(rate, expected, "EUR/GBP cross rate mismatch");
    }

    function test_Oracle_StalePrice_Reverts() public {
        // Make feed stale
        eurFeed.setUpdatedAt(block.timestamp - 2 hours);

        vm.expectRevert();
        oracle.getPriceIfFresh(address(eur), 1 hours);
    }

    function test_Oracle_UnsupportedAsset_Reverts() public {
        address unknown = makeAddr("unknown");
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.AssetNotSupported.selector, unknown));
        oracle.getPrice(unknown);
    }

    function test_Oracle_IsSupported() public view {
        assertTrue(oracle.isSupported(address(eur)));
        assertFalse(oracle.isSupported(address(0xdead)));
    }

    function test_Oracle_FallbackFeed() public {
        // Set up a fallback
        MockFeed fallbackFeed = new MockFeed(int256(EUR_USD_RATE / 1e10), 8);
        oracle.setPriceFeed(address(eur), address(eurFeed), address(fallbackFeed), 1 hours, 8);

        // Make primary stale
        eurFeed.setUpdatedAt(block.timestamp - 2 hours);

        // Should fall back to secondary
        (uint256 price,) = oracle.getPrice(address(eur));
        assertEq(price, EUR_USD_RATE, "Fallback price mismatch");
    }

    function test_Oracle_TWAP() public {
        // Record observations
        oracle.observe(address(eur));

        skip(1 hours);
        eurFeed.setPrice(int256(1.10e8));
        oracle.observe(address(eur));

        skip(1 hours);
        eurFeed.setPrice(int256(1.12e8));
        oracle.observe(address(eur));

        // Get TWAP over 3 hours
        uint256 twap = oracle.getTWAP(address(eur), 3 hours);
        // Should be between 1.08 and 1.12
        assertTrue(twap >= 1.08e18 && twap <= 1.12e18, "TWAP out of range");
    }

    function test_Oracle_SetPriceFeed_OnlyAdmin() public {
        MockFeed newFeed = new MockFeed(1e8, 8);
        vm.prank(trader1);
        vm.expectRevert();
        oracle.setPriceFeed(address(eur), address(newFeed), address(0), 0, 8);
    }

    function test_Oracle_RemovePriceFeed() public {
        oracle.removePriceFeed(address(eur));
        assertFalse(oracle.isSupported(address(eur)));
    }

    function test_Oracle_Pause() public {
        oracle.pause();
        vm.expectRevert();
        oracle.getPrice(address(eur));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FOREX PAIR TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_ForexPair_CreatePair() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        IForexPair.FXPair memory pair = forexPair.getPair(pairId);
        assertEq(pair.base, address(eur));
        assertEq(pair.quote, address(usd));
        assertEq(pair.tickSize, 0.0001e18);
        assertEq(pair.minSize, 100e18);
        assertEq(pair.maxSize, 10_000_000e18);
        assertTrue(pair.active);
    }

    function test_ForexPair_CreatePair_DuplicateReverts() public {
        forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        vm.expectRevert(IForexPair.PairAlreadyExists.selector);
        forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);
    }

    function test_ForexPair_SellBase() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        uint256 sellAmount = 10_000e18; // Sell 10,000 EUR
        uint256 trader1EurBefore = eur.balanceOf(trader1);
        uint256 trader1UsdBefore = usd.balanceOf(trader1);

        vm.prank(trader1);
        uint256 quoteReceived = forexPair.sellBase(pairId, sellAmount, 0);

        // Should receive ~10,800 USD (minus 0.1% fee)
        uint256 grossQuote = (sellAmount * EUR_USD_RATE) / PRECISION;
        uint256 fee = (grossQuote * 10) / 10000;
        uint256 expectedNet = grossQuote - fee;
        assertEq(quoteReceived, expectedNet, "Quote received mismatch");

        assertEq(eur.balanceOf(trader1), trader1EurBefore - sellAmount, "EUR balance wrong");
        assertEq(usd.balanceOf(trader1), trader1UsdBefore + quoteReceived, "USD balance wrong");
    }

    function test_ForexPair_BuyBase() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        uint256 spendAmount = 10_800e18; // Spend 10,800 USD to buy EUR
        uint256 trader1EurBefore = eur.balanceOf(trader1);

        vm.prank(trader1);
        uint256 baseReceived = forexPair.buyBase(pairId, spendAmount, 0);

        // Should receive ~10,000 EUR (minus fee)
        assertTrue(baseReceived > 9_900e18, "Base received too low");
        assertTrue(baseReceived < 10_100e18, "Base received too high");

        assertEq(eur.balanceOf(trader1), trader1EurBefore + baseReceived, "EUR balance wrong");
    }

    function test_ForexPair_SlippageProtection() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        vm.prank(trader1);
        vm.expectRevert(IForexPair.SlippageExceeded.selector);
        forexPair.sellBase(pairId, 10_000e18, 20_000e18); // minQuote too high
    }

    function test_ForexPair_MinSizeReverts() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        vm.prank(trader1);
        vm.expectRevert(IForexPair.BelowMinSize.selector);
        forexPair.sellBase(pairId, 50e18, 0); // Below 100 EUR minimum
    }

    function test_ForexPair_MaxSizeReverts() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 1_000e18);

        vm.prank(trader1);
        vm.expectRevert(IForexPair.AboveMaxSize.selector);
        forexPair.sellBase(pairId, 2_000e18, 0); // Above 1,000 EUR maximum
    }

    function test_ForexPair_InactivePairReverts() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);
        forexPair.updatePair(pairId, 0.0001e18, 100e18, 10_000_000e18, false);

        vm.prank(trader1);
        vm.expectRevert(IForexPair.PairNotActive.selector);
        forexPair.sellBase(pairId, 1_000e18, 0);
    }

    function test_ForexPair_ZeroAmountReverts() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        vm.prank(trader1);
        vm.expectRevert(IForexPair.ZeroAmount.selector);
        forexPair.sellBase(pairId, 0, 0);
    }

    function test_ForexPair_FeeCollected() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        uint256 feeReceiverBefore = usd.balanceOf(feeReceiver);

        vm.prank(trader1);
        forexPair.sellBase(pairId, 10_000e18, 0);

        uint256 feeCollected = usd.balanceOf(feeReceiver) - feeReceiverBefore;
        assertTrue(feeCollected > 0, "No fee collected");

        // Fee = (10000 * 1.08) * 0.001 = ~10.8 USD
        uint256 expectedFee = ((10_000e18 * EUR_USD_RATE) / PRECISION * 10) / 10000;
        assertEq(feeCollected, expectedFee, "Fee amount wrong");
    }

    function test_ForexPair_GetRate() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        (uint256 rate,) = forexPair.getRate(pairId);
        assertEq(rate, EUR_USD_RATE, "Rate mismatch");
    }

    function test_ForexPair_GetPairId() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        uint256 foundId = forexPair.getPairId(address(eur), address(usd));
        assertEq(foundId, pairId, "Pair ID lookup mismatch");
    }

    function test_ForexPair_Paused() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);
        forexPair.pause();

        vm.prank(trader1);
        vm.expectRevert();
        forexPair.sellBase(pairId, 1_000e18, 0);
    }

    function test_ForexPair_UpdatePair() public {
        uint256 pairId = forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);

        forexPair.updatePair(pairId, 0.001e18, 500e18, 5_000_000e18, true);

        IForexPair.FXPair memory pair = forexPair.getPair(pairId);
        assertEq(pair.tickSize, 0.001e18);
        assertEq(pair.minSize, 500e18);
        assertEq(pair.maxSize, 5_000_000e18);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FOREX FORWARD TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function _createEurUsdPair() internal returns (uint256) {
        return forexPair.createPair(address(eur), address(usd), 0.0001e18, 100e18, 10_000_000e18);
    }

    function test_Forward_Create() public {
        uint256 pairId = _createEurUsdPair();

        uint256 forwardRate = 1.10e18; // Agreed rate: 1 EUR = 1.10 USD
        uint256 baseAmount = 100_000e18; // 100,000 EUR notional
        uint256 maturity = block.timestamp + 30 days;

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, forwardRate, baseAmount, maturity);

        IForexForward.Forward memory fwd = forexForward.getForward(forwardId);
        assertEq(fwd.pairId, pairId);
        assertEq(fwd.buyer, trader1);
        assertEq(fwd.seller, address(0));
        assertEq(fwd.rate, forwardRate);
        assertEq(fwd.baseAmount, baseAmount);
        assertEq(fwd.maturityDate, maturity);
        assertEq(uint256(fwd.status), uint256(IForexForward.ForwardStatus.OPEN));

        // Buyer collateral = 100,000 * 1.10 * 100% = 110,000 USD
        assertEq(fwd.buyerCollateral, 110_000e18, "Buyer collateral mismatch");
    }

    function test_Forward_Accept() public {
        uint256 pairId = _createEurUsdPair();

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        forexForward.acceptForward(forwardId);

        IForexForward.Forward memory fwd = forexForward.getForward(forwardId);
        assertEq(fwd.seller, trader2);
        assertEq(uint256(fwd.status), uint256(IForexForward.ForwardStatus.ACTIVE));
        // Seller collateral = 100,000 EUR * 100% = 100,000 EUR
        assertEq(fwd.sellerCollateral, 100_000e18, "Seller collateral mismatch");
    }

    function test_Forward_Settle_BuyerProfits() public {
        uint256 pairId = _createEurUsdPair();

        // Lock rate at 1.10 EUR/USD
        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        forexForward.acceptForward(forwardId);

        // Move EUR price up to 1.15 (buyer locked cheaper at 1.10)
        eurFeed.setPrice(int256(1.15e8));

        uint256 buyer1UsdBefore = usd.balanceOf(trader1);

        // Warp to maturity
        skip(30 days);

        vm.prank(keeper);
        forexForward.settleForward(forwardId);

        IForexForward.Forward memory fwd = forexForward.getForward(forwardId);
        assertEq(uint256(fwd.status), uint256(IForexForward.ForwardStatus.SETTLED));

        // Buyer should profit: got collateral back + PnL
        uint256 buyer1UsdAfter = usd.balanceOf(trader1);
        assertTrue(buyer1UsdAfter > buyer1UsdBefore, "Buyer should have profited");
    }

    function test_Forward_Settle_SellerProfits() public {
        uint256 pairId = _createEurUsdPair();

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        forexForward.acceptForward(forwardId);

        // Move EUR price down to 1.05 (seller benefits — buyer locked expensive at 1.10)
        eurFeed.setPrice(int256(1.05e8));

        uint256 seller2UsdBefore = usd.balanceOf(trader2);

        skip(30 days);

        vm.prank(keeper);
        forexForward.settleForward(forwardId);

        // Seller should profit
        uint256 seller2UsdAfter = usd.balanceOf(trader2);
        assertTrue(seller2UsdAfter > seller2UsdBefore, "Seller should have profited");
    }

    function test_Forward_Cancel() public {
        uint256 pairId = _createEurUsdPair();

        uint256 buyerBefore = usd.balanceOf(trader1);

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        uint256 buyerAfterCreate = usd.balanceOf(trader1);
        assertTrue(buyerAfterCreate < buyerBefore, "Collateral should be deducted");

        vm.prank(trader1);
        forexForward.cancelForward(forwardId);

        uint256 buyerAfterCancel = usd.balanceOf(trader1);
        assertEq(buyerAfterCancel, buyerBefore, "Collateral should be returned");

        IForexForward.Forward memory fwd = forexForward.getForward(forwardId);
        assertEq(uint256(fwd.status), uint256(IForexForward.ForwardStatus.CANCELLED));
    }

    function test_Forward_CancelByNonBuyer_Reverts() public {
        uint256 pairId = _createEurUsdPair();

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        vm.expectRevert(IForexForward.NotParty.selector);
        forexForward.cancelForward(forwardId);
    }

    function test_Forward_SettleBeforeMaturity_NonKeeper_Reverts() public {
        uint256 pairId = _createEurUsdPair();

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        forexForward.acceptForward(forwardId);

        // Try to settle before maturity as non-keeper
        vm.prank(trader1);
        vm.expectRevert();
        forexForward.settleForward(forwardId);
    }

    function test_Forward_InvalidMaturity_Reverts() public {
        uint256 pairId = _createEurUsdPair();

        // Maturity too soon
        vm.prank(trader1);
        vm.expectRevert(IForexForward.InvalidMaturityDate.selector);
        forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 minutes);
    }

    function test_Forward_TopUpCollateral() public {
        uint256 pairId = _createEurUsdPair();

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        forexForward.acceptForward(forwardId);

        uint256 topUpAmount = 10_000e18;

        vm.prank(trader1);
        forexForward.topUpCollateral(forwardId, topUpAmount);

        IForexForward.Forward memory fwd = forexForward.getForward(forwardId);
        assertEq(fwd.buyerCollateral, 110_000e18 + topUpAmount, "Buyer collateral should increase");
    }

    function test_Forward_MarkToMarket() public {
        uint256 pairId = _createEurUsdPair();

        vm.prank(trader1);
        uint256 forwardId =
            forexForward.createForward(pairId, 1.10e18, 100_000e18, block.timestamp + 30 days);

        vm.prank(trader2);
        forexForward.acceptForward(forwardId);

        // EUR goes up to 1.15
        eurFeed.setPrice(int256(1.15e8));

        (int256 buyerPnl, int256 sellerPnl) = forexForward.getMarkToMarket(forwardId);
        assertTrue(buyerPnl > 0, "Buyer should be in profit");
        assertTrue(sellerPnl < 0, "Seller should be in loss");
        assertEq(buyerPnl + sellerPnl, 0, "PnL should be zero sum");
    }

    function test_Forward_BatchSettle() public {
        uint256 pairId = _createEurUsdPair();

        // Create and activate two forwards
        vm.prank(trader1);
        uint256 fwd1 = forexForward.createForward(pairId, 1.10e18, 10_000e18, block.timestamp + 30 days);
        vm.prank(trader2);
        forexForward.acceptForward(fwd1);

        vm.prank(trader1);
        uint256 fwd2 = forexForward.createForward(pairId, 1.12e18, 5_000e18, block.timestamp + 30 days);
        vm.prank(trader2);
        forexForward.acceptForward(fwd2);

        // Warp to maturity
        skip(30 days);

        uint256[] memory ids = new uint256[](2);
        ids[0] = fwd1;
        ids[1] = fwd2;

        vm.prank(keeper);
        forexForward.batchSettle(ids);

        assertEq(
            uint256(forexForward.getForward(fwd1).status),
            uint256(IForexForward.ForwardStatus.SETTLED),
            "Forward 1 not settled"
        );
        assertEq(
            uint256(forexForward.getForward(fwd2).status),
            uint256(IForexForward.ForwardStatus.SETTLED),
            "Forward 2 not settled"
        );
    }
}
