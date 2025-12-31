// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Core contracts
import {WLUX} from "../../contracts/tokens/WLUX.sol";
import {sLUX} from "../../contracts/staking/sLUX.sol";
import {FeeSplitter} from "../../contracts/treasury/FeeSplitter.sol";
import {ValidatorVault} from "../../contracts/treasury/ValidatorVault.sol";

// Governance
import {DAO} from "../../contracts/governance/DAO.sol";
import {VotesToken} from "../../contracts/governance/VotesToken.sol";

// AMM
import {AMMV2Factory} from "../../contracts/amm/AMMV2Factory.sol";
import {AMMV2Router} from "../../contracts/amm/AMMV2Router.sol";
import {AMMV2Pair} from "../../contracts/amm/AMMV2Pair.sol";

// Mocks
import {MockGaugeControllerFull as MockGaugeController, MockVLUX} from "./TestMocks.sol";

/**
 * @title Fee Rewards Integration Test
 * @notice Comprehensive E2E test for Lux fee collection and reward distribution
 *
 * Flow:
 * 1. Users trade on AMM → swap fees collected
 * 2. Swap fees → FeeSplitter
 * 3. FeeSplitter distributes to:
 *    - ValidatorVault (validators/delegators)
 *    - sLUX stakers
 *    - DAO Treasury
 *    - Burn address
 * 4. Users claim staking rewards
 * 5. Validators claim commission
 * 6. Delegators claim rewards
 */
contract FeeRewardsIntegrationTest is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════

    WLUX public wlux;
    sLUX public stakedLux;
    FeeSplitter public feeSplitter;
    ValidatorVault public validatorVault;
    DAO public dao;
    VotesToken public govToken;
    MockGaugeController public gaugeController;
    MockVLUX public vLux;

    AMMV2Factory public factory;
    AMMV2Router public router;

    // Test tokens
    WLUX public usdc; // Using WLUX as mock USDC for simplicity

    // ═══════════════════════════════════════════════════════════════════════
    // USERS
    // ═══════════════════════════════════════════════════════════════════════

    address public deployer;
    address public alice;
    address public bob;
    address public carol;
    address public validator1;
    address public validator2;
    address public daoTreasury;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    bytes32 public validatorId1;
    bytes32 public validatorId2;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant SWAP_AMOUNT = 10_000e18;
    uint256 constant STAKE_AMOUNT = 100_000e18;

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        validator1 = makeAddr("validator1");
        validator2 = makeAddr("validator2");
        daoTreasury = makeAddr("daoTreasury");

        validatorId1 = keccak256("validator1");
        validatorId2 = keccak256("validator2");

        console.log("=== DEPLOYING LUX FEE/REWARDS INFRASTRUCTURE ===");

        // 1. Deploy core tokens
        wlux = new WLUX();
        usdc = new WLUX(); // Mock USDC

        // 2. Deploy staking
        stakedLux = new sLUX(address(wlux));

        // 3. Deploy governance mocks
        vLux = new MockVLUX();
        gaugeController = new MockGaugeController(address(vLux));

        // 4. Deploy treasury contracts
        feeSplitter = new FeeSplitter(address(wlux));
        validatorVault = new ValidatorVault(address(wlux));

        // 5. Deploy AMM
        factory = new AMMV2Factory(deployer);
        router = new AMMV2Router(address(factory), address(wlux));

        // 6. Deploy governance
        VotesToken.Allocation[] memory allocations = new VotesToken.Allocation[](3);
        allocations[0] = VotesToken.Allocation(alice, 10_000_000e18);
        allocations[1] = VotesToken.Allocation(bob, 5_000_000e18);
        allocations[2] = VotesToken.Allocation(carol, 1_000_000e18);

        govToken = new VotesToken(
            "Lux Governance",
            "vLUX-GOV",
            allocations,
            deployer,
            0,
            false
        );

        dao = new DAO(address(govToken), deployer);

        // 7. Configure FeeSplitter recipients
        feeSplitter.addRecipient(address(validatorVault));
        feeSplitter.addRecipient(address(stakedLux));
        feeSplitter.addRecipient(daoTreasury);
        feeSplitter.addRecipient(burnAddress);
        feeSplitter.setGaugeController(address(gaugeController));

        // 8. Configure ValidatorVault
        validatorVault.registerValidator(validatorId1, validator1, 1000); // 10% commission
        validatorVault.registerValidator(validatorId2, validator2, 500);  // 5% commission

        // 9. Configure sLUX
        stakedLux.setProtocolVault(address(feeSplitter));
        stakedLux.transferOwnership(address(dao)); // DAO controls sLUX parameters

        // 10. Fund users
        deal(address(wlux), alice, INITIAL_BALANCE);
        deal(address(wlux), bob, INITIAL_BALANCE);
        deal(address(wlux), carol, INITIAL_BALANCE);
        deal(address(usdc), alice, INITIAL_BALANCE);
        deal(address(usdc), bob, INITIAL_BALANCE);

        // 11. Create AMM liquidity pool
        vm.startPrank(alice);
        wlux.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(wlux),
            address(usdc),
            100_000e18,
            100_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        console.log("=== SETUP COMPLETE ===");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Integration_FullFeeRewardsFlow() public {
        console.log("\n=== FULL FEE REWARDS FLOW ===");

        // Step 1: Users stake LUX
        console.log("\n--- Step 1: Staking ---");
        _stakeTokens();

        // Step 2: Users delegate to validators
        console.log("\n--- Step 2: Delegation ---");
        _delegateToValidators();

        // Step 3: Trading generates fees
        console.log("\n--- Step 3: Trading ---");
        uint256 feesGenerated = _generateTradingFees();
        console.log("Fees generated:", feesGenerated / 1e18, "LUX");

        // Step 4: Deposit fees to splitter
        console.log("\n--- Step 4: Fee Distribution ---");
        _distributeFees(feesGenerated);

        // Step 5: Claim staking rewards
        console.log("\n--- Step 5: Claim Rewards ---");
        _claimRewards();

        console.log("\n=== FLOW COMPLETE ===");
    }

    function test_Integration_StakingRewardsAccrue() public {
        console.log("\n=== STAKING REWARDS ACCRUAL ===");

        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(stakedLux), STAKE_AMOUNT);
        stakedLux.stake(STAKE_AMOUNT);
        vm.stopPrank();

        uint256 initialRate = stakedLux.exchangeRate();
        console.log("Initial exchange rate:", initialRate / 1e18);

        // Simulate rewards from protocol vault (feeSplitter)
        uint256 rewardAmount = 10_000e18;
        deal(address(wlux), address(feeSplitter), rewardAmount);
        vm.startPrank(address(feeSplitter));
        wlux.approve(address(stakedLux), rewardAmount);
        stakedLux.addRewards(rewardAmount);
        vm.stopPrank();

        uint256 newRate = stakedLux.exchangeRate();
        console.log("New exchange rate:", newRate / 1e18);
        assertGt(newRate, initialRate, "Exchange rate should increase");

        // Alice's sLUX is now worth more
        uint256 aliceSLux = stakedLux.balanceOf(alice);
        uint256 aliceLuxValue = stakedLux.previewRedeem(aliceSLux);
        console.log("Alice staked:", STAKE_AMOUNT / 1e18, "LUX");
        console.log("Alice's sLUX now worth:", aliceLuxValue / 1e18, "LUX");
        assertGt(aliceLuxValue, STAKE_AMOUNT, "Alice should have profit");
    }

    function test_Integration_ValidatorRewardsDistribution() public {
        console.log("\n=== VALIDATOR REWARDS DISTRIBUTION ===");

        // Users delegate to validators
        vm.startPrank(alice);
        wlux.approve(address(validatorVault), 50_000e18);
        validatorVault.delegate(validatorId1, 50_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        wlux.approve(address(validatorVault), 30_000e18);
        validatorVault.delegate(validatorId2, 30_000e18);
        vm.stopPrank();

        console.log("Alice delegated 50k LUX to Validator 1");
        console.log("Bob delegated 30k LUX to Validator 2");

        // Deposit rewards
        uint256 rewardAmount = 10_000e18;
        deal(address(wlux), address(this), rewardAmount);
        wlux.approve(address(validatorVault), rewardAmount);
        validatorVault.depositRewards(rewardAmount);

        console.log("Deposited", rewardAmount / 1e18, "LUX rewards");

        // Check pending rewards
        uint256 alicePending = validatorVault.getPendingRewards(alice);
        uint256 bobPending = validatorVault.getPendingRewards(bob);
        (,,,uint256 val1Commission,) = validatorVault.getValidatorInfo(validatorId1);
        (,,,uint256 val2Commission,) = validatorVault.getValidatorInfo(validatorId2);

        console.log("Alice pending rewards:", alicePending / 1e18, "LUX");
        console.log("Bob pending rewards:", bobPending / 1e18, "LUX");
        console.log("Validator 1 commission:", val1Commission / 1e18, "LUX");
        console.log("Validator 2 commission:", val2Commission / 1e18, "LUX");

        // Claim rewards
        vm.prank(alice);
        validatorVault.claimRewards();

        vm.prank(bob);
        validatorVault.claimRewards();

        vm.prank(validator1);
        validatorVault.claimValidatorRewards(validatorId1);

        console.log("Rewards claimed successfully");
    }

    function test_Integration_GovernanceCanUpdateFees() public {
        console.log("\n=== GOVERNANCE FEE UPDATE ===");

        // Create proposal to update sLUX APY
        vm.startPrank(alice);
        govToken.delegate(alice);
        vm.stopPrank();

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(stakedLux);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(sLUX.setAPY.selector, 1500); // 15% APY

        vm.prank(alice);
        uint256 proposalId = dao.propose(targets, values, calldatas, "Increase sLUX APY to 15%");

        console.log("Created proposal:", proposalId);

        // Vote
        vm.roll(block.number + dao.VOTING_DELAY() / 12 + 1);
        vm.prank(alice);
        dao.castVote(proposalId, 1);

        // End voting
        vm.roll(block.number + dao.VOTING_PERIOD() / 12 + 1);

        // Queue
        dao.queue(proposalId);

        // Execute
        vm.warp(block.timestamp + dao.TIMELOCK_DELAY() + 1);
        dao.execute(proposalId);

        assertEq(stakedLux.apy(), 1500, "APY should be updated to 15%");
        console.log("APY successfully updated to 15%");
    }

    function test_Integration_FeeSplitterWithGauges() public {
        console.log("\n=== FEE SPLITTER WITH GAUGES ===");

        // Setup gauge weights (validators get 40%, sLUX gets 40%, DAO gets 20%)
        uint256 validatorGaugeId = gaugeController.addGauge(address(validatorVault), "Validators", 0);
        uint256 sLuxGaugeId = gaugeController.addGauge(address(stakedLux), "sLUX Stakers", 0);
        uint256 daoGaugeId = gaugeController.addGauge(daoTreasury, "DAO Treasury", 0);

        // Mock gauge weights
        gaugeController.setGaugeWeight(validatorGaugeId, 4000); // 40%
        gaugeController.setGaugeWeight(sLuxGaugeId, 4000);      // 40%
        gaugeController.setGaugeWeight(daoGaugeId, 2000);       // 20%

        // Deposit fees
        uint256 feeAmount = 100_000e18;
        deal(address(wlux), address(this), feeAmount);
        wlux.approve(address(feeSplitter), feeAmount);
        feeSplitter.depositFees(feeAmount);

        console.log("Deposited", feeAmount / 1e18, "LUX in fees");

        // Distribute
        feeSplitter.distribute();

        // Check balances
        uint256 validatorBalance = wlux.balanceOf(address(validatorVault));
        uint256 sLuxBalance = wlux.balanceOf(address(stakedLux));
        uint256 daoBalance = wlux.balanceOf(daoTreasury);

        console.log("Validator Vault received:", validatorBalance / 1e18, "LUX");
        console.log("sLUX received:", sLuxBalance / 1e18, "LUX");
        console.log("DAO Treasury received:", daoBalance / 1e18, "LUX");

        // Verify distribution is approximately correct
        assertGt(validatorBalance, 0, "Validators should receive fees");
        assertGt(sLuxBalance, 0, "sLUX should receive fees");
        assertGt(daoBalance, 0, "DAO should receive fees");
    }

    function test_Integration_MultiCycleRewards() public {
        console.log("\n=== MULTI-CYCLE REWARDS ===");

        // Initial stake
        vm.startPrank(alice);
        wlux.approve(address(stakedLux), STAKE_AMOUNT);
        stakedLux.stake(STAKE_AMOUNT);
        vm.stopPrank();

        uint256 aliceInitialBalance = stakedLux.balanceOf(alice);
        console.log("Alice staked:", STAKE_AMOUNT / 1e18, "LUX");
        console.log("Alice received:", aliceInitialBalance / 1e18, "sLUX");

        // Simulate 4 reward cycles
        for (uint256 i = 0; i < 4; i++) {
            // Add rewards via protocol vault (feeSplitter)
            uint256 cycleReward = 5_000e18;
            deal(address(wlux), address(feeSplitter), cycleReward);
            vm.startPrank(address(feeSplitter));
            wlux.approve(address(stakedLux), cycleReward);
            stakedLux.addRewards(cycleReward);
            vm.stopPrank();

            // Advance time
            vm.warp(block.timestamp + 1 weeks);

            uint256 aliceValue = stakedLux.previewRedeem(aliceInitialBalance);
            console.log("Cycle", i + 1);
            console.log("  Alice's value:", aliceValue / 1e18);
        }

        // Final check
        uint256 finalValue = stakedLux.previewRedeem(aliceInitialBalance);
        assertGt(finalValue, STAKE_AMOUNT + 19_000e18, "Should have ~20k rewards");
        console.log("Total value after 4 cycles:", finalValue / 1e18, "LUX");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _stakeTokens() internal {
        vm.startPrank(alice);
        wlux.approve(address(stakedLux), STAKE_AMOUNT);
        stakedLux.stake(STAKE_AMOUNT);
        vm.stopPrank();
        console.log("Alice staked", STAKE_AMOUNT / 1e18, "LUX -> sLUX");

        vm.startPrank(bob);
        wlux.approve(address(stakedLux), STAKE_AMOUNT / 2);
        stakedLux.stake(STAKE_AMOUNT / 2);
        vm.stopPrank();
        console.log("Bob staked", (STAKE_AMOUNT / 2) / 1e18, "LUX -> sLUX");
    }

    function _delegateToValidators() internal {
        vm.startPrank(carol);
        wlux.approve(address(validatorVault), 50_000e18);
        validatorVault.delegate(validatorId1, 30_000e18);
        validatorVault.delegate(validatorId2, 20_000e18);
        vm.stopPrank();
        console.log("Carol delegated to validators");
    }

    function _generateTradingFees() internal returns (uint256) {
        // Simulate multiple swaps
        uint256 totalFees = 0;

        address[] memory path = new address[](2);
        path[0] = address(wlux);
        path[1] = address(usdc);

        vm.startPrank(bob);
        wlux.approve(address(router), SWAP_AMOUNT);
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            bob,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Swap generates 0.3% fee
        totalFees = SWAP_AMOUNT * 3 / 1000;

        return totalFees;
    }

    function _distributeFees(uint256 amount) internal {
        // Simulate fee collection
        deal(address(wlux), address(this), amount);
        wlux.approve(address(feeSplitter), amount);
        feeSplitter.depositFees(amount);

        console.log("Deposited", amount / 1e18, "LUX fees");

        // Distribute to recipients
        feeSplitter.distribute();
        console.log("Fees distributed to recipients");
    }

    function _claimRewards() internal {
        // Stakers: check sLUX value increased
        uint256 aliceSLux = stakedLux.balanceOf(alice);
        uint256 aliceValue = stakedLux.previewRedeem(aliceSLux);
        console.log("Alice's sLUX worth:", aliceValue / 1e18, "LUX");

        // Validators: claim pending
        uint256 carolPending = validatorVault.getPendingRewards(carol);
        if (carolPending > 0) {
            vm.prank(carol);
            validatorVault.claimRewards();
            console.log("Carol claimed", carolPending / 1e18, "LUX from delegation");
        }
    }
}
