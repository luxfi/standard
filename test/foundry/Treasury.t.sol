// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {ILRC20} from "../../contracts/tokens/interfaces/ILRC20.sol";

// Treasury contracts
import {FeeSplitter} from "../../contracts/treasury/FeeSplitter.sol";
import {SynthFeeSplitter} from "../../contracts/treasury/SynthFeeSplitter.sol";
import {ValidatorVault} from "../../contracts/treasury/ValidatorVault.sol";

// Dependencies
import {WLUX} from "../../contracts/tokens/WLUX.sol";

/**
 * @title Treasury Test Suite
 * @notice Comprehensive tests for treasury management contracts
 *
 * Covers:
 * - FeeSplitter (gauge-based fee distribution)
 * - SynthFeeSplitter (fixed synth protocol fees)
 * - ValidatorVault (validator/delegator rewards)
 */
contract TreasuryTest is Test {
    // ════════════════════════════════════════════════════════════════
    // Contracts
    // ════════════════════════════════════════════════════════════════

    FeeSplitter public feeSplitter;
    SynthFeeSplitter public synthFeeSplitter;
    ValidatorVault public validatorVault;
    WLUX public lux;
    MockGaugeController public gaugeController;
    MockVLUX public vLux;
    MockSLUX public sLux;

    // ════════════════════════════════════════════════════════════════
    // Test Accounts
    // ════════════════════════════════════════════════════════════════

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    // Treasury recipients
    address public pol = makeAddr("pol");
    address public daoTreasury = makeAddr("daoTreasury");
    address public vaultReserve = makeAddr("vaultReserve");
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    // Validators
    bytes32 public validatorId1 = keccak256("validator1");
    bytes32 public validatorId2 = keccak256("validator2");
    bytes32 public validatorId3 = keccak256("validator3");

    // ════════════════════════════════════════════════════════════════
    // Events
    // ════════════════════════════════════════════════════════════════

    event FeesReceived(address indexed from, uint256 amount);
    event FeesDistributed(uint256 total, uint256 burned);
    event GaugeControllerUpdated(address indexed newController);
    event RecipientAdded(address indexed recipient);
    event ValidatorRegistered(bytes32 indexed validatorId, address rewardAddress, uint256 commissionBps);
    event Delegated(address indexed delegator, bytes32 indexed validatorId, uint256 amount);
    event RewardsClaimed(address indexed delegator, uint256 amount);

    // ════════════════════════════════════════════════════════════════
    // Setup
    // ════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy LUX token
        lux = new WLUX();

        // Deploy mocks
        vLux = new MockVLUX();
        sLux = new MockSLUX(address(lux));
        gaugeController = new MockGaugeController(address(vLux));

        // Deploy treasury contracts
        feeSplitter = new FeeSplitter(address(lux));
        synthFeeSplitter = new SynthFeeSplitter(
            address(lux),
            pol,
            daoTreasury,
            address(sLux),
            vaultReserve
        );
        validatorVault = new ValidatorVault(address(lux));

        // Mint LUX to test users
        deal(address(lux), alice, 10000 ether);
        deal(address(lux), bob, 10000 ether);
        deal(address(lux), carol, 10000 ether);
        deal(address(lux), address(this), 10000 ether);
    }

    // ════════════════════════════════════════════════════════════════
    // FeeSplitter Tests
    // ════════════════════════════════════════════════════════════════

    function test_FeeSplitter_Setup() public view {
        assertEq(address(feeSplitter.lux()), address(lux));
        assertEq(feeSplitter.owner(), owner);
        assertEq(feeSplitter.totalReceived(), 0);
        assertEq(feeSplitter.totalDistributed(), 0);
        assertEq(feeSplitter.totalBurned(), 0);
    }

    function test_FeeSplitter_SetGaugeController() public {
        vm.expectEmit(true, true, true, true);
        emit GaugeControllerUpdated(address(gaugeController));

        feeSplitter.setGaugeController(address(gaugeController));

        assertEq(address(feeSplitter.gaugeController()), address(gaugeController));
    }

    function test_FeeSplitter_SetGaugeController_RevertZeroAddress() public {
        vm.expectRevert(FeeSplitter.InvalidAddress.selector);
        feeSplitter.setGaugeController(address(0));
    }

    function test_FeeSplitter_SetGaugeController_RevertNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        feeSplitter.setGaugeController(address(gaugeController));
    }

    function test_FeeSplitter_AddRecipient() public {
        vm.expectEmit(true, true, true, true);
        emit RecipientAdded(pol);

        feeSplitter.addRecipient(pol);

        assertTrue(feeSplitter.isRecipient(pol));
        assertEq(feeSplitter.recipientCount(), 1);
        assertEq(feeSplitter.recipients(0), pol);
    }

    function test_FeeSplitter_AddRecipient_RevertDuplicate() public {
        feeSplitter.addRecipient(pol);

        vm.expectRevert(FeeSplitter.RecipientExists.selector);
        feeSplitter.addRecipient(pol);
    }

    function test_FeeSplitter_RemoveRecipient() public {
        feeSplitter.addRecipient(pol);
        feeSplitter.addRecipient(daoTreasury);

        feeSplitter.removeRecipient(pol);

        assertFalse(feeSplitter.isRecipient(pol));
        assertEq(feeSplitter.recipientCount(), 1);
    }

    function test_FeeSplitter_DepositFees() public {
        vm.startPrank(alice);
        lux.approve(address(feeSplitter), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit FeesReceived(alice, 100 ether);

        feeSplitter.depositFees(100 ether);
        vm.stopPrank();

        assertEq(feeSplitter.totalReceived(), 100 ether);
        assertEq(lux.balanceOf(address(feeSplitter)), 100 ether);
    }

    function test_FeeSplitter_Distribute_WithGauges() public {
        // Setup gauge controller
        feeSplitter.setGaugeController(address(gaugeController));

        // Add gauges
        uint256 burnGaugeId = gaugeController.addGauge(burnAddress, "Burn", 0);
        gaugeController.addGauge(pol, "POL", 0);
        gaugeController.addGauge(daoTreasury, "DAO", 0);

        feeSplitter.setBurnGaugeId(burnGaugeId);
        feeSplitter.addRecipient(pol);
        feeSplitter.addRecipient(daoTreasury);

        // Set weights: 50% burn, 30% POL, 20% DAO
        gaugeController.setWeight(burnAddress, 5000);
        gaugeController.setWeight(pol, 3000);
        gaugeController.setWeight(daoTreasury, 2000);

        // Deposit fees
        vm.prank(alice);
        lux.approve(address(feeSplitter), 1000 ether);
        vm.prank(alice);
        feeSplitter.depositFees(1000 ether);

        // Distribute
        uint256 burnBalanceBefore = lux.balanceOf(burnAddress);
        uint256 polBalanceBefore = lux.balanceOf(pol);
        uint256 daoBalanceBefore = lux.balanceOf(daoTreasury);

        feeSplitter.distribute();

        // Check distribution
        assertEq(lux.balanceOf(burnAddress) - burnBalanceBefore, 500 ether);
        assertEq(lux.balanceOf(pol) - polBalanceBefore, 300 ether);
        assertEq(lux.balanceOf(daoTreasury) - daoBalanceBefore, 200 ether);

        assertEq(feeSplitter.totalDistributed(), 1000 ether);
        assertEq(feeSplitter.totalBurned(), 500 ether);
    }

    function test_FeeSplitter_Distribute_RevertNothingToDistribute() public {
        feeSplitter.setGaugeController(address(gaugeController));

        vm.expectRevert(FeeSplitter.NothingToDistribute.selector);
        feeSplitter.distribute();
    }

    function test_FeeSplitter_GetPendingDistribution() public {
        feeSplitter.setGaugeController(address(gaugeController));
        feeSplitter.addRecipient(pol);
        feeSplitter.addRecipient(daoTreasury);

        gaugeController.addGauge(pol, "POL", 0);
        gaugeController.addGauge(daoTreasury, "DAO", 0);
        gaugeController.setWeight(pol, 6000);
        gaugeController.setWeight(daoTreasury, 4000);

        vm.prank(alice);
        lux.approve(address(feeSplitter), 1000 ether);
        vm.prank(alice);
        feeSplitter.depositFees(1000 ether);

        (uint256 balance, address[] memory addrs, uint256[] memory amounts) = feeSplitter.getPendingDistribution();

        assertEq(balance, 1000 ether);
        assertEq(addrs.length, 3); // burn + 2 recipients
        assertEq(amounts[1], 600 ether); // POL
        assertEq(amounts[2], 400 ether); // DAO
    }

    function testFuzz_FeeSplitter_Distribute(uint256 amount, uint16 weight1, uint16 weight2) public {
        amount = bound(amount, 1 ether, 1000000 ether);
        weight1 = uint16(bound(weight1, 0, 10000));
        weight2 = uint16(bound(weight2, 0, 10000 - weight1));

        feeSplitter.setGaugeController(address(gaugeController));
        feeSplitter.addRecipient(pol);
        feeSplitter.addRecipient(daoTreasury);

        gaugeController.addGauge(pol, "POL", 0);
        gaugeController.addGauge(daoTreasury, "DAO", 0);
        gaugeController.setWeight(pol, weight1);
        gaugeController.setWeight(daoTreasury, weight2);

        deal(address(lux), address(feeSplitter), amount);

        uint256 expectedPOL = (amount * weight1) / 10000;
        uint256 expectedDAO = (amount * weight2) / 10000;

        feeSplitter.distribute();

        assertEq(lux.balanceOf(pol), expectedPOL);
        assertEq(lux.balanceOf(daoTreasury), expectedDAO);
    }

    // ════════════════════════════════════════════════════════════════
    // SynthFeeSplitter Tests
    // ════════════════════════════════════════════════════════════════

    function test_SynthFeeSplitter_Setup() public view {
        assertEq(address(synthFeeSplitter.lux()), address(lux));
        assertEq(synthFeeSplitter.pol(), pol);
        assertEq(synthFeeSplitter.daoTreasury(), daoTreasury);
        assertEq(synthFeeSplitter.vaultReserve(), vaultReserve);
        assertEq(synthFeeSplitter.POL_BPS(), 100); // 1%
        assertEq(synthFeeSplitter.DAO_BPS(), 100); // 1%
        assertEq(synthFeeSplitter.STAKER_BPS(), 100); // 1%
        assertEq(synthFeeSplitter.RESERVE_BPS(), 9700); // 97%
    }

    function test_SynthFeeSplitter_DepositFees() public {
        vm.startPrank(alice);
        lux.approve(address(synthFeeSplitter), 100 ether);
        synthFeeSplitter.depositFees(100 ether);
        vm.stopPrank();

        assertEq(synthFeeSplitter.totalReceived(), 100 ether);
    }

    function test_SynthFeeSplitter_Distribute() public {
        // Deposit fees
        vm.prank(alice);
        lux.approve(address(synthFeeSplitter), 10000 ether);
        vm.prank(alice);
        synthFeeSplitter.depositFees(10000 ether);

        uint256 polBefore = lux.balanceOf(pol);
        uint256 daoBefore = lux.balanceOf(daoTreasury);
        uint256 reserveBefore = lux.balanceOf(vaultReserve);

        synthFeeSplitter.distribute();

        // Check 1% to POL, 1% to DAO, 1% to sLUX, 97% to reserve
        assertEq(lux.balanceOf(pol) - polBefore, 100 ether); // 1%
        assertEq(lux.balanceOf(daoTreasury) - daoBefore, 100 ether); // 1%
        assertEq(lux.balanceOf(vaultReserve) - reserveBefore, 9700 ether); // 97%

        assertEq(synthFeeSplitter.totalToPOL(), 100 ether);
        assertEq(synthFeeSplitter.totalToDAO(), 100 ether);
        assertEq(synthFeeSplitter.totalToReserve(), 9700 ether);
    }

    function test_SynthFeeSplitter_Distribute_ToSLUX() public {
        vm.prank(alice);
        lux.approve(address(synthFeeSplitter), 10000 ether);
        vm.prank(alice);
        synthFeeSplitter.depositFees(10000 ether);

        uint256 sLuxBefore = lux.balanceOf(address(sLux));

        synthFeeSplitter.distribute();

        // 1% should be sent to sLUX
        assertEq(lux.balanceOf(address(sLux)) - sLuxBefore, 100 ether);
        assertEq(synthFeeSplitter.totalToStakers(), 100 ether);
        assertEq(sLux.pendingRewards(), 100 ether);
    }

    function test_SynthFeeSplitter_SetRecipients() public {
        address newPOL = makeAddr("newPOL");
        synthFeeSplitter.setPOL(newPOL);
        assertEq(synthFeeSplitter.pol(), newPOL);

        address newDAO = makeAddr("newDAO");
        synthFeeSplitter.setDAOTreasury(newDAO);
        assertEq(synthFeeSplitter.daoTreasury(), newDAO);

        address newReserve = makeAddr("newReserve");
        synthFeeSplitter.setVaultReserve(newReserve);
        assertEq(synthFeeSplitter.vaultReserve(), newReserve);
    }

    function test_SynthFeeSplitter_GetPendingDistribution() public {
        vm.prank(alice);
        lux.approve(address(synthFeeSplitter), 10000 ether);
        vm.prank(alice);
        synthFeeSplitter.depositFees(10000 ether);

        (
            uint256 balance,
            uint256 toPOL,
            uint256 toDAO,
            uint256 toStakers,
            uint256 toReserve
        ) = synthFeeSplitter.getPendingDistribution();

        assertEq(balance, 10000 ether);
        assertEq(toPOL, 100 ether);
        assertEq(toDAO, 100 ether);
        assertEq(toStakers, 100 ether);
        assertEq(toReserve, 9700 ether);
    }

    function testFuzz_SynthFeeSplitter_Distribute(uint256 amount) public {
        amount = bound(amount, 1 ether, 1000000 ether);

        deal(address(lux), address(synthFeeSplitter), amount);

        uint256 expectedPOL = (amount * 100) / 10000;
        uint256 expectedDAO = (amount * 100) / 10000;
        uint256 expectedStakers = (amount * 100) / 10000;
        uint256 expectedReserve = (amount * 9700) / 10000;

        synthFeeSplitter.distribute();

        assertEq(lux.balanceOf(pol), expectedPOL);
        assertEq(lux.balanceOf(daoTreasury), expectedDAO);
        assertEq(lux.balanceOf(vaultReserve), expectedReserve);
    }

    // ════════════════════════════════════════════════════════════════
    // ValidatorVault Tests
    // ════════════════════════════════════════════════════════════════

    function test_ValidatorVault_Setup() public view {
        assertEq(address(validatorVault.lux()), address(lux));
        assertEq(validatorVault.totalDelegated(), 0);
        assertEq(validatorVault.accRewardPerShare(), 0);
        assertEq(validatorVault.slashingReserveBps(), 500); // 5%
    }

    function test_ValidatorVault_RegisterValidator() public {
        vm.expectEmit(true, true, true, true);
        emit ValidatorRegistered(validatorId1, alice, 1000);

        validatorVault.registerValidator(validatorId1, alice, 1000);

        (
            address rewardAddress,
            uint256 commissionBps,
            uint256 totalDelegatedAmount,
            uint256 pendingRewards,
            bool active
        ) = validatorVault.getValidatorInfo(validatorId1);

        assertEq(rewardAddress, alice);
        assertEq(commissionBps, 1000); // 10%
        assertEq(totalDelegatedAmount, 0);
        assertEq(pendingRewards, 0);
        assertTrue(active);
    }

    function test_ValidatorVault_RegisterValidator_RevertExcessiveCommission() public {
        vm.expectRevert(ValidatorVault.InvalidCommission.selector);
        validatorVault.registerValidator(validatorId1, alice, 2001); // > 20%
    }

    function test_ValidatorVault_UpdateValidator() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);

        validatorVault.updateValidator(validatorId1, 1500, false);

        (,uint256 commissionBps,,,bool active) = validatorVault.getValidatorInfo(validatorId1);
        assertEq(commissionBps, 1500);
        assertFalse(active);
    }

    function test_ValidatorVault_Delegate() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);

        vm.startPrank(bob);
        lux.approve(address(validatorVault), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Delegated(bob, validatorId1, 100 ether);

        validatorVault.delegate(validatorId1, 100 ether);
        vm.stopPrank();

        assertEq(validatorVault.totalDelegated(), 100 ether);
        assertEq(validatorVault.getDelegationCount(bob), 1);
    }

    function test_ValidatorVault_Delegate_RevertInactive() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);
        validatorVault.updateValidator(validatorId1, 1000, false);

        vm.startPrank(bob);
        lux.approve(address(validatorVault), 100 ether);

        vm.expectRevert(ValidatorVault.ValidatorNotActive.selector);
        validatorVault.delegate(validatorId1, 100 ether);
        vm.stopPrank();
    }

    function test_ValidatorVault_DepositRewards() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);

        vm.prank(bob);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, 100 ether);

        // Deposit rewards
        vm.prank(alice);
        lux.approve(address(validatorVault), 50 ether);
        vm.prank(alice);
        validatorVault.depositRewards(50 ether);

        assertEq(validatorVault.totalReceived(), 50 ether);
        // 5% to slashing reserve
        assertEq(validatorVault.slashingReserve(), 2.5 ether);

        // Verify rewards can be claimed
        assertGt(validatorVault.getPendingRewards(bob), 0);
    }

    function test_ValidatorVault_ClaimRewards() public {
        // Setup
        validatorVault.registerValidator(validatorId1, alice, 1000);

        vm.prank(bob);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, 100 ether);

        // Add rewards
        deal(address(lux), address(validatorVault), 200 ether);
        vm.prank(address(this));
        lux.approve(address(validatorVault), 100 ether);
        validatorVault.depositRewards(100 ether);

        uint256 pending = validatorVault.getPendingRewards(bob);
        uint256 bobBalanceBefore = lux.balanceOf(bob);

        vm.prank(bob);
        validatorVault.claimRewards();

        // Bob should receive rewards minus validator commission
        assertEq(lux.balanceOf(bob) - bobBalanceBefore, pending);
        assertGt(pending, 0);
    }

    function test_ValidatorVault_ValidatorClaimCommission() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);

        vm.prank(bob);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, 100 ether);

        // Add rewards - give to this contract and approve for depositRewards
        deal(address(lux), address(this), 100 ether);
        lux.approve(address(validatorVault), 100 ether);
        validatorVault.depositRewards(100 ether);

        // Bob claims (triggers commission calculation)
        vm.prank(bob);
        validatorVault.claimRewards();

        // Check validator has pending commission
        (,,,uint256 pendingRewards,) = validatorVault.getValidatorInfo(validatorId1);
        assertGt(pendingRewards, 0);

        uint256 aliceBalanceBefore = lux.balanceOf(alice);

        // Alice claims commission
        vm.prank(alice);
        validatorVault.claimValidatorRewards(validatorId1);

        assertGt(lux.balanceOf(alice) - aliceBalanceBefore, 0);
    }

    function test_ValidatorVault_Undelegate() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);

        vm.startPrank(bob);
        lux.approve(address(validatorVault), 100 ether);
        validatorVault.delegate(validatorId1, 100 ether);

        uint256 bobBalanceBefore = lux.balanceOf(bob);

        validatorVault.undelegate(0);
        vm.stopPrank();

        // Bob should get his delegation back
        assertEq(lux.balanceOf(bob) - bobBalanceBefore, 100 ether);
        assertEq(validatorVault.getDelegationCount(bob), 0);
        assertEq(validatorVault.totalDelegated(), 0);
    }

    function test_ValidatorVault_MultipleValidators() public {
        // Register 3 validators
        validatorVault.registerValidator(validatorId1, alice, 500);
        validatorVault.registerValidator(validatorId2, bob, 1000);
        validatorVault.registerValidator(validatorId3, carol, 1500);

        assertEq(validatorVault.getValidatorCount(), 3);

        // Different delegators to different validators
        vm.prank(alice);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(alice);
        validatorVault.delegate(validatorId1, 50 ether);

        vm.prank(bob);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(bob);
        validatorVault.delegate(validatorId2, 75 ether);

        assertEq(validatorVault.totalDelegated(), 125 ether);
    }

    function test_ValidatorVault_SetSlashingReserve() public {
        validatorVault.setSlashingReserveBps(1000); // 10%
        assertEq(validatorVault.slashingReserveBps(), 1000);
    }

    function test_ValidatorVault_SetSlashingReserve_RevertExcessive() public {
        vm.expectRevert("Max 20%");
        validatorVault.setSlashingReserveBps(2001);
    }

    function testFuzz_ValidatorVault_Delegation(
        uint256 amount,
        uint16 commission
    ) public {
        amount = bound(amount, 1 ether, 1000000 ether);
        commission = uint16(bound(commission, 0, 2000)); // Max 20%

        validatorVault.registerValidator(validatorId1, alice, commission);

        deal(address(lux), bob, amount);
        vm.prank(bob);
        lux.approve(address(validatorVault), amount);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, amount);

        assertEq(validatorVault.totalDelegated(), amount);
    }

    function testFuzz_ValidatorVault_RewardDistribution(
        uint256 delegateAmount,
        uint256 rewardAmount,
        uint16 commission
    ) public {
        delegateAmount = bound(delegateAmount, 1 ether, 100000 ether);
        rewardAmount = bound(rewardAmount, 1 ether, 10000 ether);
        commission = uint16(bound(commission, 0, 2000));

        validatorVault.registerValidator(validatorId1, alice, commission);

        deal(address(lux), bob, delegateAmount);
        vm.prank(bob);
        lux.approve(address(validatorVault), delegateAmount);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, delegateAmount);

        // Give rewards to this contract and deposit properly
        deal(address(lux), address(this), rewardAmount);
        lux.approve(address(validatorVault), rewardAmount);
        validatorVault.depositRewards(rewardAmount);

        uint256 pending = validatorVault.getPendingRewards(bob);
        assertGt(pending, 0);
    }

    // ════════════════════════════════════════════════════════════════
    // Integration Tests
    // ════════════════════════════════════════════════════════════════

    function test_Integration_FeeSplitterToValidatorVault() public {
        // Setup: FeeSplitter routes fees to ValidatorVault
        feeSplitter.setGaugeController(address(gaugeController));

        uint256 validatorGaugeId = gaugeController.addGauge(
            address(validatorVault),
            "Validators",
            0
        );
        feeSplitter.addRecipient(address(validatorVault));

        // 100% to validators
        gaugeController.setWeight(address(validatorVault), 10000);

        // Register validator and delegate
        validatorVault.registerValidator(validatorId1, alice, 1000);
        vm.prank(bob);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, 100 ether);

        // Deposit fees to FeeSplitter
        vm.prank(carol);
        lux.approve(address(feeSplitter), 100 ether);
        vm.prank(carol);
        feeSplitter.depositFees(100 ether);

        // Distribute fees
        feeSplitter.distribute();

        // Fees should be in ValidatorVault (check balance, not totalReceived since
        // totalReceived only tracks deposits via depositRewards())
        assertEq(lux.balanceOf(address(validatorVault)), 200 ether); // 100 delegated + 100 distributed
    }

    function test_Integration_CombinedTreasury() public {
        // Setup all fee recipients
        feeSplitter.setGaugeController(address(gaugeController));

        gaugeController.addGauge(address(validatorVault), "Validators", 0);
        gaugeController.addGauge(address(synthFeeSplitter), "Synths", 0);
        gaugeController.addGauge(pol, "POL", 0);

        feeSplitter.addRecipient(address(validatorVault));
        feeSplitter.addRecipient(address(synthFeeSplitter));
        feeSplitter.addRecipient(pol);

        // 40% validators, 30% synths, 30% POL
        gaugeController.setWeight(address(validatorVault), 4000);
        gaugeController.setWeight(address(synthFeeSplitter), 3000);
        gaugeController.setWeight(pol, 3000);

        // Deposit 1000 LUX in fees
        vm.prank(alice);
        lux.approve(address(feeSplitter), 1000 ether);
        vm.prank(alice);
        feeSplitter.depositFees(1000 ether);

        // Distribute
        feeSplitter.distribute();

        // Check distribution - use balances for ValidatorVault and SynthFeeSplitter since
        // totalReceived only tracks deposits via depositRewards()/depositFees()
        assertEq(lux.balanceOf(address(validatorVault)), 400 ether);
        assertEq(lux.balanceOf(address(synthFeeSplitter)), 300 ether);
        assertEq(lux.balanceOf(pol), 300 ether);
    }

    // ════════════════════════════════════════════════════════════════
    // Edge Cases
    // ════════════════════════════════════════════════════════════════

    function test_EdgeCase_ZeroWeightDistribution() public {
        feeSplitter.setGaugeController(address(gaugeController));
        feeSplitter.addRecipient(pol);

        gaugeController.addGauge(pol, "POL", 0);
        gaugeController.setWeight(pol, 0); // Zero weight

        vm.prank(alice);
        lux.approve(address(feeSplitter), 100 ether);
        vm.prank(alice);
        feeSplitter.depositFees(100 ether);

        // Should not revert
        feeSplitter.distribute();

        // POL should receive nothing
        assertEq(lux.balanceOf(pol), 0);
    }

    function test_EdgeCase_ValidatorVault_NoRewards() public {
        validatorVault.registerValidator(validatorId1, alice, 1000);

        vm.prank(bob);
        lux.approve(address(validatorVault), 100 ether);
        vm.prank(bob);
        validatorVault.delegate(validatorId1, 100 ether);

        // Try claiming without rewards
        vm.prank(bob);
        vm.expectRevert(ValidatorVault.NothingToClaim.selector);
        validatorVault.claimRewards();
    }

    function test_EdgeCase_SynthFeeSplitter_NullRecipients() public {
        // Deploy with null recipients (edge case)
        SynthFeeSplitter nullSplitter = new SynthFeeSplitter(
            address(lux),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        deal(address(lux), address(nullSplitter), 100 ether);

        // Should not revert
        nullSplitter.distribute();
    }
}

// ════════════════════════════════════════════════════════════════════
// Mock Contracts
// ════════════════════════════════════════════════════════════════════

contract MockGaugeController {
    struct Gauge {
        address recipient;
        string name;
        uint256 gaugeType;
        bool active;
    }

    address public vLux;
    Gauge[] public gauges;
    mapping(address => uint256) public gaugeIds;
    mapping(address => uint256) public weights;

    constructor(address _vLux) {
        vLux = _vLux;
        // Dummy gauge at 0
        gauges.push(Gauge(address(0), "INVALID", 0, false));
    }

    function addGauge(
        address recipient,
        string memory name,
        uint256 gaugeType
    ) external returns (uint256) {
        uint256 id = gauges.length;
        gauges.push(Gauge(recipient, name, gaugeType, true));
        gaugeIds[recipient] = id;
        return id;
    }

    function setWeight(address recipient, uint256 weight) external {
        weights[recipient] = weight;
    }

    function getWeightByRecipient(address recipient) external view returns (uint256) {
        return weights[recipient];
    }

    function gaugeCount() external view returns (uint256) {
        return gauges.length;
    }

    function getGauge(uint256 gaugeId) external view returns (
        address recipient,
        string memory name,
        uint256 gaugeType,
        bool active,
        uint256 weight
    ) {
        Gauge memory g = gauges[gaugeId];
        return (g.recipient, g.name, g.gaugeType, g.active, weights[g.recipient]);
    }
}

contract MockVLUX {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }
}

contract MockSLUX {
    ILRC20 public lux;
    uint256 public pendingRewards;

    constructor(address _lux) {
        lux = ILRC20(_lux);
    }

    function addRewards(uint256 amount) external {
        lux.transferFrom(msg.sender, address(this), amount);
        pendingRewards += amount;
    }
}
