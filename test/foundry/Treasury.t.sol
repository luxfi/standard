// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {ILRC20} from "../../contracts/tokens/interfaces/ILRC20.sol";

// Treasury contracts
import {FeeSplitter} from "../../contracts/treasury/FeeSplitter.sol";
import {ValidatorVault} from "../../contracts/treasury/ValidatorVault.sol";

// Dependencies
import {WLUX} from "../../contracts/tokens/WLUX.sol";

// Shared mocks
import {MockGaugeControllerFull as MockGaugeController, MockVLUX, MockSLUXRewards as MockSLUX} from "./TestMocks.sol";

/**
 * @title Treasury Test Suite
 * @notice Comprehensive tests for treasury management contracts
 *
 * Covers:
 * - FeeSplitter (gauge-based fee distribution)
 * - FeeSplitter (fixed synth protocol fees)
 * - ValidatorVault (validator/delegator rewards)
 */
contract TreasuryTest is Test {
    // ════════════════════════════════════════════════════════════════
    // Contracts
    // ════════════════════════════════════════════════════════════════

    FeeSplitter public feeSplitter;
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
    // FeeSplitter Tests
    // ════════════════════════════════════════════════════════════════

// Mock contracts moved to ./TestMocks.sol - imported at top of file
}
