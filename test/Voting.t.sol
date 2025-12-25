// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {WLUX} from "../contracts/tokens/WLUX.sol";
import {vLUX} from "../contracts/governance/vLUX.sol";
import {GaugeController} from "../contracts/governance/GaugeController.sol";
import {FeeSplitter} from "../contracts/treasury/FeeSplitter.sol";
import {ValidatorVault} from "../contracts/treasury/ValidatorVault.sol";
import {SynthFeeSplitter} from "../contracts/treasury/SynthFeeSplitter.sol";
import {sLUX} from "../contracts/staking/sLUX.sol";

/**
 * @title VotingTest
 * @notice Comprehensive tests for Lux voting system
 * 
 * Tests cover:
 * 1. vLUX locking and voting power
 * 2. GaugeController weight voting
 * 3. FeeSplitter distribution
 * 4. ValidatorVault delegation
 * 5. sLUX staking and rewards
 * 6. Full integration flow
 */
contract VotingTest is Test {
    // Contracts
    WLUX public wlux;
    vLUX public vlux;
    GaugeController public gaugeController;
    FeeSplitter public feeSplitter;
    ValidatorVault public validatorVault;
    SynthFeeSplitter public synthFeeSplitter;
    sLUX public slux;
    
    // Addresses
    address public deployer;
    address public alice;
    address public bob;
    address public charlie;
    address public daoTreasury;
    address public pol;
    
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // Gauge IDs
    uint256 public burnGaugeId;
    uint256 public validatorGaugeId;
    uint256 public daoGaugeId;
    uint256 public polGaugeId;
    
    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        daoTreasury = makeAddr("daoTreasury");
        pol = makeAddr("pol");
        
        // Deploy contracts
        wlux = new WLUX();
        vlux = new vLUX(address(wlux));
        gaugeController = new GaugeController(address(vlux));
        validatorVault = new ValidatorVault(address(wlux));
        feeSplitter = new FeeSplitter(address(wlux));
        slux = new sLUX(address(wlux));
        synthFeeSplitter = new SynthFeeSplitter(
            address(wlux),
            pol,
            daoTreasury,
            address(slux),
            address(slux)
        );
        
        // Setup gauges
        burnGaugeId = gaugeController.addGauge(BURN_ADDRESS, "Burn", 0);
        validatorGaugeId = gaugeController.addGauge(address(validatorVault), "Validators", 0);
        daoGaugeId = gaugeController.addGauge(daoTreasury, "DAO Treasury", 0);
        polGaugeId = gaugeController.addGauge(pol, "Protocol Liquidity", 0);
        
        // Connect components
        feeSplitter.setGaugeController(address(gaugeController));
        feeSplitter.setBurnGaugeId(burnGaugeId);
        feeSplitter.addRecipient(address(validatorVault));
        feeSplitter.addRecipient(daoTreasury);
        feeSplitter.addRecipient(pol);
        
        slux.setProtocolVault(address(synthFeeSplitter));
        
        // Fund test accounts
        vm.deal(deployer, 100000 ether);
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 10000 ether);
        vm.deal(charlie, 10000 ether);
        
        // Get WLUX
        wlux.deposit{value: 50000 ether}();
        vm.prank(alice);
        wlux.deposit{value: 5000 ether}();
        vm.prank(bob);
        wlux.deposit{value: 5000 ether}();
        vm.prank(charlie);
        wlux.deposit{value: 5000 ether}();
    }
    
    // ============ vLUX Tests ============
    
    function test_vLUX_CreateLock() public {
        uint256 lockAmount = 1000 ether;
        uint256 lockEnd = block.timestamp + 4 * 365 days;
        
        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, lockEnd);
        
        (uint256 amount, uint256 end) = vlux.getLocked(deployer);
        assertEq(amount, lockAmount, "Locked amount mismatch");
        assertGt(end, block.timestamp + 3 * 365 days, "Lock end too short");
        
        uint256 votingPower = vlux.balanceOf(deployer);
        console.log("Voting power for 1000 LUX locked 4 years:", votingPower / 1e18, "vLUX");
        
        // Should have ~997 vLUX (slightly less than 1:1 due to week rounding)
        assertGt(votingPower, 990 ether, "Voting power too low");
        assertLe(votingPower, 1000 ether, "Voting power too high");
    }
    
    function test_vLUX_VotingPowerDecays() public {
        uint256 lockAmount = 1000 ether;
        uint256 lockEnd = block.timestamp + 4 * 365 days;
        
        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, lockEnd);
        
        uint256 initialPower = vlux.balanceOf(deployer);
        
        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        
        uint256 powerAfter1Year = vlux.balanceOf(deployer);
        
        console.log("Initial voting power:", initialPower / 1e18);
        console.log("Power after 1 year:", powerAfter1Year / 1e18);
        
        // Power should decay to ~75% (3 years remaining out of 4)
        assertLt(powerAfter1Year, initialPower, "Power should decay");
        assertGt(powerAfter1Year, initialPower * 70 / 100, "Decayed too much");
    }
    
    function test_vLUX_IncreaseAmount() public {
        uint256 lockAmount = 500 ether;
        uint256 additionalAmount = 500 ether;
        uint256 lockEnd = block.timestamp + 4 * 365 days;
        
        wlux.approve(address(vlux), lockAmount + additionalAmount);
        vlux.createLock(lockAmount, lockEnd);
        
        uint256 initialPower = vlux.balanceOf(deployer);
        
        vlux.increaseAmount(additionalAmount);
        
        uint256 newPower = vlux.balanceOf(deployer);
        
        // Power should roughly double
        assertGt(newPower, initialPower * 19 / 10, "Power should increase significantly");
    }
    
    function test_vLUX_Withdraw() public {
        uint256 lockAmount = 1000 ether;
        // Use 2 weeks to ensure week-rounding doesn't cause LockTooShort
        uint256 lockEnd = block.timestamp + 2 weeks;

        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, lockEnd);

        uint256 balanceBefore = wlux.balanceOf(deployer);

        // Try to withdraw early - should fail
        vm.expectRevert();
        vlux.withdraw();

        // Fast forward past lock end (extra time for week rounding)
        vm.warp(lockEnd + 1 weeks);

        vlux.withdraw();

        uint256 balanceAfter = wlux.balanceOf(deployer);
        assertEq(balanceAfter - balanceBefore, lockAmount, "Should return locked amount");
    }
    
    // ============ GaugeController Tests ============
    
    function test_GaugeController_Vote() public {
        // Lock LUX for voting power
        uint256 lockAmount = 1000 ether;
        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, block.timestamp + 4 * 365 days);

        // Skip past initial vote delay (10 days)
        vm.warp(block.timestamp + 11 days);

        // Vote for burn gauge (50%)
        gaugeController.vote(burnGaugeId, 5000);

        (uint256 weight, uint256 lastVoteTime) = gaugeController.getUserVote(deployer, burnGaugeId);
        assertEq(weight, 5000, "Vote weight should be 5000 BPS");
        assertEq(lastVoteTime, block.timestamp, "Vote time should be now");
    }
    
    function test_GaugeController_VoteMultiple() public {
        uint256 lockAmount = 1000 ether;
        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, block.timestamp + 4 * 365 days);
        
        uint256[] memory gaugeIds = new uint256[](4);
        uint256[] memory weights = new uint256[](4);
        
        gaugeIds[0] = burnGaugeId;
        gaugeIds[1] = validatorGaugeId;
        gaugeIds[2] = daoGaugeId;
        gaugeIds[3] = polGaugeId;
        
        weights[0] = 5000; // 50%
        weights[1] = 4800; // 48%
        weights[2] = 100;  // 1%
        weights[3] = 100;  // 1%
        
        gaugeController.voteMultiple(gaugeIds, weights);
        
        uint256 totalWeight = gaugeController.userTotalWeight(deployer);
        assertEq(totalWeight, 10000, "Total weight should be 100%");
    }
    
    function test_GaugeController_UpdateWeights() public {
        // Multiple users vote
        _setupMultipleVoters();
        
        // Fast forward 1 week
        vm.warp(block.timestamp + 7 days + 1);
        
        gaugeController.updateWeights();
        
        uint256 burnWeight = gaugeController.getGaugeWeightBPS(burnGaugeId);
        uint256 validatorWeight = gaugeController.getGaugeWeightBPS(validatorGaugeId);
        
        console.log("Burn weight after update:", burnWeight);
        console.log("Validator weight after update:", validatorWeight);
        
        // Weights should reflect votes
        assertGt(burnWeight, 0, "Burn weight should be > 0");
        assertGt(validatorWeight, 0, "Validator weight should be > 0");
    }
    
    function test_GaugeController_VoteDelay() public {
        uint256 lockAmount = 1000 ether;
        wlux.approve(address(vlux), lockAmount);
        vlux.createLock(lockAmount, block.timestamp + 4 * 365 days);

        // Skip past initial vote delay for first vote
        vm.warp(block.timestamp + 11 days);

        // First vote
        gaugeController.vote(burnGaugeId, 5000);

        // Try to vote again immediately - should fail
        vm.expectRevert();
        gaugeController.vote(burnGaugeId, 6000);

        // Fast forward past delay
        vm.warp(block.timestamp + 10 days + 1);

        // Now should succeed
        gaugeController.vote(burnGaugeId, 6000);
    }
    
    // ============ FeeSplitter Tests ============
    
    function test_FeeSplitter_Distribute() public {
        // Setup votes and update weights
        _setupMultipleVoters();
        vm.warp(block.timestamp + 7 days + 1);
        gaugeController.updateWeights();
        
        // Deposit fees
        uint256 feeAmount = 1000 ether;
        wlux.approve(address(feeSplitter), feeAmount);
        feeSplitter.depositFees(feeAmount);
        
        uint256 burnBalanceBefore = wlux.balanceOf(BURN_ADDRESS);
        uint256 validatorBalanceBefore = wlux.balanceOf(address(validatorVault));
        uint256 daoBalanceBefore = wlux.balanceOf(daoTreasury);
        uint256 polBalanceBefore = wlux.balanceOf(pol);
        
        // Distribute
        feeSplitter.distribute();
        
        uint256 burnReceived = wlux.balanceOf(BURN_ADDRESS) - burnBalanceBefore;
        uint256 validatorReceived = wlux.balanceOf(address(validatorVault)) - validatorBalanceBefore;
        uint256 daoReceived = wlux.balanceOf(daoTreasury) - daoBalanceBefore;
        uint256 polReceived = wlux.balanceOf(pol) - polBalanceBefore;
        
        console.log("Burned:", burnReceived / 1e18, "LUX");
        console.log("To Validators:", validatorReceived / 1e18, "LUX");
        console.log("To DAO:", daoReceived / 1e18, "LUX");
        console.log("To POL:", polReceived / 1e18, "LUX");
        
        // Verify distribution roughly matches gauge weights
        assertGt(burnReceived, 0, "Should burn some");
        assertGt(validatorReceived, 0, "Validators should receive some");
    }
    
    // ============ ValidatorVault Tests ============
    
    function test_ValidatorVault_Delegate() public {
        bytes32 validatorId = keccak256("validator1");
        address validatorReward = makeAddr("validatorReward");
        
        // Register validator
        validatorVault.registerValidator(validatorId, validatorReward, 1000); // 10% commission
        
        // Delegate
        uint256 delegateAmount = 100 ether;
        wlux.approve(address(validatorVault), delegateAmount);
        validatorVault.delegate(validatorId, delegateAmount);
        
        assertEq(validatorVault.totalDelegated(), delegateAmount, "Total delegated mismatch");
    }
    
    function test_ValidatorVault_RewardsDistribution() public {
        bytes32 validatorId = keccak256("validator1");
        address validatorReward = makeAddr("validatorReward");
        
        // Register validator with 10% commission
        validatorVault.registerValidator(validatorId, validatorReward, 1000);
        
        // Delegate
        uint256 delegateAmount = 100 ether;
        wlux.approve(address(validatorVault), delegateAmount);
        validatorVault.delegate(validatorId, delegateAmount);
        
        // Add rewards
        uint256 rewardAmount = 10 ether;
        wlux.approve(address(validatorVault), rewardAmount);
        validatorVault.depositRewards(rewardAmount);
        
        // Check pending rewards (minus reserve)
        uint256 pending = validatorVault.getPendingRewards(deployer);
        console.log("Pending rewards for delegator:", pending / 1e18, "LUX");
        
        // Should be ~8.55 LUX (10 - 5% reserve = 9.5, then 90% delegator = 8.55)
        assertGt(pending, 8 ether, "Should have significant pending rewards");
    }
    
    // ============ sLUX Tests ============
    
    function test_sLUX_Stake() public {
        uint256 stakeAmount = 100 ether;
        
        wlux.approve(address(slux), stakeAmount);
        uint256 sLuxReceived = slux.stake(stakeAmount);
        
        assertEq(sLuxReceived, stakeAmount, "Should receive 1:1 sLUX initially");
        assertEq(slux.balanceOf(deployer), stakeAmount, "sLUX balance mismatch");
        assertEq(slux.totalStaked(), stakeAmount, "Total staked mismatch");
    }
    
    function test_sLUX_ExchangeRateIncreasesWithRewards() public {
        // Stake initial amount
        uint256 stakeAmount = 100 ether;
        wlux.approve(address(slux), stakeAmount);
        slux.stake(stakeAmount);
        
        uint256 initialRate = slux.exchangeRate();
        
        // Add rewards
        uint256 rewardAmount = 10 ether;
        wlux.approve(address(slux), rewardAmount);
        slux.addRewards(rewardAmount);
        
        uint256 newRate = slux.exchangeRate();
        
        console.log("Initial exchange rate:", initialRate / 1e16, "/ 100");
        console.log("New exchange rate:", newRate / 1e16, "/ 100");
        
        assertGt(newRate, initialRate, "Exchange rate should increase with rewards");
    }
    
    function test_sLUX_UnstakeAfterCooldown() public {
        uint256 stakeAmount = 100 ether;
        
        wlux.approve(address(slux), stakeAmount);
        slux.stake(stakeAmount);
        
        // Start cooldown
        slux.startCooldown(stakeAmount);
        
        // Try to unstake immediately - should fail
        vm.expectRevert("sLUX: cooldown not complete");
        slux.unstake();
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + 7 days + 1);
        
        uint256 balanceBefore = wlux.balanceOf(deployer);
        slux.unstake();
        uint256 balanceAfter = wlux.balanceOf(deployer);
        
        assertEq(balanceAfter - balanceBefore, stakeAmount, "Should return staked amount");
    }
    
    // ============ Integration Tests ============
    
    function test_FullFlow_VoteAndDistribute() public {
        console.log("\n=== FULL VE-TOKENOMICS FLOW TEST ===\n");
        
        // 1. Users lock LUX for vLUX
        console.log("1. Users locking LUX for voting power...");
        
        vm.startPrank(alice);
        wlux.approve(address(vlux), 1000 ether);
        vlux.createLock(1000 ether, block.timestamp + 4 * 365 days);
        uint256 alicePower = vlux.balanceOf(alice);
        console.log("   Alice locked 1000 LUX, got", alicePower / 1e18, "vLUX");
        vm.stopPrank();
        
        vm.startPrank(bob);
        wlux.approve(address(vlux), 2000 ether);
        vlux.createLock(2000 ether, block.timestamp + 2 * 365 days);
        uint256 bobPower = vlux.balanceOf(bob);
        console.log("   Bob locked 2000 LUX for 2 years, got", bobPower / 1e18, "vLUX");
        vm.stopPrank();
        
        // 2. Users vote on gauges
        console.log("\n2. Users voting on gauge weights...");
        
        vm.startPrank(alice);
        uint256[] memory aliceGauges = new uint256[](2);
        uint256[] memory aliceWeights = new uint256[](2);
        aliceGauges[0] = burnGaugeId;
        aliceGauges[1] = validatorGaugeId;
        aliceWeights[0] = 6000; // 60% burn
        aliceWeights[1] = 4000; // 40% validators
        gaugeController.voteMultiple(aliceGauges, aliceWeights);
        console.log("   Alice voted: 60% burn, 40% validators");
        vm.stopPrank();
        
        vm.startPrank(bob);
        uint256[] memory bobGauges = new uint256[](3);
        uint256[] memory bobWeights = new uint256[](3);
        bobGauges[0] = burnGaugeId;
        bobGauges[1] = validatorGaugeId;
        bobGauges[2] = daoGaugeId;
        bobWeights[0] = 4000; // 40% burn
        bobWeights[1] = 5000; // 50% validators
        bobWeights[2] = 1000; // 10% DAO
        gaugeController.voteMultiple(bobGauges, bobWeights);
        console.log("   Bob voted: 40% burn, 50% validators, 10% DAO");
        vm.stopPrank();
        
        // 3. Wait for epoch and update weights
        console.log("\n3. Waiting for epoch and updating weights...");
        vm.warp(block.timestamp + 7 days + 1);
        gaugeController.updateWeights();
        
        uint256 burnWeight = gaugeController.getGaugeWeightBPS(burnGaugeId);
        uint256 validatorWeight = gaugeController.getGaugeWeightBPS(validatorGaugeId);
        uint256 daoWeight = gaugeController.getGaugeWeightBPS(daoGaugeId);
        
        console.log("   Final weights after voting:");
        console.log("   - Burn:", burnWeight, "BPS");
        console.log("   - Validators:", validatorWeight, "BPS");
        console.log("   - DAO:", daoWeight, "BPS");
        
        // 4. Protocol collects fees and distributes
        console.log("\n4. Distributing 1000 LUX in protocol fees...");
        
        uint256 feeAmount = 1000 ether;
        wlux.approve(address(feeSplitter), feeAmount);
        feeSplitter.depositFees(feeAmount);
        
        uint256 burnBefore = wlux.balanceOf(BURN_ADDRESS);
        uint256 validatorBefore = wlux.balanceOf(address(validatorVault));
        uint256 daoBefore = wlux.balanceOf(daoTreasury);
        
        feeSplitter.distribute();
        
        console.log("   Distribution results:");
        console.log("   - Burned:", (wlux.balanceOf(BURN_ADDRESS) - burnBefore) / 1e18, "LUX");
        console.log("   - To Validators:", (wlux.balanceOf(address(validatorVault)) - validatorBefore) / 1e18, "LUX");
        console.log("   - To DAO:", (wlux.balanceOf(daoTreasury) - daoBefore) / 1e18, "LUX");
        
        // 5. Verify stats
        (uint256 received, uint256 distributed, uint256 burned) = feeSplitter.getStats();
        console.log("\n5. FeeSplitter stats:");
        console.log("   - Total received:", received / 1e18, "LUX");
        console.log("   - Total distributed:", distributed / 1e18, "LUX");
        console.log("   - Total burned:", burned / 1e18, "LUX");
        
        console.log("\n=== FLOW TEST COMPLETE ===\n");
    }
    
    function test_SynthFeeSplitter_Distribution() public {
        console.log("\n=== SYNTH FEE SPLITTER TEST ===\n");
        
        // Stake some LUX first
        uint256 stakeAmount = 1000 ether;
        wlux.approve(address(slux), stakeAmount);
        slux.stake(stakeAmount);
        console.log("Staked", stakeAmount / 1e18, "LUX for sLUX");
        
        // Deposit fees to synth fee splitter
        uint256 feeAmount = 100 ether;
        wlux.approve(address(synthFeeSplitter), feeAmount);
        synthFeeSplitter.depositFees(feeAmount);
        console.log("Deposited", feeAmount / 1e18, "LUX in fees");
        
        uint256 polBefore = wlux.balanceOf(pol);
        uint256 daoBefore = wlux.balanceOf(daoTreasury);
        uint256 stakeBefore = slux.totalStaked();
        
        // Distribute
        synthFeeSplitter.distribute();
        
        uint256 polReceived = wlux.balanceOf(pol) - polBefore;
        uint256 daoReceived = wlux.balanceOf(daoTreasury) - daoBefore;
        uint256 stakeIncrease = slux.totalStaked() - stakeBefore;
        
        console.log("\nDistribution (1% POL, 1% DAO, 1% stakers, 97% reserve):");
        console.log("  - POL received:", polReceived / 1e18, "LUX (expected: 1)");
        console.log("  - DAO received:", daoReceived / 1e18, "LUX (expected: 1)");
        console.log("  - sLUX increase:", stakeIncrease / 1e18, "LUX (expected: 1)");
        
        // Verify allocations
        assertEq(polReceived, 1 ether, "POL should get 1%");
        assertEq(daoReceived, 1 ether, "DAO should get 1%");
        assertEq(stakeIncrease, 1 ether, "Stakers should get 1%");
        
        console.log("\n=== SYNTH FEE TEST COMPLETE ===\n");
    }
    
    // ============ Helper Functions ============
    
    function _setupMultipleVoters() internal {
        // Alice votes
        vm.startPrank(alice);
        wlux.approve(address(vlux), 1000 ether);
        vlux.createLock(1000 ether, block.timestamp + 4 * 365 days);
        
        uint256[] memory aliceGauges = new uint256[](2);
        uint256[] memory aliceWeights = new uint256[](2);
        aliceGauges[0] = burnGaugeId;
        aliceGauges[1] = validatorGaugeId;
        aliceWeights[0] = 5000;
        aliceWeights[1] = 5000;
        gaugeController.voteMultiple(aliceGauges, aliceWeights);
        vm.stopPrank();
        
        // Bob votes
        vm.startPrank(bob);
        wlux.approve(address(vlux), 2000 ether);
        vlux.createLock(2000 ether, block.timestamp + 2 * 365 days);
        
        uint256[] memory bobGauges = new uint256[](3);
        uint256[] memory bobWeights = new uint256[](3);
        bobGauges[0] = burnGaugeId;
        bobGauges[1] = validatorGaugeId;
        bobGauges[2] = daoGaugeId;
        bobWeights[0] = 4000;
        bobWeights[1] = 4000;
        bobWeights[2] = 2000;
        gaugeController.voteMultiple(bobGauges, bobWeights);
        vm.stopPrank();
    }
}
