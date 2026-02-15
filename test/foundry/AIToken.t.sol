// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/ai/AIToken.sol";

/**
 * @title AIToken Test Suite
 * @author Lux Network Foundation
 * @notice Comprehensive tests with mathematical proofs for AIToken
 *
 * TEST COVERAGE:
 * 1. Supply Invariants - Verify all supply caps hold
 * 2. Halving Schedule - Mathematical verification of reward decay
 * 3. Treasury Allocation - Verify 2% treasury split
 * 4. Access Control - Role-based permissions
 * 5. Bridge Operations - Mint/burn for Teleport
 * 6. Edge Cases - Overflow, underflow, boundary conditions
 * 7. Gas Optimization - Ensure reasonable gas costs
 */
contract AITokenTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 constant LP_ALLOCATION = 100_000_000 ether;
    uint256 constant MINING_ALLOCATION = 900_000_000 ether;
    uint256 constant CHAIN_SUPPLY_CAP = 1_000_000_000 ether;
    uint256 constant HALVING_INTERVAL = 63_072_000; // 4 years at 2-sec blocks
    uint256 constant INITIAL_REWARD = 7_140_000_000_000_000_000; // 7.14 ether (Bitcoin-aligned)
    uint256 constant TREASURY_BPS = 200;
    uint256 constant BPS_DENOMINATOR = 10_000;

    // Test chain IDs
    uint256 constant LUX_CHAIN_ID = 96369;
    uint256 constant HANZO_CHAIN_ID = 36963;
    uint256 constant ZOO_CHAIN_ID = 200200;
    uint256 constant ETH_CHAIN_ID = 1;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              STATE
    // ═══════════════════════════════════════════════════════════════════════════

    AIToken public token;
    address public safe;
    address public treasury;
    address public miner;
    address public bridge;
    address public user;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Set chain ID to Lux C-Chain
        vm.chainId(LUX_CHAIN_ID);

        safe = makeAddr("safe");
        treasury = makeAddr("treasury");
        miner = makeAddr("miner");
        bridge = makeAddr("bridge");
        user = makeAddr("user");

        // Deploy token as safe
        vm.prank(safe);
        token = new AIToken(safe, treasury);

        // Authorize miner and bridge
        vm.startPrank(safe);
        token.authorizeMiner(miner);
        token.authorizeBridge(bridge);
        token.setGenesis();
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         DEPLOYMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DeploymentConstants() public {
        assertEq(token.LP_ALLOCATION(), LP_ALLOCATION, "LP_ALLOCATION mismatch");
        assertEq(token.MINING_ALLOCATION(), MINING_ALLOCATION, "MINING_ALLOCATION mismatch");
        assertEq(token.CHAIN_SUPPLY_CAP(), CHAIN_SUPPLY_CAP, "CHAIN_SUPPLY_CAP mismatch");
        assertEq(token.HALVING_INTERVAL(), HALVING_INTERVAL, "HALVING_INTERVAL mismatch");
        assertEq(token.INITIAL_REWARD(), INITIAL_REWARD, "INITIAL_REWARD mismatch");
        assertEq(token.TREASURY_BPS(), TREASURY_BPS, "TREASURY_BPS mismatch");
    }

    function test_DeploymentState() public {
        assertEq(token.safe(), safe, "Safe address mismatch");
        assertEq(token.treasury(), treasury, "Treasury address mismatch");
        assertEq(token.CHAIN_ID(), LUX_CHAIN_ID, "Chain ID mismatch");
        assertEq(token.totalSupply(), 0, "Initial supply should be 0");
        assertEq(token.lpMinted(), 0, "Initial LP minted should be 0");
        assertEq(token.miningMinted(), 0, "Initial mining minted should be 0");
        assertEq(token.treasuryMinted(), 0, "Initial treasury minted should be 0");
    }

    function test_DeploymentRoles() public {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), safe), "Safe should have admin role");
        assertTrue(token.hasRole(token.PAUSER_ROLE(), safe), "Safe should have pauser role");
        assertTrue(token.hasRole(token.MINER_ROLE(), miner), "Miner should have miner role");
        assertTrue(token.hasRole(token.BRIDGE_ROLE(), bridge), "Bridge should have bridge role");
    }

    function test_InvalidChainId() public {
        vm.chainId(999); // Invalid chain ID
        vm.expectRevert(abi.encodeWithSelector(AIToken.InvalidChainId.selector, 999));
        new AIToken(safe, treasury);
    }

    function test_AllLaunchChains() public {
        uint256[10] memory launchChains = [
            uint256(96369),  // Lux
            uint256(36963),  // AI
            uint256(200200), // Zoo
            uint256(1),      // Ethereum
            uint256(8453),   // Base
            uint256(56),     // BNB
            uint256(43114),  // Avalanche
            uint256(42161),  // Arbitrum
            uint256(10),     // Optimism
            uint256(137)     // Polygon
        ];

        for (uint256 i = 0; i < launchChains.length; i++) {
            vm.chainId(launchChains[i]);
            AIToken chainToken = new AIToken(safe, treasury);
            assertEq(chainToken.CHAIN_ID(), launchChains[i], "Chain token deployed on wrong chain");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         LP ALLOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MintLP() public {
        uint256 amount = 50_000_000 ether;

        vm.prank(safe);
        token.mintLP(user, amount);

        assertEq(token.balanceOf(user), amount, "User balance mismatch");
        assertEq(token.lpMinted(), amount, "LP minted mismatch");
        assertEq(token.totalSupply(), amount, "Total supply mismatch");
    }

    function test_MintLP_FullAllocation() public {
        vm.prank(safe);
        token.mintLP(user, LP_ALLOCATION);

        assertEq(token.lpMinted(), LP_ALLOCATION, "Should mint full LP allocation");
        assertEq(token.remainingLP(), 0, "Remaining LP should be 0");
    }

    function test_MintLP_ExceedsAllocation() public {
        vm.prank(safe);
        vm.expectRevert(
            abi.encodeWithSelector(AIToken.LPCapExceeded.selector, LP_ALLOCATION + 1, LP_ALLOCATION)
        );
        token.mintLP(user, LP_ALLOCATION + 1);
    }

    function test_MintLP_MultipleCallsToMax() public {
        vm.startPrank(safe);

        // Mint in 4 chunks of 25M
        for (uint256 i = 0; i < 4; i++) {
            token.mintLP(user, 25_000_000 ether);
        }

        assertEq(token.lpMinted(), LP_ALLOCATION, "Should have minted full LP allocation");

        // Next mint should fail
        vm.expectRevert(
            abi.encodeWithSelector(AIToken.LPCapExceeded.selector, 1, 0)
        );
        token.mintLP(user, 1);

        vm.stopPrank();
    }

    function test_MintLP_ZeroAmount() public {
        vm.prank(safe);
        vm.expectRevert(AIToken.ZeroAmount.selector);
        token.mintLP(user, 0);
    }

    function test_MintLP_InvalidAddress() public {
        vm.prank(safe);
        vm.expectRevert(AIToken.InvalidAddress.selector);
        token.mintLP(address(0), 1 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         MINING REWARD TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MintReward_TreasurySplit() public {
        uint256 reward = 100 ether;
        uint256 expectedTreasury = (reward * TREASURY_BPS) / BPS_DENOMINATOR; // 2%
        uint256 expectedMiner = reward - expectedTreasury; // 98%

        vm.prank(miner);
        token.mintReward(user, reward);

        assertEq(token.balanceOf(user), expectedMiner, "Miner reward mismatch");
        assertEq(token.balanceOf(treasury), expectedTreasury, "Treasury reward mismatch");
        assertEq(token.miningMinted(), expectedMiner, "Mining minted mismatch");
        assertEq(token.treasuryMinted(), expectedTreasury, "Treasury minted mismatch");
    }

    /// @dev Mathematical proof: Treasury split is exactly 2%
    function testFuzz_TreasurySplit_MathProof(uint256 reward) public {
        // Bound reward to reasonable range
        reward = bound(reward, 1 ether, 1_000_000 ether);

        uint256 expectedTreasury = (reward * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 expectedMiner = reward - expectedTreasury;

        // Mathematical invariant: miner + treasury = reward
        assertEq(expectedMiner + expectedTreasury, reward, "Split should sum to total");

        // Mathematical invariant: treasury ≈ 2% of reward
        // Allow for rounding: treasury should be within 1 wei of exact 2%
        uint256 exactTreasury = (reward * 200) / 10000;
        assertEq(expectedTreasury, exactTreasury, "Treasury should be exactly 2%");

        vm.prank(miner);
        token.mintReward(user, reward);

        assertEq(token.balanceOf(user), expectedMiner, "Actual miner mismatch");
        assertEq(token.balanceOf(treasury), expectedTreasury, "Actual treasury mismatch");
    }

    function test_MintReward_ExceedsMiningCap() public {
        // Try to mint more than MINING_ALLOCATION
        uint256 overAmount = MINING_ALLOCATION + 1;

        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(AIToken.MiningCapExceeded.selector, overAmount, MINING_ALLOCATION)
        );
        token.mintReward(user, overAmount);
    }

    function test_MintReward_GenesisNotSet() public {
        // Deploy new token without setting genesis
        vm.chainId(HANZO_CHAIN_ID);
        AIToken noGenesis = new AIToken(safe, treasury);

        vm.prank(safe);
        noGenesis.authorizeMiner(miner);

        vm.prank(miner);
        vm.expectRevert(AIToken.GenesisNotSet.selector);
        noGenesis.mintReward(user, 100 ether);
    }

    function test_MintReward_UpdatesEpochMinted() public {
        uint256 reward = 100 ether;

        vm.prank(miner);
        token.mintReward(user, reward);

        uint256 epoch = token.currentEpoch();
        assertEq(token.epochMinted(epoch), reward, "Epoch minted should track total reward");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         HALVING SCHEDULE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Mathematical proof: Reward halves correctly at each epoch
    function test_HalvingSchedule_MathProof() public {
        uint256 genesis = token.genesisBlock();

        // Epoch 0: Initial reward
        assertEq(token.currentReward(), INITIAL_REWARD, "Epoch 0 reward should be INITIAL_REWARD");

        // Epoch 1: Half of initial
        vm.roll(genesis + HALVING_INTERVAL);
        assertEq(token.currentReward(), INITIAL_REWARD / 2, "Epoch 1 reward should be half");

        // Epoch 2: Quarter of initial
        vm.roll(genesis + HALVING_INTERVAL * 2);
        assertEq(token.currentReward(), INITIAL_REWARD / 4, "Epoch 2 reward should be quarter");

        // Epoch 3: Eighth of initial
        vm.roll(genesis + HALVING_INTERVAL * 3);
        assertEq(token.currentReward(), INITIAL_REWARD / 8, "Epoch 3 reward should be eighth");

        // Mathematical pattern: reward[n] = INITIAL_REWARD / 2^n
        for (uint256 n = 0; n < 10; n++) {
            vm.roll(genesis + HALVING_INTERVAL * n);
            uint256 expectedReward = INITIAL_REWARD >> n;
            assertEq(token.currentReward(), expectedReward, "Halving pattern mismatch");
        }
    }

    function test_HalvingSchedule_EpochCalculation() public {
        uint256 genesis = token.genesisBlock();

        // Before genesis (shouldn't happen in practice)
        assertEq(token.currentEpoch(), 0, "Should be epoch 0");

        // Middle of epoch 0
        vm.roll(genesis + HALVING_INTERVAL / 2);
        assertEq(token.currentEpoch(), 0, "Should still be epoch 0");

        // Start of epoch 1
        vm.roll(genesis + HALVING_INTERVAL);
        assertEq(token.currentEpoch(), 1, "Should be epoch 1");

        // Start of epoch 10
        vm.roll(genesis + HALVING_INTERVAL * 10);
        assertEq(token.currentEpoch(), 10, "Should be epoch 10");
    }

    function test_HalvingSchedule_RewardDecaysToZero() public {
        uint256 genesis = token.genesisBlock();

        // At epoch 64, reward should be 0 (79.4 >> 64 = 0)
        vm.roll(genesis + HALVING_INTERVAL * 64);
        assertEq(token.currentReward(), 0, "Reward should be 0 at epoch 64");

        // At epoch 100, reward should still be 0
        vm.roll(genesis + HALVING_INTERVAL * 100);
        assertEq(token.currentReward(), 0, "Reward should be 0 at epoch 100");
    }

    function test_BlocksUntilHalving() public {
        uint256 genesis = token.genesisBlock();

        // At genesis, full interval until halving
        assertEq(token.blocksUntilHalving(), HALVING_INTERVAL, "Should be full interval");

        // Midway through epoch
        vm.roll(genesis + HALVING_INTERVAL / 2);
        assertEq(token.blocksUntilHalving(), HALVING_INTERVAL / 2, "Should be half interval");

        // One block before halving
        vm.roll(genesis + HALVING_INTERVAL - 1);
        assertEq(token.blocksUntilHalving(), 1, "Should be 1 block");

        // At halving (start of new epoch)
        vm.roll(genesis + HALVING_INTERVAL);
        assertEq(token.blocksUntilHalving(), HALVING_INTERVAL, "Should reset to full interval");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BRIDGE OPERATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_BridgeMint() public {
        bytes32 teleportId = keccak256("transfer_001");
        uint256 amount = 1000 ether;

        vm.prank(bridge);
        bool success = token.bridgeMint(user, amount, teleportId);

        assertTrue(success, "Bridge mint should succeed");
        assertEq(token.balanceOf(user), amount, "User balance mismatch");
    }

    function test_BridgeBurn() public {
        // First mint some tokens
        bytes32 teleportId = keccak256("transfer_001");
        uint256 amount = 1000 ether;

        vm.prank(bridge);
        token.bridgeMint(user, amount, teleportId);

        // Now burn
        bytes32 destChain = bytes32(uint256(1)); // Ethereum

        vm.prank(user);
        bool success = token.bridgeBurn(amount, destChain);

        assertTrue(success, "Bridge burn should succeed");
        assertEq(token.balanceOf(user), 0, "User balance should be 0");
    }

    function test_BridgeMint_ExceedsSupplyCap() public {
        bytes32 teleportId = keccak256("transfer_001");

        vm.prank(bridge);
        vm.expectRevert(
            abi.encodeWithSelector(AIToken.SupplyCapExceeded.selector, CHAIN_SUPPLY_CAP + 1, CHAIN_SUPPLY_CAP)
        );
        token.bridgeMint(user, CHAIN_SUPPLY_CAP + 1, teleportId);
    }

    function test_BridgeMint_Unauthorized() public {
        bytes32 teleportId = keccak256("transfer_001");

        vm.prank(user);
        vm.expectRevert();
        token.bridgeMint(user, 1000 ether, teleportId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SUPPLY INVARIANT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Mathematical proof: Total supply = LP + Mining + Treasury
    function testFuzz_SupplyInvariant(uint256 lpAmount, uint256 miningReward) public {
        lpAmount = bound(lpAmount, 0, LP_ALLOCATION);
        miningReward = bound(miningReward, 0, MINING_ALLOCATION);

        // Mint LP
        if (lpAmount > 0) {
            vm.prank(safe);
            token.mintLP(user, lpAmount);
        }

        // Mint mining rewards
        if (miningReward > 0) {
            vm.prank(miner);
            token.mintReward(user, miningReward);
        }

        // Invariant: totalSupply = lpMinted + miningMinted + treasuryMinted
        uint256 expectedSupply = token.lpMinted() + token.miningMinted() + token.treasuryMinted();
        assertEq(token.totalSupply(), expectedSupply, "Supply invariant violated");

        // Invariant: totalSupply <= CHAIN_SUPPLY_CAP
        assertLe(token.totalSupply(), CHAIN_SUPPLY_CAP, "Supply cap violated");

        // Invariant: lpMinted <= LP_ALLOCATION
        assertLe(token.lpMinted(), LP_ALLOCATION, "LP cap violated");

        // Invariant: miningMinted + treasuryMinted <= MINING_ALLOCATION
        assertLe(
            token.miningMinted() + token.treasuryMinted(),
            MINING_ALLOCATION,
            "Mining cap violated"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         TOTAL EMISSION PROOF
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Mathematical proof: Total theoretical emission calculation (TRUE BITCOIN ALIGNMENT)
    function test_TotalEmissionCalculation() public pure {
        // Geometric series sum: S = a * (1 - r^n) / (1 - r)
        // where a = INITIAL_REWARD * HALVING_INTERVAL, r = 0.5, n → ∞
        //
        // S = INITIAL_REWARD * HALVING_INTERVAL * 2
        //   = 7.14 * 63,072,000 * 2
        //   = 900,668,160 AI
        //
        // This matches MINING_ALLOCATION (900M) within rounding error

        uint256 theoreticalMax = INITIAL_REWARD * HALVING_INTERVAL * 2;

        // Theoretical emission should be ~900M (within 1% of MINING_ALLOCATION)
        uint256 tolerance = MINING_ALLOCATION / 100; // 1% tolerance
        assertGe(theoreticalMax, MINING_ALLOCATION - tolerance, "Theoretical should be ~900M");
        assertLe(theoreticalMax, MINING_ALLOCATION + tolerance, "Theoretical should be ~900M");
    }

    /// @dev Mathematical proof: Bitcoin-aligned 4-year halving period
    function test_BitcoinAlignedHalvingPeriod() public pure {
        // 4 years in seconds = 4 * 365.25 * 24 * 60 * 60 = 126,230,400 sec
        uint256 fourYearsInSeconds = 4 * 365.25 days;

        // At 2-second blocks: 126,230,400 / 2 = 63,115,200 blocks
        uint256 expectedBlocks = fourYearsInSeconds / 2;

        // Our HALVING_INTERVAL should be approximately this value
        // Allow 1% tolerance for rounding
        uint256 tolerance = expectedBlocks / 100;
        assertGe(HALVING_INTERVAL, expectedBlocks - tolerance, "Halving interval should be ~4 years");
        assertLe(HALVING_INTERVAL, expectedBlocks + tolerance, "Halving interval should be ~4 years");
    }

    /// @dev Mathematical proof: Emission timeline matches Bitcoin
    function test_BitcoinEmissionTimeline() public pure {
        // Bitcoin: 50% mined by year 4, 75% by year 8, 99% by year 27
        // AI Token should match this exactly

        // Per-epoch supply = INITIAL_REWARD * HALVING_INTERVAL
        uint256 epoch0Supply = INITIAL_REWARD * HALVING_INTERVAL;

        // Epoch 0 should be ~50% of mining allocation
        uint256 expectedEpoch0 = MINING_ALLOCATION / 2;
        uint256 tolerance = expectedEpoch0 / 100; // 1% tolerance

        assertGe(epoch0Supply, expectedEpoch0 - tolerance, "Epoch 0 should be ~50% of mining");
        assertLe(epoch0Supply, expectedEpoch0 + tolerance, "Epoch 0 should be ~50% of mining");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OnlyAdminCanSetGenesis() public {
        vm.chainId(HANZO_CHAIN_ID);
        AIToken newToken = new AIToken(safe, treasury);

        vm.prank(user);
        vm.expectRevert();
        newToken.setGenesis();

        vm.prank(safe);
        newToken.setGenesis();
        assertGt(newToken.genesisBlock(), 0, "Genesis should be set");
    }

    function test_OnlyAdminCanMintLP() public {
        vm.prank(user);
        vm.expectRevert();
        token.mintLP(user, 1 ether);
    }

    function test_OnlyMinerCanMintReward() public {
        vm.prank(user);
        vm.expectRevert();
        token.mintReward(user, 100 ether);
    }

    function test_OnlyBridgeCanBridgeMint() public {
        vm.prank(user);
        vm.expectRevert();
        token.bridgeMint(user, 100 ether, bytes32(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         PAUSE FUNCTIONALITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Pause_BlocksMinting() public {
        vm.prank(safe);
        token.pause();

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.mintReward(user, 100 ether);
    }

    function test_Pause_BlocksBridgeOperations() public {
        vm.prank(safe);
        token.pause();

        vm.prank(bridge);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.bridgeMint(user, 100 ether, bytes32(0));
    }

    function test_Unpause_RestoresOperations() public {
        vm.prank(safe);
        token.pause();

        vm.prank(safe);
        token.unpause();

        vm.prank(miner);
        token.mintReward(user, 100 ether);
        assertGt(token.balanceOf(user), 0, "Mining should work after unpause");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ADMIN FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(safe);
        token.setTreasury(newTreasury);

        assertEq(token.treasury(), newTreasury, "Treasury should be updated");
    }

    function test_SetSafe() public {
        address newSafe = makeAddr("newSafe");

        vm.prank(safe);
        token.setSafe(newSafe);

        assertEq(token.safe(), newSafe, "Safe should be updated");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), newSafe), "New safe should have admin role");
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), safe), "Old safe should not have admin role");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         GAS OPTIMIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_MintLP() public {
        vm.prank(safe);
        uint256 gasBefore = gasleft();
        token.mintLP(user, 1 ether);
        uint256 gasUsed = gasBefore - gasleft();

        // Should be under 100k gas
        assertLt(gasUsed, 100_000, "mintLP gas too high");
    }

    function test_Gas_MintReward() public {
        vm.prank(miner);
        uint256 gasBefore = gasleft();
        token.mintReward(user, 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        // Should be under 175k gas (includes epoch tracking + treasury split)
        assertLt(gasUsed, 175_000, "mintReward gas too high");
    }

    function test_Gas_BridgeMint() public {
        vm.prank(bridge);
        uint256 gasBefore = gasleft();
        token.bridgeMint(user, 100 ether, bytes32(0));
        uint256 gasUsed = gasBefore - gasleft();

        // Should be under 100k gas
        assertLt(gasUsed, 100_000, "bridgeMint gas too high");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         STATISTICS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetStats() public {
        // Mint some LP and rewards
        vm.prank(safe);
        token.mintLP(user, 50_000_000 ether);

        vm.prank(miner);
        token.mintReward(user, 1000 ether);

        (
            uint256 totalSupply,
            uint256 lpMinted,
            uint256 miningMinted,
            uint256 treasuryMinted,
            uint256 epoch,
            uint256 reward,
            uint256 remainingLp,
            uint256 remainingMining
        ) = token.getStats();

        assertEq(totalSupply, token.totalSupply(), "Total supply mismatch");
        assertEq(lpMinted, 50_000_000 ether, "LP minted mismatch");
        assertGt(miningMinted, 0, "Mining minted should be > 0");
        assertGt(treasuryMinted, 0, "Treasury minted should be > 0");
        assertEq(epoch, 0, "Should be epoch 0");
        assertEq(reward, INITIAL_REWARD, "Should be initial reward");
        assertEq(remainingLp, LP_ALLOCATION - 50_000_000 ether, "Remaining LP mismatch");
        assertGt(remainingMining, 0, "Remaining mining should be > 0");
    }
}

/**
 * @title LaunchChains Library Tests
 * @notice Tests for the LaunchChains utility library
 */
contract LaunchChainsTest is Test {
    function test_IsLaunchChain() public pure {
        // Lux native chains
        assertTrue(LaunchChains.isLaunchChain(96369), "Lux should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(36963), "AI should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(200200), "Zoo should be launch chain");

        // External chains
        assertTrue(LaunchChains.isLaunchChain(1), "Ethereum should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(8453), "Base should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(56), "BNB should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(43114), "Avalanche should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(42161), "Arbitrum should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(10), "Optimism should be launch chain");
        assertTrue(LaunchChains.isLaunchChain(137), "Polygon should be launch chain");

        // Non-launch chains
        assertFalse(LaunchChains.isLaunchChain(999), "999 should not be launch chain");
        assertFalse(LaunchChains.isLaunchChain(0), "0 should not be launch chain");
    }

    function test_IsLuxNative() public pure {
        assertTrue(LaunchChains.isLuxNative(96369), "Lux should be native");
        assertTrue(LaunchChains.isLuxNative(36963), "AI should be native");
        assertTrue(LaunchChains.isLuxNative(200200), "Zoo should be native");

        assertFalse(LaunchChains.isLuxNative(1), "Ethereum should not be native");
        assertFalse(LaunchChains.isLuxNative(8453), "Base should not be native");
    }

    function test_IsExternal() public pure {
        assertTrue(LaunchChains.isExternal(1), "Ethereum should be external");
        assertTrue(LaunchChains.isExternal(8453), "Base should be external");
        assertTrue(LaunchChains.isExternal(56), "BNB should be external");

        assertFalse(LaunchChains.isExternal(96369), "Lux should not be external");
        assertFalse(LaunchChains.isExternal(36963), "AI should not be external");
    }

    function test_GetLaunchChains() public pure {
        uint256[10] memory chains = LaunchChains.getLaunchChains();

        assertEq(chains.length, 10, "Should have 10 launch chains");
        assertEq(chains[0], 96369, "First should be Lux");
        assertEq(chains[1], 36963, "Second should be AI");
        assertEq(chains[2], 200200, "Third should be Zoo");
    }

    function test_Constants() public pure {
        assertEq(LaunchChains.LAUNCH_CHAIN_COUNT, 10, "Should be 10 launch chains");
        assertEq(LaunchChains.PER_CHAIN_CAP, 1_000_000_000 ether, "Per chain cap should be 1B");
        assertEq(LaunchChains.LP_PER_CHAIN, 100_000_000 ether, "LP per chain should be 100M");
        assertEq(LaunchChains.MINING_PER_CHAIN, 900_000_000 ether, "Mining per chain should be 900M");
        assertEq(LaunchChains.LAUNCH_SUPPLY, 10_000_000_000 ether, "Launch supply should be 10B");
    }
}
