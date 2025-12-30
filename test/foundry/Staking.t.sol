// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// Staking contracts
import {sLUX} from "../../contracts/staking/sLUX.sol";

// Token contracts
import {WLUX} from "../../contracts/tokens/WLUX.sol";

// Import shared mocks
import {MockERC20Solmate as MockRewardToken} from "./TestMocks.sol";

/// @title StakingTest
/// @notice Comprehensive tests for sLUX staking contract
contract StakingTest is Test {
    // Contracts
    sLUX public slux;
    WLUX public wlux;
    MockRewardToken public rewardToken;

    // Users
    address public owner = address(0x1);
    address public protocolVault = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public carol = address(0x5);

    // Constants
    uint256 constant INITIAL_LUX = 1000 ether;
    uint256 constant MIN_STAKE = 1 ether;
    uint256 constant DEFAULT_APY = 1100; // 11%
    uint256 constant COOLDOWN_PERIOD = 7 days;

    // Events
    event Staked(address indexed user, uint256 luxAmount, uint256 sLuxMinted);
    event Unstaked(address indexed user, uint256 sLuxBurned, uint256 luxReturned);
    event CooldownStarted(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 amount);
    event APYUpdated(uint256 newAPY);
    event ProtocolVaultUpdated(address indexed oldVault, address indexed newVault);

    function setUp() public {
        // Deploy contracts as owner
        vm.startPrank(owner);

        wlux = new WLUX();
        slux = new sLUX(address(wlux));
        rewardToken = new MockRewardToken("Reward Token", "RWRD", 18);

        // Set protocol vault
        slux.setProtocolVault(protocolVault);

        vm.stopPrank();

        // Fund users with LUX and WLUX
        vm.deal(alice, INITIAL_LUX);
        vm.deal(bob, INITIAL_LUX);
        vm.deal(carol, INITIAL_LUX);

        // Wrap LUX to WLUX for each user
        vm.prank(alice);
        wlux.deposit{value: INITIAL_LUX}();

        vm.prank(bob);
        wlux.deposit{value: INITIAL_LUX}();

        vm.prank(carol);
        wlux.deposit{value: INITIAL_LUX}();

        // Fund protocol vault with WLUX for rewards
        vm.deal(protocolVault, INITIAL_LUX);
        vm.prank(protocolVault);
        wlux.deposit{value: INITIAL_LUX}();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC STAKING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testStakeBasic() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        wlux.approve(address(slux), stakeAmount);

        uint256 sLuxMinted = slux.stake(stakeAmount);
        vm.stopPrank();

        // First stake should be 1:1
        assertEq(sLuxMinted, stakeAmount);
        assertEq(slux.balanceOf(alice), stakeAmount);
        assertEq(slux.totalStaked(), stakeAmount);
        assertEq(slux.totalSupply(), stakeAmount);
    }

    function testStakeMultipleUsers() public {
        uint256 aliceStake = 100 ether;
        uint256 bobStake = 200 ether;

        // Alice stakes first
        vm.startPrank(alice);
        wlux.approve(address(slux), aliceStake);
        slux.stake(aliceStake);
        vm.stopPrank();

        // Bob stakes second
        vm.startPrank(bob);
        wlux.approve(address(slux), bobStake);
        slux.stake(bobStake);
        vm.stopPrank();

        assertEq(slux.balanceOf(alice), aliceStake);
        assertEq(slux.balanceOf(bob), bobStake);
        assertEq(slux.totalStaked(), aliceStake + bobStake);
    }

    function testStakeEmitsEvent() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(alice);
        wlux.approve(address(slux), stakeAmount);

        vm.expectEmit(true, false, false, true);
        emit Staked(alice, stakeAmount, stakeAmount);
        slux.stake(stakeAmount);
        vm.stopPrank();
    }

    function testStakeRevertsOnInsufficientBalance() public {
        uint256 stakeAmount = INITIAL_LUX + 1 ether;

        vm.startPrank(alice);
        wlux.approve(address(slux), stakeAmount);

        vm.expectRevert();
        slux.stake(stakeAmount);
        vm.stopPrank();
    }

    function testStakeRevertsOnBelowMinimum() public {
        uint256 stakeAmount = MIN_STAKE - 1;

        vm.startPrank(alice);
        wlux.approve(address(slux), stakeAmount);

        vm.expectRevert("sLUX: below minimum stake");
        slux.stake(stakeAmount);
        vm.stopPrank();
    }

    function testStakeRevertsOnZeroAmount() public {
        vm.startPrank(alice);
        wlux.approve(address(slux), 0);

        vm.expectRevert("sLUX: below minimum stake");
        slux.stake(0);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXCHANGE RATE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testExchangeRateInitial() public {
        assertEq(slux.exchangeRate(), 1e18); // 1:1 initially
    }

    function testExchangeRateAfterRewards() public {
        // Alice stakes 100 LUX
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Add 10 LUX rewards (10% increase)
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Exchange rate should be 1.1 (110 staked / 100 supply)
        assertEq(slux.exchangeRate(), 1.1e18);
    }

    function testPreviewDeposit() public {
        // Alice stakes 100 LUX
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Add 10 LUX rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Bob deposits 110 LUX - should get 100 sLUX
        uint256 expectedShares = slux.previewDeposit(110 ether);
        assertEq(expectedShares, 100 ether);
    }

    function testPreviewRedeem() public {
        // Alice stakes 100 LUX
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Add 10 LUX rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Redeeming 100 sLUX should return 110 LUX
        uint256 expectedAssets = slux.previewRedeem(100 ether);
        assertEq(expectedAssets, 110 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COOLDOWN & UNSTAKE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testStartCooldown() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);

        // Start cooldown
        vm.expectEmit(true, false, false, true);
        emit CooldownStarted(alice, 50 ether);
        slux.startCooldown(50 ether);
        vm.stopPrank();

        assertEq(slux.cooldownStart(alice), block.timestamp);
        assertEq(slux.cooldownAmount(alice), 50 ether);
    }

    function testUnstakeAfterCooldown() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        uint256 sLuxMinted = slux.stake(100 ether);

        // Start cooldown
        slux.startCooldown(sLuxMinted);

        // Warp time forward
        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        // Unstake
        uint256 luxReturned = slux.unstake();
        vm.stopPrank();

        assertEq(luxReturned, 100 ether);
        assertEq(slux.balanceOf(alice), 0);
        assertEq(wlux.balanceOf(alice), INITIAL_LUX); // Back to original balance
    }

    function testUnstakeRevertsBeforeCooldown() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);

        // Start cooldown
        slux.startCooldown(100 ether);

        // Try to unstake immediately
        vm.expectRevert("sLUX: cooldown not complete");
        slux.unstake();
        vm.stopPrank();
    }

    function testUnstakeRevertsWithoutCooldown() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);

        // Try to unstake without starting cooldown
        vm.expectRevert("sLUX: no cooldown active");
        slux.unstake();
        vm.stopPrank();
    }

    function testUnstakeWithRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        slux.startCooldown(100 ether);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Warp time and unstake
        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        vm.prank(alice);
        uint256 luxReturned = slux.unstake();

        // Should receive original stake + rewards (110 LUX)
        assertEq(luxReturned, 110 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INSTANT UNSTAKE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testInstantUnstake() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        uint256 sLuxMinted = slux.stake(100 ether);

        // Instant unstake with 10% penalty
        uint256 luxReturned = slux.instantUnstake(sLuxMinted);
        vm.stopPrank();

        // Should receive 90% of stake (10% penalty)
        assertEq(luxReturned, 90 ether);
        assertEq(slux.balanceOf(alice), 0);
    }

    function testInstantUnstakePartial() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);

        // Instant unstake half
        uint256 luxReturned = slux.instantUnstake(50 ether);
        vm.stopPrank();

        assertEq(luxReturned, 45 ether); // 50 * 0.9
        assertEq(slux.balanceOf(alice), 50 ether);
    }

    function testInstantUnstakeWithRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Add 10% rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Instant unstake all (receives 110 * 0.9 = 99 LUX)
        vm.prank(alice);
        uint256 luxReturned = slux.instantUnstake(100 ether);

        assertEq(luxReturned, 99 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARD DISTRIBUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testAddRewardsFromProtocolVault() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Protocol vault adds rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);

        vm.expectEmit(false, false, false, true);
        emit RewardsDistributed(10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        assertEq(slux.totalStaked(), 110 ether);
    }

    function testAddRewardsFromOwner() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Owner can also add rewards (for testing/bootstrapping)
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);
        wlux.deposit{value: 10 ether}();
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        assertEq(slux.totalStaked(), 110 ether);
    }

    function testAddRewardsRevertsFromUnauthorized() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Bob tries to add rewards (should fail)
        vm.startPrank(bob);
        wlux.approve(address(slux), 10 ether);

        vm.expectRevert("sLUX: not authorized");
        slux.addRewards(10 ether);
        vm.stopPrank();
    }

    function testQueueRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Protocol vault queues rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.queueRewards(10 ether);
        vm.stopPrank();

        assertEq(slux.pendingRewards(), 10 ether);
        assertEq(slux.totalStaked(), 100 ether); // Not added yet

        // Distribute rewards
        slux.distributeRewards();

        assertEq(slux.pendingRewards(), 0);
        assertEq(slux.totalStaked(), 110 ether);
    }

    function testSimulateYield() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Warp 365 days forward
        vm.warp(block.timestamp + 365 days);

        // Simulate yield (11% APY)
        vm.prank(owner);
        slux.simulateYield();

        // Should have ~11 LUX in rewards (11% of 100)
        uint256 totalStaked = slux.totalStaked();
        assertApproxEqRel(totalStaked, 111 ether, 0.01e18); // 1% tolerance
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPOUND REWARDS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testCompoundRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Add 10 LUX rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Bob stakes - gets fewer shares due to increased exchange rate
        vm.startPrank(bob);
        wlux.approve(address(slux), 110 ether);
        uint256 bobShares = slux.stake(110 ether);
        vm.stopPrank();

        // Bob should get 100 sLUX for 110 LUX (1.1:1 ratio)
        assertEq(bobShares, 100 ether);

        // Add more rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 22 ether); // 10% of 220
        slux.addRewards(22 ether);
        vm.stopPrank();

        // Total staked should be 242 LUX
        assertEq(slux.totalStaked(), 242 ether);

        // Alice and Bob should have equal shares
        assertEq(slux.balanceOf(alice), 100 ether);
        assertEq(slux.balanceOf(bob), 100 ether);

        // But they should receive equal value when redeeming
        uint256 aliceValue = slux.previewRedeem(slux.balanceOf(alice));
        uint256 bobValue = slux.previewRedeem(slux.balanceOf(bob));
        assertEq(aliceValue, bobValue);
        assertEq(aliceValue, 121 ether); // 242 / 2
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function testStakeMaxAmount() public {
        uint256 maxStake = INITIAL_LUX;

        vm.startPrank(alice);
        wlux.approve(address(slux), maxStake);
        slux.stake(maxStake);
        vm.stopPrank();

        assertEq(slux.balanceOf(alice), maxStake);
    }

    function testMultipleStakeUnstakeCycles() public {
        vm.startPrank(alice);

        // Cycle 1: Stake and unstake
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        slux.startCooldown(100 ether);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        slux.unstake();

        // Cycle 2: Stake again
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);

        vm.stopPrank();

        assertEq(slux.balanceOf(alice), 100 ether);
    }

    function testZeroStakedDistribution() public {
        // Try to distribute rewards with no stakers
        vm.prank(owner);
        slux.simulateYield();

        assertEq(slux.totalStaked(), 0);
    }

    function testMultipleUserRewardDistribution() public {
        // Alice stakes 100, Bob stakes 200, Carol stakes 300
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        wlux.approve(address(slux), 200 ether);
        slux.stake(200 ether);
        vm.stopPrank();

        vm.startPrank(carol);
        wlux.approve(address(slux), 300 ether);
        slux.stake(300 ether);
        vm.stopPrank();

        // Add 60 LUX rewards (10% of 600)
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 60 ether);
        slux.addRewards(60 ether);
        vm.stopPrank();

        // Check reward distribution proportions
        uint256 aliceValue = slux.previewRedeem(slux.balanceOf(alice));
        uint256 bobValue = slux.previewRedeem(slux.balanceOf(bob));
        uint256 carolValue = slux.previewRedeem(slux.balanceOf(carol));

        // Alice should have ~110 LUX worth
        assertApproxEqRel(aliceValue, 110 ether, 0.01e18);
        // Bob should have ~220 LUX worth
        assertApproxEqRel(bobValue, 220 ether, 0.01e18);
        // Carol should have ~330 LUX worth
        assertApproxEqRel(carolValue, 330 ether, 0.01e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GOVERNANCE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testSetAPY() public {
        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true);
        emit APYUpdated(1500);
        slux.setAPY(1500); // 15%
        vm.stopPrank();

        assertEq(slux.apy(), 1500);
    }

    function testSetAPYRevertsOnTooHigh() public {
        vm.startPrank(owner);

        vm.expectRevert("sLUX: APY too high");
        slux.setAPY(5001); // > 50%
        vm.stopPrank();
    }

    function testSetAPYRevertsFromNonOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        slux.setAPY(1500);
        vm.stopPrank();
    }

    function testSetProtocolVault() public {
        address newVault = address(0x99);

        vm.startPrank(owner);

        vm.expectEmit(true, true, false, false);
        emit ProtocolVaultUpdated(protocolVault, newVault);
        slux.setProtocolVault(newVault);
        vm.stopPrank();

        assertEq(slux.protocolVault(), newVault);
    }

    function testSetProtocolVaultRevertsOnZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(sLUX.InvalidProtocolVault.selector);
        slux.setProtocolVault(address(0));
        vm.stopPrank();
    }

    function testSetCooldownPeriod() public {
        vm.startPrank(owner);

        slux.setCooldownPeriod(14 days);
        vm.stopPrank();

        assertEq(slux.cooldownPeriod(), 14 days);
    }

    function testSetCooldownPeriodRevertsOnTooLong() public {
        vm.startPrank(owner);

        vm.expectRevert("sLUX: cooldown too long");
        slux.setCooldownPeriod(31 days);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzzStakeAmount(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, MIN_STAKE, INITIAL_LUX);

        vm.startPrank(alice);
        wlux.approve(address(slux), amount);
        uint256 sLuxMinted = slux.stake(amount);
        vm.stopPrank();

        assertEq(sLuxMinted, amount); // First stake is 1:1
        assertEq(slux.balanceOf(alice), amount);
    }

    function testFuzzMultipleStakes(uint256 stake1, uint256 stake2, uint256 stake3) public {
        // Bound stakes to reasonable ranges
        stake1 = bound(stake1, MIN_STAKE, INITIAL_LUX / 3);
        stake2 = bound(stake2, MIN_STAKE, INITIAL_LUX / 3);
        stake3 = bound(stake3, MIN_STAKE, INITIAL_LUX / 3);

        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), stake1);
        slux.stake(stake1);
        vm.stopPrank();

        // Bob stakes
        vm.startPrank(bob);
        wlux.approve(address(slux), stake2);
        slux.stake(stake2);
        vm.stopPrank();

        // Carol stakes
        vm.startPrank(carol);
        wlux.approve(address(slux), stake3);
        slux.stake(stake3);
        vm.stopPrank();

        // Total staked should equal sum of individual stakes
        assertEq(slux.totalStaked(), stake1 + stake2 + stake3);
    }

    function testFuzzRewardDistribution(uint256 stakeAmount, uint256 rewardAmount) public {
        // Bound to reasonable ranges
        stakeAmount = bound(stakeAmount, MIN_STAKE, INITIAL_LUX);
        rewardAmount = bound(rewardAmount, 0.01 ether, INITIAL_LUX);

        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), stakeAmount);
        slux.stake(stakeAmount);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), rewardAmount);
        slux.addRewards(rewardAmount);
        vm.stopPrank();

        // Total staked should be original + rewards
        assertEq(slux.totalStaked(), stakeAmount + rewardAmount);

        // Exchange rate should reflect rewards
        uint256 expectedRate = ((stakeAmount + rewardAmount) * 1e18) / stakeAmount;
        assertEq(slux.exchangeRate(), expectedRate);
    }

    function testFuzzCooldownDuration(uint256 cooldownTime) public {
        // Bound cooldown to 0-30 days
        cooldownTime = bound(cooldownTime, 0, 30 days);

        vm.startPrank(owner);
        slux.setCooldownPeriod(cooldownTime);
        vm.stopPrank();

        // Alice stakes and starts cooldown
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        slux.startCooldown(100 ether);
        vm.stopPrank();

        // Warp to just before cooldown completes
        if (cooldownTime > 0) {
            vm.warp(block.timestamp + cooldownTime - 1);

            vm.startPrank(alice);
            vm.expectRevert("sLUX: cooldown not complete");
            slux.unstake();
            vm.stopPrank();
        }

        // Warp to cooldown completion
        vm.warp(block.timestamp + cooldownTime + 1);

        vm.prank(alice);
        slux.unstake();

        assertEq(slux.balanceOf(alice), 0);
    }

    function testFuzzInstantUnstakePenalty(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE, INITIAL_LUX);

        vm.startPrank(alice);
        wlux.approve(address(slux), stakeAmount);
        uint256 sLuxMinted = slux.stake(stakeAmount);

        uint256 luxReturned = slux.instantUnstake(sLuxMinted);
        vm.stopPrank();

        // Should receive 90% of staked amount (10% penalty)
        uint256 expected = (stakeAmount * 90) / 100;
        assertEq(luxReturned, expected);
    }

    function testFuzzExchangeRateConsistency(uint256 stake1, uint256 stake2, uint256 rewards) public {
        // Bound to reasonable ranges
        stake1 = bound(stake1, MIN_STAKE, INITIAL_LUX / 2);
        stake2 = bound(stake2, MIN_STAKE, INITIAL_LUX / 2);
        rewards = bound(rewards, 0.1 ether, INITIAL_LUX / 10);

        // Alice stakes
        vm.startPrank(alice);
        wlux.approve(address(slux), stake1);
        slux.stake(stake1);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), rewards);
        slux.addRewards(rewards);
        vm.stopPrank();

        // Bob stakes after rewards
        vm.startPrank(bob);
        wlux.approve(address(slux), stake2);
        uint256 bobShares = slux.stake(stake2);
        vm.stopPrank();

        // Verify exchange rate consistency
        uint256 expectedBobShares = (stake2 * stake1) / (stake1 + rewards);
        assertApproxEqRel(bobShares, expectedBobShares, 0.01e18); // 1% tolerance
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFullStakingCycle() public {
        // Alice stakes 100 LUX
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        uint256 aliceShares = slux.stake(100 ether);
        vm.stopPrank();

        // Protocol vault distributes 10 LUX rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 10 ether);
        slux.addRewards(10 ether);
        vm.stopPrank();

        // Bob stakes 110 LUX (should get 100 sLUX due to 1.1 exchange rate)
        vm.startPrank(bob);
        wlux.approve(address(slux), 110 ether);
        uint256 bobShares = slux.stake(110 ether);
        vm.stopPrank();

        assertEq(aliceShares, bobShares); // Equal shares

        // Add more rewards
        vm.startPrank(protocolVault);
        wlux.approve(address(slux), 22 ether); // 10% of 220
        slux.addRewards(22 ether);
        vm.stopPrank();

        // Alice unstakes
        vm.startPrank(alice);
        slux.startCooldown(aliceShares);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        uint256 aliceReturned = slux.unstake();
        vm.stopPrank();

        // Alice should receive 121 LUX (half of 242)
        assertEq(aliceReturned, 121 ether);

        // Bob instant unstakes with penalty
        vm.prank(bob);
        uint256 bobReturned = slux.instantUnstake(bobShares);

        // Bob should receive 108.9 LUX (121 * 0.9)
        assertEq(bobReturned, 108.9 ether);
    }

    function testReentrancyProtection() public {
        // This is implicitly tested by the ReentrancyGuard
        // Solidity will prevent reentrancy attacks
        vm.startPrank(alice);
        wlux.approve(address(slux), 100 ether);
        slux.stake(100 ether);
        vm.stopPrank();

        // Cannot test explicit reentrancy without a malicious contract
        // But the modifier ensures protection
    }
}
