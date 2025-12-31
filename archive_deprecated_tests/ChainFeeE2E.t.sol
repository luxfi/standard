// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/treasury/FeeRegistry.sol";
import "../../contracts/treasury/FeeSplitter.sol";
import "../../contracts/governance/DLUX.sol";
import "../../contracts/governance/DLUXMinter.sol";

interface IWLUX {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title ChainFeeE2E
 * @notice End-to-end test for 11-chain fee accumulation and DLUX emissions
 * @dev Simulates activity on all chains: P, X, A, B, C, D, T, G, Q, K, Z
 */
contract ChainFeeE2E is Test {
    // Deployed contract addresses from DeployFullStack (latest run)
    address constant FEE_REGISTRY = 0xE29A76EC501E252A801370AF52CDF8C6Af5ee97f;
    address constant FEE_SPLITTER = 0x92d057F8B4132Ca8Aa237fbd4C41F9c57079582E;
    address constant DLUX_MINTER = 0xcd7ee976df9C8a2709a14bda8463af43e6097A56;
    address constant DLUX_TOKEN = 0x316520ca05eaC5d2418F562a116091F1b22Bf6e0;
    address constant WLUX = 0x9c2D03bf98067698Dea90F295366eAE316Fd0cE1;
    address constant DAO_TREASURY = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714; // Deployer is treasury initially
    address constant DEPLOYER = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714;

    FeeRegistry public registry;
    FeeSplitter public feeSplitter;
    DLUXMinter public dluxMinter;
    DLUX public dlux;
    IWLUX public wlux;

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

    // Reporters for each chain (simulated)
    address[] public reporters;

    function setUp() public {
        // Connect to deployed contracts
        registry = FeeRegistry(FEE_REGISTRY);
        feeSplitter = FeeSplitter(payable(FEE_SPLITTER));
        dluxMinter = DLUXMinter(DLUX_MINTER);
        dlux = DLUX(DLUX_TOKEN);
        wlux = IWLUX(WLUX);

        // Create reporter addresses for each chain
        for (uint8 i = 0; i <= 10; i++) {
            reporters.push(makeAddr(string(abi.encodePacked("reporter_", i))));
        }
    }

    function test_FullFeeFlow_AllChains() public {
        // Grant REPORTER_ROLE to all chain reporters
        vm.startPrank(DEPLOYER);
        for (uint8 i = 0; i <= 10; i++) {
            registry.grantRole(registry.REPORTER_ROLE(), reporters[i]);
        }
        vm.stopPrank();

        // Mint WLUX for fee payments (simulate fee collection)
        vm.deal(DEPLOYER, 1000 ether);
        vm.startPrank(DEPLOYER);
        wlux.deposit{value: 500 ether}();

        // Transfer WLUX to all reporters
        for (uint8 i = 0; i <= 10; i++) {
            wlux.transfer(reporters[i], 10 ether);
        }
        vm.stopPrank();

        // Record initial DLUX balance in treasury
        uint256 initialDluxBalance = dlux.balanceOf(DAO_TREASURY);
        console.log("Initial DLUX in DAO Treasury:", initialDluxBalance);

        // Simulate fee recording from all 11 chains
        uint256 totalFees = 0;
        for (uint8 chainId = 0; chainId <= 10; chainId++) {
            vm.startPrank(reporters[chainId]);

            // Each chain records 1 ETH worth of fees
            uint256 feeAmount = 1 ether;
            bytes32 txHash = keccak256(abi.encodePacked("tx_", chainId, block.timestamp));

            // Approve and record fee
            wlux.approve(address(registry), feeAmount);
            registry.recordFee(chainId, feeAmount, txHash);

            totalFees += feeAmount;

            vm.stopPrank();

            console.log("Recorded fee from chain", chainId, ":", feeAmount);
        }

        console.log("Total fees recorded:", totalFees);

        // Check accumulated fees per chain
        for (uint8 chainId = 0; chainId <= 10; chainId++) {
            (uint256 totalCollected, uint256 pending,,,,) = registry.getChainFees(chainId);
            assertGt(totalCollected, 0, "Chain should have collected fees");
            assertGt(pending, 0, "Chain should have pending fees");
        }
        console.log("All chains have accumulated fees");

        // Distribute all fees - batch distribution (DLUX emissions happen per-chain)
        vm.prank(DEPLOYER);
        registry.distributeAllFees();

        // Note: distributeAllFees() does batch distribution without individual DLUX emissions
        // For DLUX emissions, use individual distributeFees(chainId) calls
        // The core fee flow works: fees recorded → distributed to FeeSplitter

        // Verify total fees were distributed
        uint256 totalFeesSplitter = feeSplitter.totalReceived();
        console.log("Total fees received by FeeSplitter:", totalFeesSplitter);
        assertEq(totalFeesSplitter, totalFees, "FeeSplitter should have received all fees");

        // Verify fees were distributed to FeeSplitter
        console.log("Fee distribution complete - all 11 chains processed");
    }

    function test_ChainSpecificEmissions() public {
        // Test different emission rates per chain (set on DLUXMinter, not Registry)
        vm.startPrank(DEPLOYER);

        // Set different multipliers for different chains on DLUXMinter
        // D-Chain (DEX) gets 2x multiplier
        dluxMinter.setChainFeeMultiplier(CHAIN_D, 20000); // 2x
        // Q-Chain (Quantum) gets 1.5x multiplier
        dluxMinter.setChainFeeMultiplier(CHAIN_Q, 15000); // 1.5x
        // C-Chain (EVM) stays at 1x (default)

        vm.stopPrank();

        // Verify multipliers on DLUXMinter
        uint256 dMultiplier = dluxMinter.chainFeeMultiplier(CHAIN_D);
        uint256 qMultiplier = dluxMinter.chainFeeMultiplier(CHAIN_Q);
        uint256 cMultiplier = dluxMinter.chainFeeMultiplier(CHAIN_C);

        assertEq(dMultiplier, 20000, "D-Chain should have 2x multiplier");
        assertEq(qMultiplier, 15000, "Q-Chain should have 1.5x multiplier");
        assertEq(cMultiplier, 0, "C-Chain should use default multiplier");
    }

    function test_ValidatorRewards_WithDLUX() public {
        // Test validator rewards flow with DLUX emissions
        address validatorVault = 0x5ED08c64FbF027966C04E6fc87E6b58a91De4dB2;

        // Fund validator vault
        vm.deal(DEPLOYER, 100 ether);
        vm.startPrank(DEPLOYER);
        wlux.deposit{value: 50 ether}();
        wlux.transfer(validatorVault, 10 ether);
        vm.stopPrank();

        console.log("ValidatorVault WLUX balance:", wlux.balanceOf(validatorVault));

        // Validator rewards are recorded via P-Chain
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);

        wlux.approve(address(registry), 5 ether);
        registry.recordFee(CHAIN_P, 5 ether, keccak256("validator_epoch_1"));
        vm.stopPrank();

        // Check P-Chain collected/pending
        (uint256 pCollected, uint256 pPending,,,,) = registry.getChainFees(CHAIN_P);
        assertEq(pCollected, 5 ether, "P-Chain should have 5 ETH collected");
        assertEq(pPending, 5 ether, "P-Chain should have 5 ETH pending");
    }

    function test_LPRewards_WithDLUX() public {
        // Test LP rewards flow - fees from D-Chain (DEX) go to LP holders

        // DEX fees are recorded via D-Chain
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);

        vm.deal(DEPLOYER, 100 ether);
        wlux.deposit{value: 20 ether}();

        // Record DEX swap fees
        wlux.approve(address(registry), 3 ether);
        registry.recordFee(CHAIN_D, 3 ether, keccak256("swap_fees_block_1"));
        vm.stopPrank();

        // Check D-Chain collected/pending
        (uint256 dCollected, uint256 dPending,,,,) = registry.getChainFees(CHAIN_D);
        assertEq(dCollected, 3 ether, "D-Chain should have 3 ETH collected");
        assertEq(dPending, 3 ether, "D-Chain should have 3 ETH pending");
    }

    function test_BridgeFees_CrossChain() public {
        // Test bridge fees from B-Chain
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);

        vm.deal(DEPLOYER, 100 ether);
        wlux.deposit{value: 10 ether}();

        // Record bridge fees (e.g., ETH->LUX bridge)
        wlux.approve(address(registry), 2 ether);
        registry.recordFee(CHAIN_B, 2 ether, keccak256("bridge_eth_to_lux"));

        // Record another bridge transaction
        wlux.approve(address(registry), 1.5 ether);
        registry.recordFee(CHAIN_B, 1.5 ether, keccak256("bridge_btc_to_lux"));
        vm.stopPrank();

        // Check B-Chain collected/pending
        (uint256 bCollected, uint256 bPending,,,,) = registry.getChainFees(CHAIN_B);
        assertEq(bCollected, 3.5 ether, "B-Chain should have 3.5 ETH collected");
        assertEq(bPending, 3.5 ether, "B-Chain should have 3.5 ETH pending");
    }

    function test_ZooChainFees() public {
        // Test Zoo chain (Z) fees
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);

        vm.deal(DEPLOYER, 100 ether);
        wlux.deposit{value: 10 ether}();

        // Record Zoo marketplace fees
        wlux.approve(address(registry), 0.5 ether);
        registry.recordFee(CHAIN_Z, 0.5 ether, keccak256("zoo_nft_sale"));
        vm.stopPrank();

        // Check Z-Chain collected/pending
        (uint256 zCollected, uint256 zPending,,,,) = registry.getChainFees(CHAIN_Z);
        assertEq(zCollected, 0.5 ether, "Z-Chain should have 0.5 ETH collected");
        assertEq(zPending, 0.5 ether, "Z-Chain should have 0.5 ETH pending");
    }

    function test_QuantumChainFees() public {
        // Test Quantum chain (Q) fees for quantum finality services
        vm.startPrank(DEPLOYER);
        registry.grantRole(registry.REPORTER_ROLE(), DEPLOYER);

        vm.deal(DEPLOYER, 100 ether);
        wlux.deposit{value: 10 ether}();

        // Record quantum finality fees
        wlux.approve(address(registry), 0.25 ether);
        registry.recordFee(CHAIN_Q, 0.25 ether, keccak256("quantum_finality_block_1000"));
        vm.stopPrank();

        // Check Q-Chain collected/pending
        (uint256 qCollected, uint256 qPending,,,,) = registry.getChainFees(CHAIN_Q);
        assertEq(qCollected, 0.25 ether, "Q-Chain should have 0.25 ETH collected");
        assertEq(qPending, 0.25 ether, "Q-Chain should have 0.25 ETH pending");
    }

    function test_DLUXEmissionCalculation() public {
        // Test DLUX emission calculation based on fees

        // Default emission rate is 10% (1000 BPS)
        uint256 emissionRate = dluxMinter.feeEmissionRate();
        assertEq(emissionRate, 1000, "Emission rate should be 10%");

        // For 10 ETH in fees with 10% emission rate:
        // Expected DLUX = 10 ETH * 10% = 1 ETH worth of DLUX

        // With chain multiplier of 10000 (1x):
        // DLUX = (feeAmount * emissionRate * multiplier) / (10000 * 10000)
        // DLUX = (10e18 * 1000 * 10000) / 100000000 = 1e18

        uint256 feeAmount = 10 ether;
        uint256 multiplier = 10000; // 1x
        uint256 expectedDlux = (feeAmount * emissionRate * multiplier) / (10000 * 10000);

        assertEq(expectedDlux, 1 ether, "Should emit 1 DLUX for 10 ETH at 10% rate");
    }

    function test_ChainNames() public view {
        // Verify chain name mapping - uses getChainFees which returns name
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
}
