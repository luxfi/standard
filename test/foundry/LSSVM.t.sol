// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// LSSVM Contracts
import {LSSVMPairFactory} from "../../contracts/lssvm/LSSVMPairFactory.sol";
import {LSSVMPair} from "../../contracts/lssvm/LSSVMPair.sol";
import {LSSVMRouter} from "../../contracts/lssvm/LSSVMRouter.sol";
import {LinearCurve} from "../../contracts/lssvm/LinearCurve.sol";
import {ExponentialCurve} from "../../contracts/lssvm/ExponentialCurve.sol";
import {ICurve} from "../../contracts/lssvm/ICurve.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LSSVM Test Suite
/// @notice Comprehensive tests for Sudoswap-style NFT AMM
/// @dev Tests all bonding curves, pool types, and edge cases
contract LSSVMTest is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════

    LSSVMPairFactory public factory;
    LSSVMRouter public router;
    LinearCurve public linearCurve;
    ExponentialCurve public exponentialCurve;
    MockNFT public nft;
    MockERC20 public token;

    // ═══════════════════════════════════════════════════════════════════════
    // TEST ACCOUNTS
    // ═══════════════════════════════════════════════════════════════════════

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public protocolFeeRecipient = makeAddr("protocolFee");

    // ═══════════════════════════════════════════════════════════════════════
    // TEST CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint128 public constant INITIAL_SPOT_PRICE = 1 ether;
    uint128 public constant LINEAR_DELTA = 0.1 ether; // +0.1 ETH per item
    uint128 public constant EXPONENTIAL_DELTA = 1.1e18; // 10% increase per item
    uint96 public constant POOL_FEE = 500; // 5%
    uint256 public constant PROTOCOL_FEE = 50; // 0.5%

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy contracts
        factory = new LSSVMPairFactory(protocolFeeRecipient);
        router = new LSSVMRouter();
        linearCurve = new LinearCurve();
        exponentialCurve = new ExponentialCurve();
        nft = new MockNFT("Test NFT", "TNFT");
        token = new MockERC20("Test Token", "TT");

        // Configure factory
        factory.setBondingCurveAllowed(address(linearCurve), true);
        factory.setBondingCurveAllowed(address(exponentialCurve), true);
        factory.setProtocolFeeMultiplier(PROTOCOL_FEE);

        // Setup test accounts with tokens and NFTs
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);

        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(carol, 1000 ether);

        // Mint NFTs (IDs 1-100) to alice
        for (uint256 i = 1; i <= 100; i++) {
            nft.mint(alice, i);
        }

        // Label addresses for better traces
        vm.label(address(factory), "Factory");
        vm.label(address(router), "Router");
        vm.label(address(linearCurve), "LinearCurve");
        vm.label(address(exponentialCurve), "ExponentialCurve");
        vm.label(address(nft), "NFT");
        vm.label(address(token), "Token");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FACTORY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_CreatePairETH() public {
        vm.startPrank(alice);

        // Approve NFTs
        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        // Create TOKEN pool (buys NFTs)
        address pair = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0), // ETH pool
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );

        vm.stopPrank();

        // Verify pair state
        LSSVMPair pairContract = LSSVMPair(payable(pair));
        assertEq(pairContract.owner(), alice);
        assertEq(address(pairContract.nft()), address(nft));
        assertEq(address(pairContract.bondingCurve()), address(linearCurve));
        assertEq(pairContract.token(), address(0));
        assertEq(uint256(pairContract.poolType()), uint256(LSSVMPair.PoolType.TOKEN));
        assertEq(pairContract.spotPrice(), INITIAL_SPOT_PRICE);
        assertEq(pairContract.delta(), LINEAR_DELTA);
        assertEq(pairContract.fee(), POOL_FEE);
        assertEq(address(pair).balance, 10 ether);

        // Verify NFTs were deposited
        uint256[] memory heldIds = pairContract.getAllHeldIds();
        assertEq(heldIds.length, 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(nft.ownerOf(i + 1), pair);
        }
    }

    function test_CreatePairERC20() public {
        vm.startPrank(alice);

        uint256[] memory nftIds = new uint256[](0);

        // Create NFT pool (sells NFTs)
        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(token),
            LSSVMPair.PoolType.NFT,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            0, // No fee for NFT pools
            alice,
            nftIds
        );

        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));
        assertEq(pairContract.token(), address(token));
        assertEq(uint256(pairContract.poolType()), uint256(LSSVMPair.PoolType.NFT));
    }

    function test_CreateTradePair() public {
        vm.startPrank(alice);

        uint256[] memory nftIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 5 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TRADE,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            carol, // Different asset recipient
            nftIds
        );

        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));
        assertEq(uint256(pairContract.poolType()), uint256(LSSVMPair.PoolType.TRADE));
        assertEq(pairContract.assetRecipient(), carol);
    }

    function test_RevertCreatePairInvalidCurve() public {
        uint256[] memory nftIds = new uint256[](0);

        vm.expectRevert(LSSVMPairFactory.InvalidCurve.selector);
        factory.createPair(
            address(nft),
            makeAddr("fakeCurve"), // Invalid curve
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LINEAR CURVE - BUY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_BuyFromLinearPool() public {
        // Create pool with 10 NFTs
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 20 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        // Bob buys 3 NFTs
        vm.startPrank(bob);
        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint256[] memory buyIds = new uint256[](3);
        buyIds[0] = 1;
        buyIds[1] = 2;
        buyIds[2] = 3;

        // Get quote
        (,, uint256 cost,,) = pairContract.getBuyNFTQuote(3);

        // Execute buy
        uint256 bobBalanceBefore = bob.balance;
        pairContract.swapTokenForNFTs{value: cost}(buyIds, cost, bob);

        // Verify results
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.ownerOf(2), bob);
        assertEq(nft.ownerOf(3), bob);
        assertEq(bob.balance, bobBalanceBefore - cost);

        // Verify price increased
        assertGt(pairContract.spotPrice(), INITIAL_SPOT_PRICE);

        vm.stopPrank();
    }

    function test_LinearCurvePricing() public {
        // Test linear curve math directly
        (uint128 newSpot, uint128 newDelta, uint256 inputValue,,) =
            linearCurve.getBuyInfo(INITIAL_SPOT_PRICE, LINEAR_DELTA, 3, POOL_FEE, PROTOCOL_FEE);

        // Verify spot price increased by 3 * delta
        assertEq(newSpot, INITIAL_SPOT_PRICE + 3 * LINEAR_DELTA);
        assertEq(newDelta, LINEAR_DELTA);

        // Calculate expected input: (1.1 + 1.2 + 1.3) ETH + fees
        // = 3.6 ETH base + 5.5% fees = 3.798 ETH
        uint256 expectedBase = uint256(INITIAL_SPOT_PRICE + LINEAR_DELTA) * 3
            + (LINEAR_DELTA * 3 * 2) / 2; // Geometric sum
        uint256 expectedFees = (expectedBase * (POOL_FEE + PROTOCOL_FEE)) / 10000;
        assertEq(inputValue, expectedBase + expectedFees);
    }

    function test_BuyMultipleTimesLinear() public {
        // Create pool
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 50 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));
        uint128 spotPriceBefore = pairContract.spotPrice();

        // Buy 2 NFTs
        vm.startPrank(bob);
        uint256[] memory buy1 = new uint256[](2);
        buy1[0] = 1;
        buy1[1] = 2;
        (,, uint256 cost1,,) = pairContract.getBuyNFTQuote(2);
        pairContract.swapTokenForNFTs{value: cost1}(buy1, cost1, bob);

        uint128 spotPriceAfter1 = pairContract.spotPrice();
        assertEq(spotPriceAfter1, spotPriceBefore + 2 * LINEAR_DELTA);

        // Buy 2 more NFTs
        uint256[] memory buy2 = new uint256[](2);
        buy2[0] = 3;
        buy2[1] = 4;
        (,, uint256 cost2,,) = pairContract.getBuyNFTQuote(2);
        pairContract.swapTokenForNFTs{value: cost2}(buy2, cost2, bob);

        uint128 spotPriceAfter2 = pairContract.spotPrice();
        assertEq(spotPriceAfter2, spotPriceAfter1 + 2 * LINEAR_DELTA);

        // Second buy should be more expensive
        assertGt(cost2, cost1);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LINEAR CURVE - SELL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_SellToLinearPool() public {
        // Create NFT pool that buys NFTs
        vm.startPrank(alice);
        uint256[] memory emptyIds = new uint256[](0);
        token.approve(address(factory), type(uint256).max);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(token),
            LSSVMPair.PoolType.NFT,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            0, // No fee for NFT pools
            alice,
            emptyIds
        );

        // Deposit tokens to pool
        LSSVMPair pairContract = LSSVMPair(payable(pair));
        token.transfer(pair, 100 ether);
        vm.stopPrank();

        // Bob sells 3 NFTs
        vm.startPrank(bob);
        // Mint NFTs to bob
        nft.mint(bob, 101);
        nft.mint(bob, 102);
        nft.mint(bob, 103);

        uint256[] memory sellIds = new uint256[](3);
        sellIds[0] = 101;
        sellIds[1] = 102;
        sellIds[2] = 103;

        for (uint256 i = 0; i < 3; i++) {
            nft.approve(address(pairContract), sellIds[i]);
        }

        // Get quote
        (,, uint256 payout,,) = pairContract.getSellNFTQuote(3);

        uint256 bobTokenBefore = token.balanceOf(bob);
        pairContract.swapNFTsForToken(sellIds, payout, bob);

        // Verify results
        assertEq(nft.ownerOf(101), pair);
        assertEq(nft.ownerOf(102), pair);
        assertEq(nft.ownerOf(103), pair);
        assertEq(token.balanceOf(bob), bobTokenBefore + payout);

        // Verify price decreased
        assertLt(pairContract.spotPrice(), INITIAL_SPOT_PRICE);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXPONENTIAL CURVE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_BuyFromExponentialPool() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 50 ether}(
            address(nft),
            address(exponentialCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            EXPONENTIAL_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        // Bob buys 3 NFTs
        vm.startPrank(bob);
        uint256[] memory buyIds = new uint256[](3);
        buyIds[0] = 1;
        buyIds[1] = 2;
        buyIds[2] = 3;

        (,, uint256 cost,,) = pairContract.getBuyNFTQuote(3);
        pairContract.swapTokenForNFTs{value: cost}(buyIds, cost, bob);

        // Verify exponential growth (each NFT is 10% more expensive)
        // New spot should be INITIAL_SPOT_PRICE * 1.1^3
        uint128 expectedSpot = uint128((uint256(INITIAL_SPOT_PRICE) * 1331) / 1000); // 1.1^3 = 1.331
        assertApproxEqRel(pairContract.spotPrice(), expectedSpot, 0.01e18); // 1% tolerance

        vm.stopPrank();
    }

    function test_ExponentialCurvePricing() public {
        (uint128 newSpot,, uint256 inputValue,,) =
            exponentialCurve.getBuyInfo(INITIAL_SPOT_PRICE, EXPONENTIAL_DELTA, 3, POOL_FEE, PROTOCOL_FEE);

        // Verify exponential growth: price * 1.1^3
        uint256 expectedSpot = (uint256(INITIAL_SPOT_PRICE) * 1331) / 1000; // 1.1^3
        assertApproxEqRel(newSpot, expectedSpot, 0.01e18);

        // Cost should be geometric series: p*1.1 + p*1.1^2 + p*1.1^3 + fees
        uint256 expectedBase =
            (uint256(INITIAL_SPOT_PRICE) * (1100 + 1210 + 1331)) / 1000;
        assertLt(inputValue, expectedBase * 12 / 10); // Should be < base + 20% fees
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADE POOL TESTS (TWO-SIDED)
    // ═══════════════════════════════════════════════════════════════════════

    function test_TradePairBuyAndSell() public {
        // Create two-sided pool
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 20 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TRADE,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            carol, // Fees go to carol
            nftIds
        );
        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        // Bob buys 2 NFTs
        vm.startPrank(bob);
        uint256[] memory buyIds = new uint256[](2);
        buyIds[0] = 1;
        buyIds[1] = 2;
        (,, uint256 buyCost, uint256 buyFee,) = pairContract.getBuyNFTQuote(2);

        uint256 carolBalanceBefore = carol.balance;
        pairContract.swapTokenForNFTs{value: buyCost}(buyIds, buyCost, bob);

        // Verify carol received trade fee
        assertEq(carol.balance, carolBalanceBefore + buyFee);
        vm.stopPrank();

        // Bob sells 1 NFT back
        vm.startPrank(bob);
        uint256[] memory sellIds = new uint256[](1);
        sellIds[0] = 1;
        nft.approve(address(pairContract), 1);

        carolBalanceBefore = carol.balance;
        (,, uint256 sellPayout, uint256 sellFee,) = pairContract.getSellNFTQuote(1);
        pairContract.swapNFTsForToken(sellIds, sellPayout, bob);

        // Verify carol received sell fee too
        assertEq(carol.balance, carolBalanceBefore + sellFee);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROUTER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_RouterMultiPairBuy() public {
        // Create two pools
        vm.startPrank(alice);

        // Pool 1
        uint256[] memory nfts1 = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nfts1[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }
        address pair1 = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nfts1
        );

        // Pool 2
        uint256[] memory nfts2 = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nfts2[i] = i + 6;
            nft.approve(address(factory), i + 6);
        }
        address pair2 = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nfts2
        );
        vm.stopPrank();

        // Bob buys from both pools via router
        vm.startPrank(bob);

        LSSVMRouter.PairSwapSpecific[] memory swaps = new LSSVMRouter.PairSwapSpecific[](2);

        // Swap 1: Buy NFT 1 from pool 1
        swaps[0].pair = LSSVMPair(payable(pair1));
        swaps[0].nftIds = new uint256[](1);
        swaps[0].nftIds[0] = 1;

        // Swap 2: Buy NFT 6 from pool 2
        swaps[1].pair = LSSVMPair(payable(pair2));
        swaps[1].nftIds = new uint256[](1);
        swaps[1].nftIds[0] = 6;

        uint256 totalCost = router.swapTokenForSpecificNFTs{value: 10 ether}(
            swaps, 10 ether, bob, block.timestamp + 100
        );

        // Verify Bob owns both NFTs
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.ownerOf(6), bob);
        assertLt(totalCost, 10 ether);

        vm.stopPrank();
    }

    function test_RouterMultiPairSell() public {
        // Create two NFT pools
        vm.startPrank(alice);
        uint256[] memory emptyIds = new uint256[](0);

        address pair1 = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.NFT,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            0,
            alice,
            emptyIds
        );

        address pair2 = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.NFT,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            0,
            alice,
            emptyIds
        );
        vm.stopPrank();

        // Mint NFTs to bob
        nft.mint(bob, 101);
        nft.mint(bob, 102);

        // Bob sells to both pools via router
        vm.startPrank(bob);
        nft.approve(address(router), 101);
        nft.approve(address(router), 102);

        LSSVMRouter.PairSwapSell[] memory swaps = new LSSVMRouter.PairSwapSell[](2);

        swaps[0].pair = LSSVMPair(payable(pair1));
        swaps[0].nftIds = new uint256[](1);
        swaps[0].nftIds[0] = 101;
        swaps[0].minOutput = 0;

        swaps[1].pair = LSSVMPair(payable(pair2));
        swaps[1].nftIds = new uint256[](1);
        swaps[1].nftIds[0] = 102;
        swaps[1].minOutput = 0;

        uint256 bobBalanceBefore = bob.balance;
        uint256 totalOutput = router.swapNFTsForToken(swaps, 0, bob, block.timestamp + 100);

        assertEq(bob.balance, bobBalanceBefore + totalOutput);
        assertEq(nft.ownerOf(101), pair1);
        assertEq(nft.ownerOf(102), pair2);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDITY MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_DepositWithdrawTokens() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair{value: 5 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        // Deposit more ETH
        pairContract.depositTokens{value: 3 ether}(3 ether);
        assertEq(address(pair).balance, 8 ether);

        // Withdraw ETH
        uint256 aliceBalanceBefore = alice.balance;
        pairContract.withdrawTokens(2 ether);
        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertEq(address(pair).balance, 6 ether);

        vm.stopPrank();
    }

    function test_DepositWithdrawNFTs() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.NFT,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            0,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        // Deposit NFTs
        uint256[] memory depositIds = new uint256[](3);
        depositIds[0] = 1;
        depositIds[1] = 2;
        depositIds[2] = 3;
        for (uint256 i = 0; i < 3; i++) {
            nft.approve(address(pairContract), depositIds[i]);
        }
        pairContract.depositNFTs(depositIds);

        uint256[] memory heldIds = pairContract.getAllHeldIds();
        assertEq(heldIds.length, 3);

        // Withdraw NFTs
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = 1;
        withdrawIds[1] = 2;
        pairContract.withdrawNFTs(withdrawIds);

        heldIds = pairContract.getAllHeldIds();
        assertEq(heldIds.length, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), alice);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PARAMETER UPDATE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_UpdateSpotPrice() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint128 newSpotPrice = 2 ether;
        pairContract.setSpotPrice(newSpotPrice);
        assertEq(pairContract.spotPrice(), newSpotPrice);

        vm.stopPrank();
    }

    function test_UpdateDelta() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint128 newDelta = 0.2 ether;
        pairContract.setDelta(newDelta);
        assertEq(pairContract.delta(), newDelta);

        vm.stopPrank();
    }

    function test_UpdateFee() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TRADE,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint96 newFee = 1000; // 10%
        pairContract.setFee(newFee);
        assertEq(pairContract.fee(), newFee);

        vm.stopPrank();
    }

    function test_RevertUpdateFeeInvalid() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TRADE,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        vm.expectRevert(LSSVMPair.InvalidFee.selector);
        pairContract.setFee(9001); // > 90%

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_BuyFromEmptyPool() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        // Try to buy from empty pool - should fail on NFT transfer
        vm.startPrank(bob);
        LSSVMPair pairContract = LSSVMPair(payable(pair));
        uint256[] memory buyIds = new uint256[](1);
        buyIds[0] = 999; // NFT not in pool

        vm.expectRevert(); // Should revert on NFT transfer
        pairContract.swapTokenForNFTs{value: 10 ether}(buyIds, 10 ether, bob);
        vm.stopPrank();
    }

    function test_SellToPoolInsufficientLiquidity() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        // Pool with only 0.5 ETH - not enough to pay for 1 NFT at spotPrice 1 ETH
        // Selling 1 NFT: outputAmount = 0.995 ETH + protocolFee 0.005 ETH = 1 ETH needed
        address pair = factory.createPair{value: 0.5 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.NFT,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            0,
            alice,
            nftIds
        );
        vm.stopPrank();

        // Try to sell NFT worth ~1 ETH when pool only has 0.5 ETH
        nft.mint(bob, 101);
        vm.startPrank(bob);
        nft.approve(address(pair), 101);

        uint256[] memory sellIds = new uint256[](1);
        sellIds[0] = 101;

        LSSVMPair pairContract = LSSVMPair(payable(pair));
        vm.expectRevert(LSSVMPair.InsufficientLiquidity.selector);
        pairContract.swapNFTsForToken(sellIds, 0, bob);
        vm.stopPrank();
    }

    function test_SlippageProtection() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        vm.startPrank(bob);
        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint256[] memory buyIds = new uint256[](1);
        buyIds[0] = 1;

        // Set maxInput too low
        vm.expectRevert(LSSVMPair.SlippageExceeded.selector);
        pairContract.swapTokenForNFTs{value: 10 ether}(buyIds, 0.1 ether, bob);

        vm.stopPrank();
    }

    function test_ProtocolFeeCollection() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        vm.startPrank(bob);
        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint256[] memory buyIds = new uint256[](1);
        buyIds[0] = 1;

        (,, uint256 cost,, uint256 protocolFee) = pairContract.getBuyNFTQuote(1);

        uint256 recipientBalanceBefore = protocolFeeRecipient.balance;
        pairContract.swapTokenForNFTs{value: cost}(buyIds, cost, bob);

        // Verify protocol fee was sent
        assertEq(protocolFeeRecipient.balance, recipientBalanceBefore + protocolFee);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_LinearBuyAmount(uint8 numItems) public {
        vm.assume(numItems > 0 && numItems <= 10);

        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            nftIds[i] = i + 1;
            nft.approve(address(factory), i + 1);
        }

        address pair = factory.createPair{value: 50 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        vm.startPrank(bob);
        LSSVMPair pairContract = LSSVMPair(payable(pair));

        uint256[] memory buyIds = new uint256[](numItems);
        for (uint256 i = 0; i < numItems; i++) {
            buyIds[i] = i + 1;
        }

        (,, uint256 cost,,) = pairContract.getBuyNFTQuote(numItems);
        pairContract.swapTokenForNFTs{value: cost}(buyIds, cost, bob);

        // Verify bob owns all NFTs
        for (uint256 i = 0; i < numItems; i++) {
            assertEq(nft.ownerOf(i + 1), bob);
        }

        vm.stopPrank();
    }

    function testFuzz_ExponentialSpotPrice(uint128 spotPrice) public {
        vm.assume(spotPrice >= 1 gwei && spotPrice <= 1000 ether);

        (uint128 newSpot,,,,) =
            exponentialCurve.getBuyInfo(spotPrice, EXPONENTIAL_DELTA, 1, POOL_FEE, PROTOCOL_FEE);

        // Verify exponential growth
        uint256 expectedSpot = (uint256(spotPrice) * EXPONENTIAL_DELTA) / 1e18;
        assertApproxEqRel(newSpot, expectedSpot, 0.01e18);
    }

    function testFuzz_LinearSpotPrice(uint128 spotPrice, uint128 delta) public {
        vm.assume(spotPrice > 0 && spotPrice < type(uint128).max / 2);
        vm.assume(delta > 0 && delta < type(uint128).max / 20);

        (uint128 newSpot,,,,) = linearCurve.getBuyInfo(spotPrice, delta, 1, POOL_FEE, PROTOCOL_FEE);

        // Linear: new = old + delta
        assertEq(newSpot, spotPrice + delta);
    }

    function testFuzz_PoolFee(uint96 fee) public {
        vm.assume(fee <= 9000); // Max 90%

        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TRADE,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            fee,
            alice,
            nftIds
        );

        LSSVMPair pairContract = LSSVMPair(payable(pair));
        assertEq(pairContract.fee(), fee);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUTHORIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_OnlyOwnerCanUpdateParameters() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        // Bob tries to update (should fail)
        vm.startPrank(bob);
        vm.expectRevert(LSSVMPair.Unauthorized.selector);
        pairContract.setSpotPrice(2 ether);

        vm.expectRevert(LSSVMPair.Unauthorized.selector);
        pairContract.setDelta(0.2 ether);

        vm.expectRevert(LSSVMPair.Unauthorized.selector);
        pairContract.setFee(1000);
        vm.stopPrank();
    }

    function test_OnlyOwnerCanDepositWithdraw() public {
        vm.startPrank(alice);
        uint256[] memory nftIds = new uint256[](0);

        address pair = factory.createPair{value: 10 ether}(
            address(nft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TOKEN,
            INITIAL_SPOT_PRICE,
            LINEAR_DELTA,
            POOL_FEE,
            alice,
            nftIds
        );
        vm.stopPrank();

        LSSVMPair pairContract = LSSVMPair(payable(pair));

        // Bob tries to withdraw (should fail)
        vm.startPrank(bob);
        vm.expectRevert(LSSVMPair.Unauthorized.selector);
        pairContract.withdrawTokens(1 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_FactoryUpdateProtocolFee() public {
        uint256 newFee = 100; // 1%
        factory.setProtocolFeeMultiplier(newFee);
        assertEq(factory.protocolFeeMultiplier(), newFee);
    }

    function test_FactoryEnableDisableCurve() public {
        address newCurve = makeAddr("newCurve");

        factory.setBondingCurveAllowed(newCurve, true);
        assertTrue(factory.bondingCurveAllowed(newCurve));

        factory.setBondingCurveAllowed(newCurve, false);
        assertFalse(factory.bondingCurveAllowed(newCurve));
    }

    function test_FactoryUpdateFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        factory.setProtocolFeeRecipient(newRecipient);
        assertEq(factory.protocolFeeRecipient(), newRecipient);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MOCK CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

contract MockNFT is ERC721 {
    uint256 private _nextTokenId = 1;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
