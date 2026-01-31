// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// Governance contracts
// Note: Governor.sol is now Zodiac-style for Safe integration
// Using DAO for simple governance tests
import {DAO} from "../../contracts/governance/DAO.sol";
import {Stake} from "../../contracts/governance/Stake.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// vLUX and Gauge contracts
import {vLUX} from "../../contracts/governance/vLUX.sol";
import {GaugeController} from "../../contracts/governance/GaugeController.sol";

// Simple DAO contract
import {DAO} from "../../contracts/governance/DAO.sol";

// Shared test mocks
import {MockERC20Solmate as MockERC20, MockTargetFull as MockTarget} from "./TestMocks.sol";

/// @title GovernanceTest
/// @notice Comprehensive tests for Lux DAO governance system
contract GovernanceTest is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════

    // Simple DAO governance (Governor.sol is Zodiac-style for Safe)
    DAO public governor;
    Stake public govToken;
    TimelockController public timelock;

    // vLUX system
    MockERC20 public lux;
    vLUX public veLux;
    GaugeController public gaugeController;

    // Simple DAO
    Stake public daoToken;
    DAO public dao;

    // Mock target
    MockTarget public target;

    // ═══════════════════════════════════════════════════════════════════════
    // USERS
    // ═══════════════════════════════════════════════════════════════════════

    address public admin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public guardian = address(0x5);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    // Governor parameters
    uint48 constant VOTING_DELAY = 1 days / 12; // 1 day in blocks (~12s blocks)
    uint32 constant VOTING_PERIOD = 7 days / 12; // 7 days in blocks
    uint256 constant PROPOSAL_THRESHOLD = 100_000e18;
    uint256 constant QUORUM_PERCENTAGE = 4; // 4%
    uint256 constant TIMELOCK_DELAY = 2 days;

    // Token supply
    uint256 constant TOTAL_SUPPLY = 100_000_000e18; // 100M tokens
    uint256 constant ALICE_TOKENS = 10_000_000e18; // 10M (10%)
    uint256 constant BOB_TOKENS = 5_000_000e18; // 5M (5%)
    uint256 constant CHARLIE_TOKENS = 1_000_000e18; // 1M (1%)

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public {
        vm.startPrank(admin);

        // ─────────────────────────────────────────────────────────────────
        // Setup LuxGovernor
        // ─────────────────────────────────────────────────────────────────

        // Deploy governance token
        Stake.Allocation[] memory allocations = new Stake.Allocation[](3);
        allocations[0] = Stake.Allocation(alice, ALICE_TOKENS);
        allocations[1] = Stake.Allocation(bob, BOB_TOKENS);
        allocations[2] = Stake.Allocation(charlie, CHARLIE_TOKENS);

        govToken = new Stake(
            "Lux Governance",
            "vLUX-GOV",
            allocations,
            admin,
            TOTAL_SUPPLY,
            false // Not locked
        );

        // Deploy timelock
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0); // Anyone can propose (governor will control)
        executors[0] = address(0); // Anyone can execute

        timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            admin
        );

        // Deploy DAO (simple governance - Governor.sol is Zodiac-style for Safe integration)
        governor = new DAO(address(govToken), admin);

        // Note: DAO uses internal timelock, no separate roles needed
        // The Zodiac-style Governor uses initialize() with Safe as vault

        // ─────────────────────────────────────────────────────────────────
        // Setup vLUX and GaugeController
        // ─────────────────────────────────────────────────────────────────

        lux = new MockERC20("Lux", "LUX", 18);
        veLux = new vLUX(address(lux));
        gaugeController = new GaugeController(address(veLux));

        // Mint LUX to users
        lux.mint(alice, 1000e18);
        lux.mint(bob, 500e18);
        lux.mint(charlie, 100e18);

        // ─────────────────────────────────────────────────────────────────
        // Setup Simple DAO
        // ─────────────────────────────────────────────────────────────────

        Stake.Allocation[] memory daoAllocations = new Stake.Allocation[](3);
        daoAllocations[0] = Stake.Allocation(alice, ALICE_TOKENS);
        daoAllocations[1] = Stake.Allocation(bob, BOB_TOKENS);
        daoAllocations[2] = Stake.Allocation(charlie, CHARLIE_TOKENS);

        daoToken = new Stake(
            "DAO Token",
            "DAO",
            daoAllocations,
            admin,
            0, // Unlimited supply
            false
        );

        dao = new DAO(address(daoToken), guardian);

        // ─────────────────────────────────────────────────────────────────
        // Setup mock target
        // ─────────────────────────────────────────────────────────────────

        target = new MockTarget();

        vm.stopPrank();

        // Users delegate to themselves for voting
        vm.prank(alice);
        govToken.delegate(alice);

        vm.prank(bob);
        govToken.delegate(bob);

        vm.prank(charlie);
        govToken.delegate(charlie);

        // Same for DAO token
        vm.prank(alice);
        daoToken.delegate(alice);

        vm.prank(bob);
        daoToken.delegate(bob);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LUXGOVERNOR TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_GovernorDeployment() public view {
        // DAO uses constants, not functions (check via constant accessors)
        assertEq(governor.VOTING_DELAY(), 1 days);
        assertEq(governor.VOTING_PERIOD(), 3 days);
        assertEq(governor.PROPOSAL_THRESHOLD(), 100_000e18);
        assertEq(governor.QUORUM_VOTES(), 1_000_000e18);
    }

    function test_CreateProposal() public {
        // Advance a block so alice's voting power is recorded
        vm.roll(block.number + 1);
        
        vm.startPrank(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            "Set value to 42"
        );

        assertTrue(proposalId > 0);
        assertEq(uint256(governor.state(proposalId)), uint256(DAO.ProposalState.Pending));

        vm.stopPrank();
    }

    function test_RevertProposalBelowThreshold() public {
        // DAO requires 100k tokens to propose, use an account with no tokens
        address nobody = address(0x9999);
        vm.startPrank(nobody);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");

        vm.stopPrank();
    }

    function test_VoteOnProposal() public {
        uint256 proposalId = _createProposal();

        // Wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Alice votes FOR
        vm.prank(alice);
        governor.castVote(proposalId, 1); // 1 = For

        // Bob votes AGAINST
        vm.prank(bob);
        governor.castVote(proposalId, 0); // 0 = Against

        DAO.ProposalInfo memory info = governor.getProposal(proposalId);

        assertEq(info.forVotes, ALICE_TOKENS);
        assertEq(info.againstVotes, BOB_TOKENS);
        assertEq(info.abstainVotes, 0);
    }

    function test_VoteWithReason() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit DAO.VoteCast(alice, proposalId, 1, ALICE_TOKENS, "Great idea!");
        governor.castVoteWithReason(proposalId, 1, "Great idea!");
    }

    function test_Delegation() public {
        // Charlie delegates to Alice
        vm.prank(charlie);
        govToken.delegate(alice);

        assertEq(govToken.getVotes(alice), ALICE_TOKENS + CHARLIE_TOKENS);
        assertEq(govToken.getVotes(charlie), 0);
    }

    function test_ProposalSucceedsWithQuorum() public {
        uint256 proposalId = _createProposal();

        // Wait for voting to start
        vm.roll(block.number + VOTING_DELAY + 1);

        // Alice votes FOR (10M = 10% > 4% quorum)
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(DAO.ProposalState.Succeeded));
    }

    function test_ProposalDefeatedWithoutQuorum() public {
        // DAO uses fixed QUORUM_VOTES = 1M tokens
        // We need votes < 1M to fail quorum
        // Give a new user 500k tokens (less than 1M quorum)
        address smallVoter = address(0x8888);
        vm.prank(admin);
        govToken.mint(smallVoter, 500_000e18);
        
        vm.prank(smallVoter);
        govToken.delegate(smallVoter);
        
        // Advance a block for delegation to take effect
        vm.roll(block.number + 1);

        uint256 proposalId = _createProposal();

        // Wait for voting to start
        vm.roll(block.number + VOTING_DELAY + 1);

        // Only smallVoter votes (500k < 1M quorum)
        vm.prank(smallVoter);
        governor.castVote(proposalId, 1);

        // Wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(DAO.ProposalState.Defeated));
    }

    function test_QueueAndExecuteProposal() public {
        uint256 proposalId = _createProposal();

        // Vote and succeed
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Queue proposal (DAO uses simple proposalId-based API)
        governor.queue(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(DAO.ProposalState.Queued));

        // Wait for timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Execute
        governor.execute(proposalId);

        assertEq(target.value(), 42);
        assertTrue(target.executed());
        assertEq(uint256(governor.state(proposalId)), uint256(DAO.ProposalState.Executed));
    }

    function test_CancelProposal() public {
        // Advance a block so alice's voting power is recorded
        vm.roll(block.number + 1);
        
        uint256 proposalId = _createProposal();

        // Alice cancels her own proposal (DAO uses simple proposalId-based API)
        vm.prank(alice);
        governor.cancel(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(DAO.ProposalState.Canceled));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VOTESTOKEN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_StakeDeployment() public view {
        assertEq(govToken.name(), "Lux Governance");
        assertEq(govToken.symbol(), "vLUX-GOV");
        assertEq(govToken.totalSupply(), ALICE_TOKENS + BOB_TOKENS + CHARLIE_TOKENS);
        assertEq(govToken.balanceOf(alice), ALICE_TOKENS);
    }

    function test_StakeMint() public {
        vm.prank(admin);
        govToken.mint(address(0xdead), 1000e18);

        assertEq(govToken.balanceOf(address(0xdead)), 1000e18);
    }

    function test_StakeBurn() public {
        vm.prank(alice);
        govToken.burn(1000e18);

        assertEq(govToken.balanceOf(alice), ALICE_TOKENS - 1000e18);
    }

    function test_StakeMaxSupply() public {
        // Deploy with max supply
        Stake.Allocation[] memory allocations = new Stake.Allocation[](1);
        allocations[0] = Stake.Allocation(alice, 1000e18);

        Stake capped = new Stake(
            "Capped",
            "CAP",
            allocations,
            admin,
            2000e18, // Max supply
            false
        );

        vm.startPrank(admin);
        capped.mint(bob, 1000e18); // OK

        vm.expectRevert();
        capped.mint(bob, 1); // Exceeds max
        vm.stopPrank();
    }

    function test_StakeLocked() public {
        // Deploy locked token
        Stake.Allocation[] memory allocations = new Stake.Allocation[](1);
        allocations[0] = Stake.Allocation(alice, 1000e18);

        Stake locked = new Stake(
            "Locked",
            "LOCK",
            allocations,
            admin,
            0,
            true // Locked
        );

        // Transfers should fail
        vm.prank(alice);
        vm.expectRevert();
        locked.transfer(bob, 100e18);

        // Unlock (disable soulbound mode)
        vm.prank(admin);
        locked.setSoulbound(false);

        // Now transfers work
        vm.prank(alice);
        locked.transfer(bob, 100e18);
        assertEq(locked.balanceOf(bob), 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // vLUX TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_vLuxCreateLock() public {
        vm.startPrank(alice);

        lux.approve(address(veLux), 1000e18);

        uint256 unlockTime = block.timestamp + 365 days;
        veLux.createLock(1000e18, unlockTime);

        (uint256 amount, uint256 end) = veLux.getLocked(alice);
        assertEq(amount, 1000e18);
        assertTrue(end > 0);

        // Voting power should be ~250 vLUX (1000 * 1year / 4years)
        uint256 votingPower = veLux.balanceOf(alice);
        assertGt(votingPower, 240e18);
        assertLt(votingPower, 260e18);

        vm.stopPrank();
    }

    function test_vLuxMaxLock() public {
        vm.startPrank(alice);

        lux.approve(address(veLux), 1000e18);

        uint256 unlockTime = block.timestamp + 4 * 365 days; // Max lock
        veLux.createLock(1000e18, unlockTime);

        // Voting power should be ~1000 vLUX (max)
        uint256 votingPower = veLux.balanceOf(alice);
        assertGt(votingPower, 990e18);
        assertLt(votingPower, 1000e18);

        vm.stopPrank();
    }

    function test_vLuxIncreaseAmount() public {
        // Warp to a reasonable timestamp first
        vm.warp(1 weeks);
        
        // Mint extra LUX for alice to test increaseAmount
        vm.prank(admin);
        lux.mint(alice, 1000e18);
        
        vm.startPrank(alice);

        lux.approve(address(veLux), 2000e18);

        uint256 unlockTime = block.timestamp + 365 days;
        veLux.createLock(1000e18, unlockTime);

        uint256 votingPowerBefore = veLux.balanceOf(alice);

        veLux.increaseAmount(500e18);

        uint256 votingPowerAfter = veLux.balanceOf(alice);
        assertGt(votingPowerAfter, votingPowerBefore);

        (uint256 amount,) = veLux.getLocked(alice);
        assertEq(amount, 1500e18);

        vm.stopPrank();
    }

    function test_vLuxIncreaseUnlockTime() public {
        vm.startPrank(alice);

        lux.approve(address(veLux), 1000e18);

        uint256 unlockTime = block.timestamp + 365 days;
        veLux.createLock(1000e18, unlockTime);

        uint256 votingPowerBefore = veLux.balanceOf(alice);

        uint256 newUnlockTime = block.timestamp + 2 * 365 days;
        veLux.increaseUnlockTime(newUnlockTime);

        uint256 votingPowerAfter = veLux.balanceOf(alice);
        assertGt(votingPowerAfter, votingPowerBefore);

        vm.stopPrank();
    }

    function test_vLuxWithdraw() public {
        // Warp to a reasonable timestamp first
        vm.warp(1 weeks);
        
        vm.startPrank(alice);

        lux.approve(address(veLux), 1000e18);

        // Use 2 weeks to ensure it passes MIN_LOCK_TIME after rounding
        uint256 unlockTime = block.timestamp + 2 weeks;
        veLux.createLock(1000e18, unlockTime);

        uint256 balanceBefore = lux.balanceOf(alice);

        // Fast forward past unlock (get the actual lock end)
        (, uint256 actualEnd) = veLux.getLocked(alice);
        vm.warp(actualEnd + 1);

        veLux.withdraw();

        uint256 balanceAfter = lux.balanceOf(alice);
        assertEq(balanceAfter - balanceBefore, 1000e18);

        (uint256 amount,) = veLux.getLocked(alice);
        assertEq(amount, 0);

        vm.stopPrank();
    }

    function test_vLuxDecay() public {
        vm.startPrank(alice);

        lux.approve(address(veLux), 1000e18);

        uint256 unlockTime = block.timestamp + 365 days;
        veLux.createLock(1000e18, unlockTime);

        uint256 votingPowerInitial = veLux.balanceOf(alice);

        // Fast forward 6 months
        vm.warp(block.timestamp + 180 days);

        uint256 votingPowerAfter = veLux.balanceOf(alice);

        // Voting power should have decayed by ~50%
        assertLt(votingPowerAfter, votingPowerInitial);
        assertGt(votingPowerAfter, votingPowerInitial / 2 - 10e18); // Allow small margin
        assertLt(votingPowerAfter, votingPowerInitial / 2 + 10e18);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GAUGECONTROLLER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_GaugeControllerAddGauge() public {
        vm.prank(admin);
        uint256 gaugeId = gaugeController.addGauge(
            address(0xdead),
            "Burn Gauge",
            0 // Protocol type
        );

        assertEq(gaugeId, 1); // ID 0 is dummy

        (address recipient, string memory name, uint256 gaugeType, bool active,) =
            gaugeController.getGauge(gaugeId);

        assertEq(recipient, address(0xdead));
        assertEq(name, "Burn Gauge");
        assertEq(gaugeType, 0);
        assertTrue(active);
    }

    function test_GaugeControllerVote() public {
        // Warp past the vote delay (10 days) before any voting
        vm.warp(block.timestamp + 11 days);
        
        // Setup: Alice creates vLUX lock
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);
        veLux.createLock(1000e18, block.timestamp + 365 days);
        vm.stopPrank();

        // Admin adds gauges
        vm.startPrank(admin);
        uint256 burnGauge = gaugeController.addGauge(address(0xdead), "Burn", 0);
        uint256 validatorGauge = gaugeController.addGauge(address(0xbeef), "Validators", 0);
        vm.stopPrank();

        // Alice votes using voteMultiple (which skips delay for batch)
        uint256[] memory gauges = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        gauges[0] = burnGauge;
        gauges[1] = validatorGauge;
        weights[0] = 6000; // 60%
        weights[1] = 4000; // 40%

        vm.prank(alice);
        gaugeController.voteMultiple(gauges, weights);

        assertEq(gaugeController.userTotalWeight(alice), 10000); // 100%
    }

    function test_GaugeControllerVoteMultiple() public {
        // Setup vLUX
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);
        veLux.createLock(1000e18, block.timestamp + 365 days);
        vm.stopPrank();

        // Add gauges
        vm.startPrank(admin);
        uint256 g1 = gaugeController.addGauge(address(0x1), "G1", 0);
        uint256 g2 = gaugeController.addGauge(address(0x2), "G2", 0);
        uint256 g3 = gaugeController.addGauge(address(0x3), "G3", 0);
        vm.stopPrank();

        // Vote for all at once
        uint256[] memory gauges = new uint256[](3);
        uint256[] memory weights = new uint256[](3);
        gauges[0] = g1;
        gauges[1] = g2;
        gauges[2] = g3;
        weights[0] = 5000; // 50%
        weights[1] = 3000; // 30%
        weights[2] = 2000; // 20%

        vm.prank(alice);
        gaugeController.voteMultiple(gauges, weights);

        assertEq(gaugeController.userTotalWeight(alice), 10000);
    }

    function test_GaugeControllerUpdateWeights() public {
        // Warp past the vote delay (10 days) before any voting
        vm.warp(block.timestamp + 11 days);
        
        // Setup
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);
        veLux.createLock(1000e18, block.timestamp + 365 days);
        vm.stopPrank();

        vm.startPrank(admin);
        uint256 gaugeId = gaugeController.addGauge(address(0xdead), "Burn", 0);
        vm.stopPrank();

        vm.prank(alice);
        gaugeController.vote(gaugeId, 10000); // 100%

        // Fast forward 1 week for weight updates
        vm.warp(block.timestamp + 7 days);

        gaugeController.updateWeights();

        uint256 weight = gaugeController.getGaugeWeightBPS(gaugeId);
        assertGt(weight, 0);
    }

    function test_GaugeControllerRevertVoteTooMuch() public {
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);
        veLux.createLock(1000e18, block.timestamp + 365 days);
        vm.stopPrank();

        vm.prank(admin);
        uint256 gaugeId = gaugeController.addGauge(address(0xdead), "Burn", 0);

        // Try to vote > 100%
        vm.prank(alice);
        vm.expectRevert();
        gaugeController.vote(gaugeId, 10001);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DAO TESTS (Simple Governor)
    // ═══════════════════════════════════════════════════════════════════════

    function test_DAOCreateProposal() public {
        // Advance a block so alice's voting power is recorded
        vm.roll(block.number + 1);

        vm.startPrank(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        uint256 proposalId = dao.propose(targets, values, calldatas, "Set to 99");

        assertEq(proposalId, 1);
        assertEq(uint256(dao.state(proposalId)), uint256(DAO.ProposalState.Pending));

        vm.stopPrank();
    }

    function test_DAOVote() public {
        uint256 proposalId = _createDAOProposal();

        // Wait for voting to start
        vm.roll(block.number + dao.VOTING_DELAY() / 12 + 1);

        vm.prank(alice);
        dao.castVote(proposalId, 1); // For

        DAO.ProposalInfo memory info = dao.getProposal(proposalId);
        assertEq(info.forVotes, ALICE_TOKENS);
    }

    function test_DAOExecute() public {
        uint256 proposalId = _createDAOProposal();

        // Vote
        vm.roll(block.number + dao.VOTING_DELAY() / 12 + 1);
        vm.prank(alice);
        dao.castVote(proposalId, 1);

        // End voting
        vm.roll(block.number + dao.VOTING_PERIOD() / 12 + 1);

        assertEq(uint256(dao.state(proposalId)), uint256(DAO.ProposalState.Succeeded));

        // Queue
        dao.queue(proposalId);

        // Wait for timelock
        vm.warp(block.timestamp + dao.TIMELOCK_DELAY() + 1);

        // Execute
        dao.execute(proposalId);

        assertEq(target.value(), 99);
        assertTrue(target.executed());
    }

    function test_DAOGuardianCancel() public {
        uint256 proposalId = _createDAOProposal();

        vm.prank(guardian);
        dao.cancel(proposalId);

        assertEq(uint256(dao.state(proposalId)), uint256(DAO.ProposalState.Canceled));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_VotingPower(uint256 amount, uint256 lockTime) public {
        amount = bound(amount, 1e18, 1_000_000e18);
        // Add buffer to MIN_LOCK_TIME to account for week rounding
        lockTime = bound(lockTime, veLux.MIN_LOCK_TIME() + 1 weeks, veLux.MAX_LOCK_TIME());

        // Warp to a reasonable timestamp (vLUX rounds to weeks)
        vm.warp(1 weeks);

        // Mint LUX
        lux.mint(address(this), amount);
        lux.approve(address(veLux), amount);

        uint256 unlockTime = block.timestamp + lockTime;
        veLux.createLock(amount, unlockTime);

        uint256 votingPower = veLux.balanceOf(address(this));

        // Voting power should be between 0 and amount
        assertGt(votingPower, 0);
        assertLe(votingPower, amount);

        // Max lock should give close to full amount
        if (lockTime >= veLux.MAX_LOCK_TIME() - 7 days) {
            assertGt(votingPower, amount * 99 / 100);
        }
    }

    function testFuzz_GaugeVoting(uint256 weight) public {
        weight = bound(weight, 0, 10000);

        // Warp past the vote delay (10 days) before voting
        vm.warp(block.timestamp + 11 days);

        // Setup
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);
        veLux.createLock(1000e18, block.timestamp + 365 days);
        vm.stopPrank();

        vm.prank(admin);
        uint256 gaugeId = gaugeController.addGauge(address(0xdead), "Test", 0);

        vm.prank(alice);
        gaugeController.vote(gaugeId, weight);

        assertEq(gaugeController.userTotalWeight(alice), weight);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════

    function test_ExpiredProposal() public {
        uint256 proposalId = _createDAOProposal();

        // Vote and queue
        vm.roll(block.number + dao.VOTING_DELAY() / 12 + 1);
        vm.prank(alice);
        dao.castVote(proposalId, 1);
        vm.roll(block.number + dao.VOTING_PERIOD() / 12 + 1);
        dao.queue(proposalId);

        // Wait past grace period
        vm.warp(block.timestamp + dao.TIMELOCK_DELAY() + dao.GRACE_PERIOD() + 1);

        assertEq(uint256(dao.state(proposalId)), uint256(DAO.ProposalState.Expired));

        vm.expectRevert();
        dao.execute(proposalId);
    }

    function test_InsufficientVotesProposal() public {
        // Advance block for voting power
        vm.roll(block.number + 1);
        
        // Charlie tries to create proposal on LuxGovernor (below threshold)
        // Note: DAO.sol has lower threshold (1% = 1M tokens), Charlie has 1M
        // But LuxGovernor has 100k threshold which Charlie exceeds
        // So we test with an address that has NO tokens
        address nobody = address(0x999);
        vm.startPrank(nobody);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(target);

        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");

        vm.stopPrank();
    }

    function test_DoubleVote() public {
        uint256 proposalId = _createDAOProposal();

        vm.roll(block.number + dao.VOTING_DELAY() / 12 + 1);

        vm.startPrank(alice);
        dao.castVote(proposalId, 1);

        vm.expectRevert();
        dao.castVote(proposalId, 1); // Should revert

        vm.stopPrank();
    }

    function test_vLuxRevertLockTooShort() public {
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);

        vm.expectRevert();
        veLux.createLock(1000e18, block.timestamp + 1 days); // < MIN_LOCK_TIME

        vm.stopPrank();
    }

    function test_vLuxRevertWithdrawBeforeUnlock() public {
        vm.startPrank(alice);
        lux.approve(address(veLux), 1000e18);
        veLux.createLock(1000e18, block.timestamp + 365 days);

        vm.expectRevert();
        veLux.withdraw(); // Lock not expired

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _createProposal() internal returns (uint256) {
        // Advance a block so alice's voting power is recorded for proposals
        vm.roll(block.number + 1);
        
        vm.startPrank(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            "Set value to 42"
        );

        vm.stopPrank();
        return proposalId;
    }

    function _createDAOProposal() internal returns (uint256) {
        // Advance a block so alice's voting power is recorded
        vm.roll(block.number + 1);

        vm.startPrank(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(target);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        uint256 proposalId = dao.propose(targets, values, calldatas, "Set to 99");

        vm.stopPrank();
        return proposalId;
    }
}
