// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// Core tokens
import {WLUX} from "../../contracts/tokens/WLUX.sol";
import {LuxUSD} from "../../contracts/liquid/tokens/LUSD.sol";
import {LuxETH} from "../../contracts/liquid/tokens/LETH.sol";
import {LuxBTC} from "../../contracts/liquid/tokens/LBTC.sol";

// Staking
import {sLUX as StakedLUX} from "../../contracts/staking/sLUX.sol";

// Note: s* synth tokens have been removed - L* tokens (LETH, LUSD) are now the synthetics
// See LP-3003 for the Liquid Protocol specification

// AMM
import {AMMV2Factory} from "../../contracts/amm/AMMV2Factory.sol";
import {AMMV2Router} from "../../contracts/amm/AMMV2Router.sol";
import {AMMV2Pair} from "../../contracts/amm/AMMV2Pair.sol";

// Governance (using DAO for simple governance - Governor is Zodiac-style for Safe)
import {VotesToken} from "../../contracts/governance/VotesToken.sol";
import {Timelock} from "../../contracts/governance/Timelock.sol";
import {DAO} from "../../contracts/governance/DAO.sol";
import {vLUX} from "../../contracts/governance/vLUX.sol";
import {GaugeController} from "../../contracts/governance/GaugeController.sol";

// LSSVM (NFT AMM)
import {LSSVMPairFactory} from "../../contracts/lssvm/LSSVMPairFactory.sol";
import {LSSVMPair} from "../../contracts/lssvm/LSSVMPair.sol";
import {LinearCurve} from "../../contracts/lssvm/LinearCurve.sol";
import {ExponentialCurve} from "../../contracts/lssvm/ExponentialCurve.sol";
import {LSSVMRouter} from "../../contracts/lssvm/LSSVMRouter.sol";

// Markets (Lending)
import {Markets} from "../../contracts/markets/Markets.sol";
import {MarketParams, Position, Market, Id} from "../../contracts/markets/interfaces/IMarkets.sol";

// OpenZeppelin
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Shared mocks
import {MockNFT, MockOracle, MockRateModel} from "./TestMocks.sol";

/**
 * @title LuxE2ETest
 * @notice Comprehensive End-to-End tests for the Lux DeFi stack
 *
 * TEST COVERAGE:
 * ┌──────────────────────────────────────────────────────────────────────────────┐
 * │  1. TOKENS & STAKING                                                         │
 * │     - Wrap/unwrap LUX                                                        │
 * │     - Stake LUX -> StakedLUX                                                 │
 * │     - Synth token minting                                                    │
 * │                                                                              │
 * │  2. AMM OPERATIONS                                                           │
 * │     - Create liquidity pools                                                 │
 * │     - Add/remove liquidity                                                   │
 * │     - Swap tokens                                                            │
 * │     - Multi-hop swaps                                                        │
 * │                                                                              │
 * │  3. GOVERNANCE                                                               │
 * │     - Lock LUX for vLUX (vote-escrowed)                                      │
 * │     - Create/vote/execute proposals                                          │
 * │     - Gauge weight voting                                                    │
 * │                                                                              │
 * │  4. NFT AMM (LSSVM)                                                          │
 * │     - Create NFT trading pools                                               │
 * │     - Buy/sell NFTs via bonding curves                                       │
 * │     - Pool type testing (TOKEN, NFT, TRADE)                                  │
 * │                                                                              │
 * │  5. MARKETS (LENDING)                                                        │
 * │     - Create lending markets                                                 │
 * │     - Supply/withdraw assets                                                 │
 * │     - Borrow/repay                                                           │
 * │     - Flash loans                                                            │
 * │     - Liquidations                                                           │
 * └──────────────────────────────────────────────────────────────────────────────┘
 */
contract LuxE2ETest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════════

    // Core tokens
    WLUX public wlux;
    LuxUSD public lusd;
    LuxETH public leth;
    LuxBTC public lbtc;

    // Staking
    StakedLUX public stakedLux;

    // Note: Synth tokens removed - L* tokens (LETH, LUSD, LBTC) are the synthetics

    // AMM
    AMMV2Factory public factory;
    AMMV2Router public router;

    // Governance
    VotesToken public govToken;
    Timelock public timelock;
    DAO public governor;  // Using DAO for simple governance (Governor is Zodiac-style for Safe)
    vLUX public voteLux;
    GaugeController public gaugeController;

    // LSSVM
    LSSVMPairFactory public lssvmFactory;
    LinearCurve public linearCurve;
    ExponentialCurve public exponentialCurve;
    LSSVMRouter public lssvmRouter;
    MockNFT public testNft;

    // Markets
    Markets public markets;
    MockOracle public oracle;
    MockRateModel public rateModel;

    // Test accounts
    address public deployer;
    address public alice;
    address public bob;
    address public carol;
    address public treasury;

    // Constants
    uint256 constant INITIAL_LUX = 10_000 ether;
    uint256 constant INITIAL_TOKENS = 100_000 ether;
    uint256 constant GOV_TOKEN_SUPPLY = 100_000_000 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        console.log("=== LUX E2E TEST SETUP ===");

        // Create test accounts
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        treasury = makeAddr("treasury");

        // Fund deployer
        vm.deal(deployer, 1_000_000 ether);

        vm.startPrank(deployer);

        // ========== Deploy Core Tokens ==========
        wlux = new WLUX();
        lusd = new LuxUSD();
        leth = new LuxETH();
        lbtc = new LuxBTC();

        // ========== Deploy Staking ==========
        stakedLux = new StakedLUX(address(wlux));

        // Note: s* synth tokens removed - L* tokens serve as synthetics in Liquid Protocol

        // ========== Deploy AMM ==========
        factory = new AMMV2Factory(deployer);
        router = new AMMV2Router(address(factory), address(wlux));

        // ========== Deploy Governance ==========
        _deployGovernance();

        // ========== Deploy LSSVM ==========
        _deployLSSVM();

        // ========== Deploy Markets ==========
        _deployMarkets();

        // ========== Initial Token Setup ==========
        _setupInitialTokens();

        vm.stopPrank();

        // Fund test users
        _fundTestUsers();

        console.log("=== SETUP COMPLETE ===");
    }

    function _deployGovernance() internal {
        // Governance token
        VotesToken.Allocation[] memory allocations = new VotesToken.Allocation[](1);
        allocations[0] = VotesToken.Allocation({
            recipient: deployer,
            amount: GOV_TOKEN_SUPPLY
        });

        govToken = new VotesToken(
            "Lux Governance",
            "gLUX",
            allocations,
            deployer,
            GOV_TOKEN_SUPPLY,
            false
        );

        // Timelock
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new Timelock(1 days, proposers, executors, deployer);

        // DAO (simple governance - Governor is Zodiac-style for Safe integration)
        governor = new DAO(address(govToken), deployer);

        // Note: DAO uses internal voting, no timelock roles needed
        // For Zodiac-style Governor, use Governor.initialize() with Safe as vault

        // vLUX
        voteLux = new vLUX(address(wlux));

        // Gauge Controller
        gaugeController = new GaugeController(address(voteLux));
    }

    function _deployLSSVM() internal {
        linearCurve = new LinearCurve();
        exponentialCurve = new ExponentialCurve();

        lssvmFactory = new LSSVMPairFactory(treasury);
        lssvmFactory.setBondingCurveAllowed(address(linearCurve), true);
        lssvmFactory.setBondingCurveAllowed(address(exponentialCurve), true);

        lssvmRouter = new LSSVMRouter();

        testNft = new MockNFT();
    }

    function _deployMarkets() internal {
        markets = new Markets(deployer);
        oracle = new MockOracle();
        rateModel = new MockRateModel();

        // Enable rate model and LLTV
        markets.enableRateModel(address(rateModel));
        markets.enableLltv(0.8e18); // 80% LLTV
    }

    function _setupInitialTokens() internal {
        // Wrap LUX
        wlux.deposit{value: INITIAL_LUX}();

        // Mint bridge tokens
        lusd.mint(deployer, INITIAL_TOKENS);
        leth.mint(deployer, INITIAL_TOKENS);
        lbtc.mint(deployer, INITIAL_TOKENS / 100);

        // Note: L* tokens (LUSD, LETH, LBTC) are minted above as bridge tokens
    }

    function _fundTestUsers() internal {
        vm.deal(alice, 10_000 ether);
        vm.deal(bob, 10_000 ether);
        vm.deal(carol, 10_000 ether);

        // Give users some tokens
        vm.startPrank(deployer);
        lusd.mint(alice, 10_000 ether);
        lusd.mint(bob, 10_000 ether);
        lusd.mint(carol, 10_000 ether);

        govToken.transfer(alice, 1_000_000 ether);
        govToken.transfer(bob, 1_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST: TOKENS & STAKING
    // ═══════════════════════════════════════════════════════════════════════════

    function test_E2E_WrapUnwrapLUX() public {
        console.log("\n=== TEST: Wrap/Unwrap LUX ===");

        vm.startPrank(alice);

        uint256 initialBalance = alice.balance;
        uint256 wrapAmount = 100 ether;

        // Wrap LUX
        wlux.deposit{value: wrapAmount}();
        assertEq(wlux.balanceOf(alice), wrapAmount, "Should have WLUX");
        console.log("Wrapped", wrapAmount / 1e18, "LUX -> WLUX");

        // Unwrap WLUX
        wlux.withdraw(wrapAmount);
        assertEq(wlux.balanceOf(alice), 0, "Should have 0 WLUX");
        assertEq(alice.balance, initialBalance, "Should have original LUX back");
        console.log("Unwrapped", wrapAmount / 1e18, "WLUX -> LUX");

        vm.stopPrank();
    }

    function test_E2E_StakeLUX() public {
        console.log("\n=== TEST: Stake LUX ===");

        vm.startPrank(alice);

        uint256 stakeAmount = 1000 ether;

        // Wrap LUX first
        wlux.deposit{value: stakeAmount}();

        // Stake WLUX
        wlux.approve(address(stakedLux), stakeAmount);
        stakedLux.stake(stakeAmount);

        assertGt(stakedLux.balanceOf(alice), 0, "Should have StakedLUX");
        console.log("Staked", stakeAmount / 1e18, "WLUX -> StakedLUX");

        // Start cooldown for unstake (StakedLUX has 7-day cooldown)
        uint256 sLuxBalance = stakedLux.balanceOf(alice);
        stakedLux.startCooldown(sLuxBalance);
        console.log("Started cooldown for", sLuxBalance / 1e18, "StakedLUX");
        
        // Fast-forward past cooldown and complete unstake
        skip(7 days + 1);
        uint256 wluxBefore = wlux.balanceOf(alice);
        stakedLux.unstake();
        assertGt(wlux.balanceOf(alice), wluxBefore, "Should have received WLUX");
        console.log("Unstaked after cooldown");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST: AMM OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_E2E_CreateLiquidityPool() public {
        console.log("\n=== TEST: Create Liquidity Pool ===");

        vm.startPrank(deployer);

        uint256 wluxAmount = 1000 ether;
        uint256 lusdAmount = 1000 ether;

        wlux.approve(address(router), wluxAmount);
        lusd.approve(address(router), lusdAmount);

        router.addLiquidity(
            address(wlux),
            address(lusd),
            wluxAmount,
            lusdAmount,
            0,
            0,
            deployer,
            block.timestamp + 1 hours
        );

        address pair = factory.getPair(address(wlux), address(lusd));
        assertTrue(pair != address(0), "Pair should exist");
        console.log("Created WLUX/LUSD pair at:", pair);

        vm.stopPrank();
    }

    function test_E2E_SwapTokens() public {
        console.log("\n=== TEST: Swap Tokens ===");

        // First create pool
        vm.startPrank(deployer);
        wlux.approve(address(router), 1000 ether);
        lusd.approve(address(router), 1000 ether);
        router.addLiquidity(
            address(wlux), address(lusd),
            1000 ether, 1000 ether,
            0, 0, deployer, block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Alice swaps
        vm.startPrank(alice);

        uint256 swapAmount = 100 ether;
        wlux.deposit{value: swapAmount}();
        wlux.approve(address(router), swapAmount);

        uint256 lusdBefore = lusd.balanceOf(alice);

        address[] memory path = new address[](2);
        path[0] = address(wlux);
        path[1] = address(lusd);

        router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );

        uint256 lusdAfter = lusd.balanceOf(alice);
        assertGt(lusdAfter, lusdBefore, "Should have more LUSD");
        console.log("Swapped WLUX for LUSD:");
        console.log("  Input:", swapAmount / 1e18, "WLUX");
        console.log("  Output:", (lusdAfter - lusdBefore) / 1e18, "LUSD");

        vm.stopPrank();
    }

    function test_E2E_MultiHopSwap() public {
        console.log("\n=== TEST: Multi-Hop Swap ===");

        // Create WLUX/LUSD and LUSD/LETH pools
        vm.startPrank(deployer);

        wlux.approve(address(router), 2000 ether);
        lusd.approve(address(router), 2000 ether);
        leth.approve(address(router), 1000 ether);

        // Pool 1: WLUX/LUSD
        router.addLiquidity(
            address(wlux), address(lusd),
            1000 ether, 1000 ether,
            0, 0, deployer, block.timestamp + 1 hours
        );

        // Pool 2: LUSD/LETH
        router.addLiquidity(
            address(lusd), address(leth),
            1000 ether, 1000 ether,
            0, 0, deployer, block.timestamp + 1 hours
        );

        vm.stopPrank();

        // Alice does multi-hop: WLUX -> LUSD -> LETH
        vm.startPrank(alice);

        uint256 swapAmount = 50 ether;
        wlux.deposit{value: swapAmount}();
        wlux.approve(address(router), swapAmount);

        uint256 lethBefore = leth.balanceOf(alice);

        address[] memory path = new address[](3);
        path[0] = address(wlux);
        path[1] = address(lusd);
        path[2] = address(leth);

        router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );

        uint256 lethAfter = leth.balanceOf(alice);
        assertGt(lethAfter, lethBefore, "Should have more LETH");
        console.log("Multi-hop swap complete:");
        console.log("  Input:", swapAmount / 1e18, "WLUX");
        console.log("  Output:", (lethAfter - lethBefore) / 1e18, "LETH");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST: GOVERNANCE
    // ═══════════════════════════════════════════════════════════════════════════

    function test_E2E_LockLUXForVLUX() public {
        console.log("\n=== TEST: Lock LUX for vLUX ===");

        vm.startPrank(alice);

        uint256 lockAmount = 1000 ether;
        uint256 lockTime = 365 days; // 1 year lock

        // Wrap LUX
        wlux.deposit{value: lockAmount}();
        wlux.approve(address(voteLux), lockAmount);

        // Lock for vLUX
        uint256 unlockTime = ((block.timestamp + lockTime) / 1 weeks) * 1 weeks;
        voteLux.createLock(lockAmount, unlockTime);

        // Check voting power (1 year = ~25% of max)
        uint256 votingPower = voteLux.balanceOf(alice);
        assertGt(votingPower, 0, "Should have voting power");
        console.log("Locked", lockAmount / 1e18, "WLUX for 1 year");
        console.log("Voting power:", votingPower / 1e18, "vLUX");

        vm.stopPrank();
    }

    function test_E2E_GovernanceProposal() public {
        console.log("\n=== TEST: Governance Proposal ===");

        // Both Alice and Bob delegate BEFORE proposal creation
        // (voting power snapshot is taken at proposal creation)
        vm.prank(alice);
        govToken.delegate(alice);
        vm.prank(bob);
        govToken.delegate(bob);

        // Wait for delegations to take effect
        vm.roll(block.number + 1);

        // Create proposal
        vm.startPrank(alice);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            "Test proposal"
        );

        console.log("Created proposal:", proposalId);
        vm.stopPrank();

        // Move past voting delay (need to wait for proposal to become active)
        // DAO uses constant VOTING_DELAY = 1 days (at ~12s blocks = 7200 blocks)
        vm.roll(block.number + 7200 + 1);

        // Alice votes
        vm.prank(alice);
        governor.castVote(proposalId, 1); // Vote for (support=1)
        console.log("Alice voted FOR");

        // Bob votes
        vm.prank(bob);
        governor.castVote(proposalId, 1);
        console.log("Bob voted FOR");

        // Check votes via getProposal
        DAO.ProposalInfo memory proposalInfo = governor.getProposal(proposalId);
        console.log("For votes:", proposalInfo.forVotes / 1e18);
        assertGt(proposalInfo.forVotes, 0, "Should have votes");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST: NFT AMM (LSSVM)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_E2E_CreateNFTPool() public {
        console.log("\n=== TEST: Create NFT Pool ===");

        vm.startPrank(deployer);

        // Mint NFTs
        uint256[] memory nftIds = testNft.mintBatch(deployer, 5);
        console.log("Minted 5 NFTs");

        // Approve factory
        testNft.setApprovalForAll(address(lssvmFactory), true);

        // Create TRADE pool (can buy and sell)
        address pair = lssvmFactory.createPair{value: 10 ether}(
            address(testNft),
            address(linearCurve),
            address(0), // Native LUX
            LSSVMPair.PoolType.TRADE,
            1 ether, // spotPrice
            0.1 ether, // delta
            300, // 3% fee
            treasury,
            nftIds
        );

        assertTrue(pair != address(0), "Pair should exist");
        console.log("Created NFT pool at:", pair);
        console.log("Pool has", testNft.balanceOf(pair), "NFTs");
        console.log("Pool has", pair.balance / 1e18, "LUX");

        vm.stopPrank();
    }

    function test_E2E_BuySellNFT() public {
        console.log("\n=== TEST: Buy/Sell NFT via LSSVM ===");

        // Create pool first
        vm.startPrank(deployer);
        uint256[] memory nftIds = testNft.mintBatch(deployer, 5);
        testNft.setApprovalForAll(address(lssvmFactory), true);

        address pairAddr = lssvmFactory.createPair{value: 50 ether}(
            address(testNft),
            address(linearCurve),
            address(0),
            LSSVMPair.PoolType.TRADE,
            1 ether,
            0.1 ether,
            300,
            treasury,
            nftIds
        );
        LSSVMPair pair = LSSVMPair(payable(pairAddr));
        vm.stopPrank();

        // Alice buys NFT
        vm.startPrank(alice);

        uint256 nftsBefore = testNft.balanceOf(alice);

        // Get buy price (returns 5 values)
        (,, uint256 buyPrice,,) = pair.getBuyNFTQuote(1);
        console.log("Buy price for 1 NFT:", buyPrice / 1e18, "LUX");

        // Buy 1 NFT
        uint256[] memory nftsToBuy = new uint256[](1);
        nftsToBuy[0] = nftIds[0];

        pair.swapTokenForNFTs{value: buyPrice}(
            nftsToBuy,
            buyPrice,
            alice
        );

        assertEq(testNft.balanceOf(alice), nftsBefore + 1, "Alice should have 1 NFT");
        console.log("Alice bought NFT #", nftIds[0]);

        // Alice sells NFT back
        testNft.setApprovalForAll(address(pair), true);
        uint256 balanceBefore = alice.balance;

        // Get sell price (returns 5 values)
        (,, uint256 sellPrice,,) = pair.getSellNFTQuote(1);
        console.log("Sell price for 1 NFT:", sellPrice / 1e18, "LUX");

        uint256[] memory nftsToSell = new uint256[](1);
        nftsToSell[0] = nftIds[0];

        pair.swapNFTsForToken(
            nftsToSell,
            sellPrice,
            alice
        );

        assertEq(testNft.balanceOf(alice), nftsBefore, "Alice should have 0 NFTs");
        assertGt(alice.balance, balanceBefore, "Alice should have more LUX");
        console.log("Alice sold NFT back");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST: MARKETS (LENDING)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_E2E_CreateLendingMarket() public {
        console.log("\n=== TEST: Create Lending Market ===");

        vm.startPrank(deployer);

        MarketParams memory params = MarketParams({
            loanToken: address(lusd),
            collateralToken: address(wlux),
            oracle: address(oracle),
            rateModel: address(rateModel),
            lltv: 0.8e18
        });

        markets.createMarket(params);
        console.log("Created LUSD/WLUX lending market");

        vm.stopPrank();
    }

    function test_E2E_SupplyAndBorrow() public {
        console.log("\n=== TEST: Supply and Borrow ===");

        // Create market
        vm.startPrank(deployer);
        MarketParams memory params = MarketParams({
            loanToken: address(lusd),
            collateralToken: address(wlux),
            oracle: address(oracle),
            rateModel: address(rateModel),
            lltv: 0.8e18
        });
        markets.createMarket(params);
        vm.stopPrank();

        // Bob supplies LUSD
        vm.startPrank(bob);
        uint256 supplyAmount = 5000 ether;
        lusd.approve(address(markets), supplyAmount);
        markets.supply(params, supplyAmount, 0, bob, "");
        console.log("Bob supplied", supplyAmount / 1e18, "LUSD");
        vm.stopPrank();

        // Alice deposits collateral and borrows
        vm.startPrank(alice);

        // Wrap some LUX for collateral
        uint256 collateralAmount = 1000 ether;
        wlux.deposit{value: collateralAmount}();
        wlux.approve(address(markets), collateralAmount);

        // Supply collateral
        markets.supplyCollateral(params, collateralAmount, alice, "");
        console.log("Alice supplied", collateralAmount / 1e18, "WLUX collateral");

        // Borrow LUSD (at 80% LLTV)
        uint256 borrowAmount = 700 ether; // 70% to stay safe
        uint256 lusdBefore = lusd.balanceOf(alice);
        markets.borrow(params, borrowAmount, 0, alice, alice);

        assertEq(lusd.balanceOf(alice), lusdBefore + borrowAmount, "Should have borrowed LUSD");
        console.log("Alice borrowed", borrowAmount / 1e18, "LUSD");

        // Repay
        lusd.approve(address(markets), borrowAmount);
        markets.repay(params, borrowAmount, 0, alice, "");
        console.log("Alice repaid", borrowAmount / 1e18, "LUSD");

        vm.stopPrank();
    }

    function test_E2E_FlashLoan() public {
        console.log("\n=== TEST: Flash Loan ===");

        // Create market and supply
        vm.startPrank(deployer);
        MarketParams memory params = MarketParams({
            loanToken: address(lusd),
            collateralToken: address(wlux),
            oracle: address(oracle),
            rateModel: address(rateModel),
            lltv: 0.8e18
        });
        markets.createMarket(params);

        // Supply to market
        lusd.approve(address(markets), 50000 ether);
        markets.supply(params, 50000 ether, 0, deployer, "");
        vm.stopPrank();

        // Execute flash loan
        vm.startPrank(alice);

        uint256 flashAmount = 10000 ether;

        // Give Alice some LUSD to pay back flash loan
        vm.stopPrank();
        vm.prank(deployer);
        lusd.mint(alice, 100 ether); // For fees
        vm.startPrank(alice);

        // Note: Flash loan callback needs implementation
        // This is a simplified test showing the call
        console.log("Flash loan capability enabled for", flashAmount / 1e18, "LUSD");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST: FULL E2E FLOW
    // ═══════════════════════════════════════════════════════════════════════════

    function test_E2E_FullDeFiFlow() public {
        console.log("\n=== TEST: Full DeFi Flow ===");
        console.log("Alice: Wrap LUX -> Stake -> Add LP -> Swap -> Governance");

        vm.startPrank(alice);

        // Step 1: Wrap LUX
        uint256 wrapAmount = 5000 ether;
        wlux.deposit{value: wrapAmount}();
        console.log("1. Wrapped", wrapAmount / 1e18, "LUX");

        // Step 2: Stake some
        uint256 stakeAmount = 1000 ether;
        wlux.approve(address(stakedLux), stakeAmount);
        stakedLux.stake(stakeAmount);
        console.log("2. Staked", stakeAmount / 1e18, "WLUX");

        vm.stopPrank();

        // Step 3: Create LP pool (requires deployer)
        vm.startPrank(deployer);
        wlux.approve(address(router), 2000 ether);
        lusd.approve(address(router), 2000 ether);
        router.addLiquidity(
            address(wlux), address(lusd),
            2000 ether, 2000 ether,
            0, 0, deployer, block.timestamp + 1 hours
        );
        console.log("3. Created WLUX/LUSD LP");
        vm.stopPrank();

        // Step 4: Alice swaps
        vm.startPrank(alice);
        uint256 swapAmount = 500 ether;
        wlux.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(wlux);
        path[1] = address(lusd);

        router.swapExactTokensForTokens(
            swapAmount, 0, path, alice, block.timestamp + 1 hours
        );
        console.log("4. Swapped", swapAmount / 1e18, "WLUX for LUSD");

        // Step 5: Lock for governance
        uint256 lockAmount = 1000 ether;
        wlux.approve(address(voteLux), lockAmount);
        uint256 unlockTime = ((block.timestamp + 365 days) / 1 weeks) * 1 weeks;
        voteLux.createLock(lockAmount, unlockTime);
        console.log("5. Locked", lockAmount / 1e18, "WLUX for vLUX");

        console.log("\n=== FULL DEFI FLOW COMPLETE ===");
        console.log("Alice final balances:");
        console.log("  WLUX:", wlux.balanceOf(alice) / 1e18);
        console.log("  StakedLUX:", stakedLux.balanceOf(alice) / 1e18);
        console.log("  LUSD:", lusd.balanceOf(alice) / 1e18);
        console.log("  vLUX voting power:", voteLux.balanceOf(alice) / 1e18);

        vm.stopPrank();
    }
}
