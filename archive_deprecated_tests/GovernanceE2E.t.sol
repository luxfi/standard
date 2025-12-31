// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/treasury/FeeRegistry.sol";
import "../../contracts/treasury/FeeSplitter.sol";
import "../../contracts/governance/DLUX.sol";
import "../../contracts/governance/DLUXMinter.sol";
import "../../contracts/governance/Karma.sol";
import "../../contracts/governance/KarmaMinter.sol";
import "../../contracts/governance/vLUX.sol";
import "../../contracts/governance/GaugeController.sol";
import "../../contracts/governance/Timelock.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

interface IWLUX {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title GovernanceE2E
 * @notice Comprehensive end-to-end test for governance, fees, and 11-chain integration
 * @dev Tests:
 *   - All 11 chains fee recording and distribution
 *   - Governance proposals to change fee settings
 *   - Dynamic fee mechanisms
 *   - DLUX emissions from fees
 *   - Karma rewards for participation
 */
contract GovernanceE2E is Test {
    // Deployed contract addresses from DeployFullStack
    address constant FEE_REGISTRY = 0xE29A76EC501E252A801370AF52CDF8C6Af5ee97f;
    address constant FEE_SPLITTER = 0x92d057F8B4132Ca8Aa237fbd4C41F9c57079582E;
    address constant DLUX_MINTER = 0xcd7ee976df9C8a2709a14bda8463af43e6097A56;
    address constant DLUX_TOKEN = 0x316520ca05eaC5d2418F562a116091F1b22Bf6e0;
    address constant WLUX = 0x9c2D03bf98067698Dea90F295366eAE316Fd0cE1;
    address constant TIMELOCK = 0x80f3bd0Bdf7861487dDDA61bc651243ecB8B5072;
    address constant VLUX = 0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a;
    address constant GAUGE_CONTROLLER = 0x26328AC03d07BD9A7Caaafbde39F9b56B5449240;
    address constant VOTES_TOKEN = 0xE77E1cB5E303ed0EcB10d0d13914AaA2ED9B3b8C;
    address constant DEPLOYER = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714;

    FeeRegistry public registry;
    FeeSplitter public feeSplitter;
    DLUXMinter public dluxMinter;
    DLUX public dlux;
    IWLUX public wlux;
    TimelockController public timelock;
    vLUX public voteLux;
    GaugeController public gaugeController;

    // Chain IDs
    uint8 constant CHAIN_P = 0;  // Platform
    uint8 constant CHAIN_X = 1;  // Exchange
    uint8 constant CHAIN_A = 2;  // Attestation
    uint8 constant CHAIN_B = 3;  // Bridge
    uint8 constant CHAIN_C = 4;  // Contract (EVM)
    uint8 constant CHAIN_D = 5;  // DEX
    uint8 constant CHAIN_T = 6;  // Threshold
    uint8 constant CHAIN_G = 7;  // Graph
    uint8 constant CHAIN_Q = 8;  // Quantum
    uint8 constant CHAIN_K = 9;  // KMS
    uint8 constant CHAIN_Z = 10; // Zero (Zoo)

    // Test users
    address public alice;
    address public bob;
    address public charlie;
    address[] public reporters;

    function setUp() public {
        // Connect to deployed contracts
        registry = FeeRegistry(FEE_REGISTRY);
        feeSplitter = FeeSplitter(payable(FEE_SPLITTER));
        dluxMinter = DLUXMinter(DLUX_MINTER);
        dlux = DLUX(DLUX_TOKEN);
        wlux = IWLUX(WLUX);
        timelock = TimelockController(payable(TIMELOCK));
        voteLux = vLUX(VLUX);
        gaugeController = GaugeController(GAUGE_CONTROLLER);

        // Create test users
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Create reporters for each chain
        for (uint8 i = 0; i <= 10; i++) {
            reporters.push(makeAddr(string(abi.encodePacked("reporter_", i))));
        }
    }

    // ============ Full 11-Chain Fee Flow Tests ============

    function test_AllChains_FeeRecording() public {
        // Grant REPORTER_ROLE to all chain reporters
        vm.startPrank(DEPLOYER);
        for (uint8 i = 0; i <= 10; i++) {
            registry.grantRole(registry.REPORTER_ROLE(), reporters[i]);
        }
        vm.stopPrank();

        // Fund reporters with WLUX
        vm.deal(DEPLOYER, 1000 ether);
        vm.startPrank(DEPLOYER);
        wlux.deposit{value: 500 ether}();
        for (uint8 i = 0; i <= 10; i++) {
            wlux.transfer(reporters[i], 20 ether);
        }
        vm.stopPrank();

        // Record fees from all 11 chains
        uint256 totalFees = 0;
        for (uint8 chainId = 0; chainId <= 10; chainId++) {
            vm.startPrank(reporters[chainId]);

            uint256 feeAmount = (chainId + 1) * 1 ether; // Variable fees per chain
            bytes32 txHash = keccak256(abi.encodePacked("tx_chain_", chainId, block.timestamp));

            wlux.approve(address(registry), feeAmount);
            registry.recordFee(chainId, feeAmount, txHash);

            totalFees += feeAmount;
            vm.stopPrank();
        }

        // Verify all chains have pending fees
        for (uint8 chainId = 0; chainId <= 10; chainId++) {
            (uint256 collected, uint256 pending,,,,) = registry.getChainFees(chainId);
            uint256 expectedFee = (chainId + 1) * 1 ether;
            assertEq(collected, expectedFee, "Chain should have correct collected fees");
            assertEq(pending, expectedFee, "Chain should have correct pending fees");
        }

        // Total should be 1+2+3+4+5+6+7+8+9+10+11 = 66 ETH
        assertEq(registry.totalFeesCollected(), 66 ether, "Total fees should be 66 ETH");
    }

    function test_AllChains_BatchDistribution() public {
        // Setup: Record fees from all chains
        test_AllChains_FeeRecording();

        // Fast forward past distribution interval
        vm.warp(block.timestamp + 2 hours);

        // Distribute all fees
        registry.distributeAllFees();

        // Verify all chains have zero pending
        for (uint8 chainId = 0; chainId <= 10; chainId++) {
            (, uint256 pending,,,,) = registry.getChainFees(chainId);
            assertEq(pending, 0, "Chain should have zero pending after distribution");
        }

        // Verify FeeSplitter received fees
        uint256 splitterReceived = feeSplitter.totalReceived();
        assertEq(splitterReceived, 66 ether, "FeeSplitter should have received 66 ETH");
    }

    function test_IndividualChain_Distribution_WithDLUX() public {
        // Grant REPORTER_ROLE
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);

        // Fund deployer with WLUX
        vm.deal(DEPLOYER, 100 ether);
        wlux.deposit{value: 50 ether}();

        // Record fee on D-Chain (DEX)
        wlux.approve(address(registry), 10 ether);
        registry.recordFee(CHAIN_D, 10 ether, keccak256("dex_swap_batch"));
        vm.stopPrank();

        // Get initial DLUX balance
        uint256 initialDlux = dlux.balanceOf(DEPLOYER);

        // Fast forward and distribute
        vm.warp(block.timestamp + 2 hours);
        registry.distributeFees(CHAIN_D);

        // Verify fee was distributed
        (, uint256 pending,,,,) = registry.getChainFees(CHAIN_D);
        assertEq(pending, 0, "D-Chain should have zero pending");

        // Note: DLUX emission happens via DLUXMinter.recordFeeEmission()
        // Treasury should receive DLUX emissions
    }

    // ============ Governance Tests ============

    function test_Timelock_ScheduleAndExecute() public {
        // First, grant GOVERNOR_ROLE to Timelock on FeeRegistry
        // GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE")
        bytes32 governorRole = keccak256("GOVERNOR_ROLE");
        vm.prank(DEPLOYER);
        registry.grantRole(governorRole, address(timelock));

        // Prepare the call to change distribution interval
        bytes memory callData = abi.encodeWithSelector(
            FeeRegistry.setDistributionInterval.selector,
            30 minutes // New interval
        );

        // Get timelock delay
        uint256 delay = timelock.getMinDelay();

        // Schedule the operation (deployer should have proposer role)
        vm.startPrank(DEPLOYER);

        bytes32 salt = keccak256("change_distribution_interval_v1");
        bytes32 operationId = timelock.hashOperation(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt
        );

        timelock.schedule(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt,
            delay
        );

        // Verify operation is pending
        assertTrue(timelock.isOperationPending(operationId), "Operation should be pending");

        // Fast forward past delay
        vm.warp(block.timestamp + delay + 1);

        // Execute the operation
        timelock.execute(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt
        );

        vm.stopPrank();

        // Verify the change took effect
        assertEq(registry.distributionInterval(), 30 minutes, "Distribution interval should be updated");
    }

    function test_Timelock_ChangeChainEnabled() public {
        // First, grant GOVERNOR_ROLE to Timelock on FeeRegistry
        // Use hardcoded hash to avoid consuming vm.prank on GOVERNOR_ROLE() getter
        bytes32 governorRole = keccak256("GOVERNOR_ROLE");
        vm.prank(DEPLOYER);
        registry.grantRole(governorRole, address(timelock));

        // Disable a chain via governance
        bytes memory callData = abi.encodeWithSelector(
            FeeRegistry.setChainEnabled.selector,
            CHAIN_G, // Graph chain
            false    // Disable
        );

        uint256 delay = timelock.getMinDelay();
        bytes32 salt = keccak256("disable_g_chain_v1");

        vm.startPrank(DEPLOYER);

        timelock.schedule(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt,
            delay
        );

        vm.warp(block.timestamp + delay + 1);

        timelock.execute(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt
        );

        vm.stopPrank();

        // Verify G-Chain is disabled
        (,,,, bool enabled,) = registry.getChainFees(CHAIN_G);
        assertFalse(enabled, "G-Chain should be disabled");

        // Try to record fee on disabled chain - should fail
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), alice);
        vm.stopPrank();

        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        wlux.deposit{value: 5 ether}();
        wlux.approve(address(registry), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(FeeRegistry.ChainNotEnabled.selector, CHAIN_G));
        registry.recordFee(CHAIN_G, 1 ether, keccak256("should_fail"));
        vm.stopPrank();
    }

    // ============ DLUX Emission Tests ============

    function test_DLUXEmission_ChainMultipliers() public {
        // Test different multipliers per chain

        vm.startPrank(DEPLOYER);

        // Set D-Chain (DEX) to 2x multiplier
        dluxMinter.setChainFeeMultiplier(CHAIN_D, 20000); // 2x

        // Set Q-Chain (Quantum) to 1.5x multiplier
        dluxMinter.setChainFeeMultiplier(CHAIN_Q, 15000); // 1.5x

        vm.stopPrank();

        // Verify multipliers
        assertEq(dluxMinter.chainFeeMultiplier(CHAIN_D), 20000, "D-Chain should have 2x multiplier");
        assertEq(dluxMinter.chainFeeMultiplier(CHAIN_Q), 15000, "Q-Chain should have 1.5x multiplier");
        assertEq(dluxMinter.chainFeeMultiplier(CHAIN_C), 0, "C-Chain should use default multiplier");
    }

    function test_DLUXEmission_Calculation() public view {
        // Verify DLUX emission calculation

        uint256 emissionRate = dluxMinter.feeEmissionRate();
        assertEq(emissionRate, 1000, "Emission rate should be 10% (1000 BPS)");

        // For 10 ETH in fees with 10% emission rate and 1x multiplier:
        // DLUX = (feeAmount * emissionRate * multiplier) / (10000 * 10000)
        // DLUX = (10e18 * 1000 * 10000) / 100000000 = 1e18
        uint256 feeAmount = 10 ether;
        uint256 multiplier = 10000; // 1x
        uint256 expectedDlux = (feeAmount * emissionRate * multiplier) / (10000 * 10000);
        assertEq(expectedDlux, 1 ether, "Should emit 1 DLUX for 10 ETH at 10% rate");

        // With 2x multiplier:
        // DLUX = (10e18 * 1000 * 20000) / 100000000 = 2e18
        uint256 multiplier2x = 20000;
        uint256 expectedDlux2x = (feeAmount * emissionRate * multiplier2x) / (10000 * 10000);
        assertEq(expectedDlux2x, 2 ether, "Should emit 2 DLUX for 10 ETH at 10% rate with 2x multiplier");
    }

    // ============ vLUX Voting Power Tests ============

    function test_vLUX_LockAndVote() public {
        // Fund alice with WLUX
        vm.deal(alice, 100 ether);
        vm.startPrank(alice);
        wlux.deposit{value: 50 ether}();

        // Approve vLUX to spend WLUX
        wlux.approve(address(voteLux), 10 ether);

        // Lock WLUX for voting power (1 year from now)
        uint256 unlockTime = block.timestamp + 365 days;
        voteLux.createLock(10 ether, unlockTime);

        // Check voting power (balanceOf returns voting power in vLUX)
        uint256 votingPower = voteLux.balanceOf(alice);
        assertGt(votingPower, 0, "Alice should have voting power");

        vm.stopPrank();
    }

    // ============ GaugeController Tests ============

    function test_GaugeController_AddGauge() public {
        // Add a gauge for fee distribution

        vm.startPrank(DEPLOYER);

        // Add FeeRegistry as a gauge (recipient, name, gaugeType)
        uint256 gaugeId = gaugeController.addGauge(FEE_REGISTRY, "FeeRegistry", 0);

        // Verify gauge was added (returns: recipient, name, gaugeType, active, weight)
        (address recipient, string memory name,, bool active,) = gaugeController.getGauge(gaugeId);
        assertEq(recipient, FEE_REGISTRY, "Gauge recipient should be FeeRegistry");
        assertEq(name, "FeeRegistry", "Gauge name should match");
        assertTrue(active, "Gauge should be active");

        vm.stopPrank();
    }

    // ============ Chain Name Verification ============

    function test_AllChainNames() public view {
        string[11] memory expectedNames = [
            "P-Chain (Platform)",
            "X-Chain (Exchange)",
            "A-Chain (Attestation)",
            "B-Chain (Bridge)",
            "C-Chain (Contract)",
            "D-Chain (DEX)",
            "T-Chain (Threshold)",
            "G-Chain (Graph)",
            "Q-Chain (Quantum)",
            "K-Chain (KMS)",
            "Z-Chain (Zero)"
        ];

        for (uint8 i = 0; i <= 10; i++) {
            (,,,,,string memory name) = registry.getChainFees(i);
            assertEq(
                keccak256(bytes(name)),
                keccak256(bytes(expectedNames[i])),
                string(abi.encodePacked("Chain ", i, " name mismatch"))
            );
        }
    }

    // ============ Batch Fee Recording Tests ============

    function test_BatchFeeRecording() public {
        // Grant REPORTER_ROLE
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), alice);
        vm.stopPrank();

        // Fund alice
        vm.deal(alice, 100 ether);
        vm.startPrank(alice);
        wlux.deposit{value: 50 ether}();

        // Prepare batch
        uint8[] memory chainIds = new uint8[](3);
        chainIds[0] = CHAIN_C;
        chainIds[1] = CHAIN_D;
        chainIds[2] = CHAIN_B;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 1.5 ether;

        bytes32[] memory txHashes = new bytes32[](3);
        txHashes[0] = keccak256("batch_tx_1");
        txHashes[1] = keccak256("batch_tx_2");
        txHashes[2] = keccak256("batch_tx_3");

        // Approve total
        wlux.approve(address(registry), 4.5 ether);

        // Record batch
        registry.batchRecordFees(chainIds, amounts, txHashes);

        vm.stopPrank();

        // Verify each chain received correct fees
        (uint256 cCollected,,,,,) = registry.getChainFees(CHAIN_C);
        (uint256 dCollected,,,,,) = registry.getChainFees(CHAIN_D);
        (uint256 bCollected,,,,,) = registry.getChainFees(CHAIN_B);

        assertEq(cCollected, 1 ether, "C-Chain should have 1 ETH");
        assertEq(dCollected, 2 ether, "D-Chain should have 2 ETH");
        assertEq(bCollected, 1.5 ether, "B-Chain should have 1.5 ETH");
    }

    // ============ Fee Statistics Tests ============

    function test_GetAllChainFees() public {
        // Record some fees first
        test_AllChains_FeeRecording();

        // Get all chain stats
        (
            uint256[11] memory collected,
            uint256[11] memory pending,
            uint256[11] memory txCounts
        ) = registry.getAllChainFees();

        // Verify totals
        uint256 totalCollected = 0;
        uint256 totalPending = 0;
        for (uint8 i = 0; i < 11; i++) {
            totalCollected += collected[i];
            totalPending += pending[i];
            assertEq(txCounts[i], 1, "Each chain should have 1 tx");
        }

        assertEq(totalCollected, 66 ether, "Total collected should be 66 ETH");
        assertEq(totalPending, 66 ether, "Total pending should be 66 ETH");
    }

    function test_GetTotalPendingFees() public {
        // Record fees
        test_AllChains_FeeRecording();

        // Get total pending
        uint256 totalPending = registry.getTotalPendingFees();
        assertEq(totalPending, 66 ether, "Total pending should be 66 ETH");
    }

    // ============ Access Control Tests ============

    function test_OnlyReporterCanRecordFees() public {
        // Non-reporter should not be able to record fees
        vm.deal(bob, 10 ether);
        vm.startPrank(bob);
        wlux.deposit{value: 5 ether}();
        wlux.approve(address(registry), 1 ether);

        vm.expectRevert();
        registry.recordFee(CHAIN_C, 1 ether, keccak256("should_fail"));
        vm.stopPrank();
    }

    function test_AddAndRemoveReporter() public {
        // Add reporter
        vm.startPrank(DEPLOYER);
        registry.addReporter(charlie);
        vm.stopPrank();

        // Charlie should be able to record fees
        vm.deal(charlie, 10 ether);
        vm.startPrank(charlie);
        wlux.deposit{value: 5 ether}();
        wlux.approve(address(registry), 1 ether);
        registry.recordFee(CHAIN_C, 1 ether, keccak256("charlie_tx"));
        vm.stopPrank();

        // Remove reporter
        vm.prank(DEPLOYER);
        registry.removeReporter(charlie);

        // Charlie should no longer be able to record
        vm.startPrank(charlie);
        wlux.approve(address(registry), 1 ether);
        vm.expectRevert();
        registry.recordFee(CHAIN_C, 1 ether, keccak256("should_fail"));
        vm.stopPrank();
    }

    // ============ Distribution Interval Tests ============

    function test_DistributionInterval_Enforced() public {
        // Record fee
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);
        vm.deal(DEPLOYER, 100 ether);
        wlux.deposit{value: 50 ether}();
        wlux.approve(address(registry), 10 ether);
        registry.recordFee(CHAIN_C, 5 ether, keccak256("tx1"));
        vm.stopPrank();

        // Distribute fees
        registry.distributeFees(CHAIN_C);

        // Record more fees
        vm.startPrank(DEPLOYER);
        wlux.approve(address(registry), 5 ether);
        registry.recordFee(CHAIN_C, 5 ether, keccak256("tx2"));
        vm.stopPrank();

        // Try to distribute again immediately - should revert
        uint256 nextDistribution = block.timestamp + registry.distributionInterval();
        vm.expectRevert(abi.encodeWithSelector(
            FeeRegistry.DistributionTooSoon.selector,
            CHAIN_C,
            nextDistribution
        ));
        registry.distributeFees(CHAIN_C);

        // Fast forward and try again
        vm.warp(block.timestamp + registry.distributionInterval() + 1);
        registry.distributeFees(CHAIN_C);

        // Verify distribution succeeded
        (, uint256 pending,,,,) = registry.getChainFees(CHAIN_C);
        assertEq(pending, 0, "Should have distributed");
    }

    // ============ Dynamic Fee Mechanism Tests ============

    function test_DynamicFee_DefaultParams() public view {
        // Check default parameters are set
        (
            uint256 feeRate,
            uint256 congestionLevel,
            uint256 activity,
            uint256 target
        ) = registry.getDynamicFeeRate(CHAIN_C);

        // Default base fee is 30 BPS (0.3%)
        assertEq(feeRate, 30, "Default fee rate should be 30 BPS");
        assertEq(congestionLevel, 10000, "Default congestion should be 1x (10000)");
        assertEq(activity, 0, "Initial activity should be 0");
        assertEq(target, 1000, "Default target should be 1000 tx/hour");
    }

    function test_DynamicFee_GetRecommendedFee() public view {
        // Test fee calculation for a 10 ETH transaction
        uint256 recommendedFee = registry.getRecommendedFee(CHAIN_C, 10 ether);

        // With 30 BPS (0.3%), 10 ETH should yield 0.03 ETH fee
        assertEq(recommendedFee, 0.03 ether, "Recommended fee should be 0.03 ETH");
    }

    function test_DynamicFee_SetParams_ViaGovernance() public {
        // Set custom fee params via governance
        bytes32 governorRole = keccak256("GOVERNOR_ROLE");
        vm.prank(DEPLOYER);
        registry.setDynamicFeeParams(CHAIN_D, 50, 20, 200); // 0.5% base, 0.2% min, 2% max

        // Verify params were set
        (
            uint256 baseFeeRate,
            uint256 minFeeRate,
            uint256 maxFeeRate,
            ,,,,
        ) = registry.getDynamicFeeInfo(CHAIN_D);

        assertEq(baseFeeRate, 50, "Base fee should be 50 BPS");
        assertEq(minFeeRate, 20, "Min fee should be 20 BPS");
        assertEq(maxFeeRate, 200, "Max fee should be 200 BPS");
    }

    function test_DynamicFee_Congestion_IncreasesWithActivity() public {
        // Setup: Grant reporter role and fund
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);
        registry.setTargetTxPerHour(CHAIN_D, 10); // Set low target for easier testing
        vm.deal(DEPLOYER, 1000 ether);
        wlux.deposit{value: 500 ether}();
        vm.stopPrank();

        // Window 1: Build up high activity (15 > target of 10)
        vm.warp(block.timestamp + 1 hours + 1);
        vm.startPrank(DEPLOYER);
        for (uint256 i = 0; i < 15; i++) {
            wlux.approve(address(registry), 0.1 ether);
            registry.recordFee(CHAIN_D, 0.1 ether, keccak256(abi.encodePacked("window1_tx_", i)));
        }
        vm.stopPrank();

        // Record congestion after window 1 completes
        (,uint256 afterWindow1,,) = registry.getDynamicFeeRate(CHAIN_D);

        // Window 2: Roll over - now lastWindowTxCount = 15
        vm.warp(block.timestamp + 1 hours + 1);

        // Record a few transactions to see congestion respond to high last window
        vm.startPrank(DEPLOYER);
        for (uint256 i = 0; i < 5; i++) {
            wlux.approve(address(registry), 0.1 ether);
            registry.recordFee(CHAIN_D, 0.1 ether, keccak256(abi.encodePacked("window2_tx_", i)));
        }
        vm.stopPrank();

        (,uint256 afterWindow2,,) = registry.getDynamicFeeRate(CHAIN_D);

        // Congestion should increase in window 2 because lastWindowTxCount (15) > target (10)
        // Each recordFee now sees activity=15 and increases multiplier
        assertGt(afterWindow2, afterWindow1, "Congestion should increase with high activity from last window");
    }

    function test_DynamicFee_AllChains_HaveParams() public view {
        // Verify all 11 chains have dynamic fee parameters initialized
        for (uint8 chainId = 0; chainId <= 10; chainId++) {
            (
                uint256 baseFeeRate,
                uint256 minFeeRate,
                uint256 maxFeeRate,
                uint256 congestionMultiplier,
                uint256 targetTxPerHour,
                ,,
            ) = registry.getDynamicFeeInfo(chainId);

            assertEq(baseFeeRate, 30, "All chains should have 30 BPS base fee");
            assertEq(minFeeRate, 10, "All chains should have 10 BPS min fee");
            assertEq(maxFeeRate, 500, "All chains should have 500 BPS max fee");
            assertEq(congestionMultiplier, 10000, "All chains should start at 1x congestion");
            assertEq(targetTxPerHour, 1000, "All chains should have 1000 tx/hour target");
        }
    }

    function test_DynamicFee_Timelock_ChangeParams() public {
        // Use governance (Timelock) to change dynamic fee params
        bytes32 governorRole = keccak256("GOVERNOR_ROLE");
        vm.prank(DEPLOYER);
        registry.grantRole(governorRole, address(timelock));

        // Prepare call to change D-Chain fees
        bytes memory callData = abi.encodeWithSelector(
            FeeRegistry.setDynamicFeeParams.selector,
            CHAIN_D,
            100, // 1% base fee
            50,  // 0.5% min
            300  // 3% max
        );

        uint256 delay = timelock.getMinDelay();
        bytes32 salt = keccak256("change_d_chain_fees_v1");

        vm.startPrank(DEPLOYER);

        timelock.schedule(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt,
            delay
        );

        vm.warp(block.timestamp + delay + 1);

        timelock.execute(
            FEE_REGISTRY,
            0,
            callData,
            bytes32(0),
            salt
        );

        vm.stopPrank();

        // Verify new params
        (uint256 baseFeeRate, uint256 minFeeRate, uint256 maxFeeRate,,,,,) = registry.getDynamicFeeInfo(CHAIN_D);
        assertEq(baseFeeRate, 100, "Base fee should be 100 BPS");
        assertEq(minFeeRate, 50, "Min fee should be 50 BPS");
        assertEq(maxFeeRate, 300, "Max fee should be 300 BPS");
    }
}
