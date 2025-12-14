// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/ai/ChainConfig.sol";
import "../../contracts/ai/AIToken.sol";
import "../../contracts/ai/AIMining.sol";
import "../../contracts/ai/ComputeMarket.sol";

/**
 * @title AIMiningTest
 * @notice Unit tests for AI mining contracts
 */
contract AIMiningTest is Test {
    ChainConfig public chainConfig;
    AIToken public aiToken;
    AIMining public mining;
    ComputeMarket public market;

    address public treasury = address(0x1234);
    address public miner1 = address(0x2345);
    address public miner2 = address(0x3456);
    address public user1 = address(0x4567);

    // Chain ID constants from ChainConfig
    uint256 constant CHAIN_C = 96369;

    function setUp() public {
        // Fork to C-Chain ID
        vm.chainId(CHAIN_C);

        // Deploy contracts
        chainConfig = new ChainConfig();
        aiToken = new AIToken(treasury);
        mining = new AIMining(address(aiToken), address(chainConfig));
        market = new ComputeMarket(address(aiToken), treasury);

        // Configure
        aiToken.setGenesisBlock();
        aiToken.authorizeMiner(address(mining));
        chainConfig.authorizeMiner(CHAIN_C, address(mining));
        chainConfig.setChainActive(CHAIN_C, true);
        chainConfig.setTreasury(CHAIN_C, treasury, 200); // 2%

        mining.setMiningEnabled(true);

        // Fund test accounts
        vm.deal(miner1, 100 ether);
        vm.deal(miner2, 100 ether);
        vm.deal(user1, 100 ether);
    }

    // ============ ChainConfig Tests ============

    function test_ChainConfig_ValidChainIds() public view {
        assertTrue(chainConfig.isValidChainId(96369));   // C-Chain
        assertTrue(chainConfig.isValidChainId(36963));   // Hanzo
        assertTrue(chainConfig.isValidChainId(200200));  // Zoo
        assertFalse(chainConfig.isValidChainId(1));      // Ethereum
        assertFalse(chainConfig.isValidChainId(0));
    }

    function test_ChainConfig_GPUMultipliers() public view {
        assertEq(chainConfig.gpuMultipliers(ChainConfig.GPUTier.Consumer), 5000);      // 0.5x
        assertEq(chainConfig.gpuMultipliers(ChainConfig.GPUTier.Professional), 10000); // 1.0x
        assertEq(chainConfig.gpuMultipliers(ChainConfig.GPUTier.DataCenter), 15000);   // 1.5x
        assertEq(chainConfig.gpuMultipliers(ChainConfig.GPUTier.Sovereign), 20000);    // 2.0x
    }

    function test_ChainConfig_SetGPUMultiplier() public {
        chainConfig.setGPUMultiplier(ChainConfig.GPUTier.Consumer, 7500);
        assertEq(chainConfig.gpuMultipliers(ChainConfig.GPUTier.Consumer), 7500);
    }

    function test_ChainConfig_HalvingEpoch() public view {
        // At genesis, epoch should be 0
        uint256 epoch = chainConfig.getHalvingEpoch(CHAIN_C);
        assertEq(epoch, 0);
    }

    function test_ChainConfig_GetCurrentReward() public view {
        uint256 reward = chainConfig.getCurrentReward(CHAIN_C);
        // Base reward is 50 ether at epoch 0
        assertEq(reward, 50 ether);
    }

    function test_ChainConfig_BlocksUntilHalving() public view {
        uint256 blocks = chainConfig.blocksUntilHalving(CHAIN_C);
        // Should be close to HALVING_INTERVAL (210000)
        assertGt(blocks, 0);
        assertLe(blocks, 210_000);
    }

    // ============ AIToken Tests ============

    function test_AIToken_InitialState() public view {
        assertEq(aiToken.name(), "AI");
        assertEq(aiToken.symbol(), "AI");
        assertEq(aiToken.totalSupply(), 0);
        assertEq(aiToken.MAX_SUPPLY(), 1_000_000_000 ether);
        assertEq(aiToken.HALVING_INTERVAL(), 210_000);
        assertEq(aiToken.TREASURY_BPS(), 200);
    }

    function test_AIToken_Treasury() public view {
        assertEq(aiToken.treasury(), treasury);
    }

    function test_AIToken_SetTreasury() public {
        address newTreasury = address(0x9999);
        aiToken.setTreasury(newTreasury);
        assertEq(aiToken.treasury(), newTreasury);
    }

    function test_AIToken_MintReward() public {
        // Mining contract is authorized
        uint256 amount = 100 ether;

        vm.prank(address(mining));
        aiToken.mintReward(miner1, amount);

        // Miner gets 98% (after 2% treasury)
        uint256 minerAmount = amount - (amount * 200 / 10000);
        uint256 treasuryAmount = amount * 200 / 10000;

        assertEq(aiToken.balanceOf(miner1), minerAmount);
        assertEq(aiToken.balanceOf(treasury), treasuryAmount);
    }

    function test_AIToken_RemainingSupply() public view {
        assertEq(aiToken.remainingSupply(), 1_000_000_000 ether);
    }

    function test_AIToken_CurrentEpoch() public view {
        assertEq(aiToken.currentEpoch(), 0);
    }

    function test_AIToken_EpochReward() public view {
        // At epoch 0, reward is 1x
        assertEq(aiToken.epochReward(100 ether), 100 ether);
    }

    function test_AIToken_MiningStats() public {
        // Mint some tokens
        vm.prank(address(mining));
        aiToken.mintReward(miner1, 100 ether);

        (
            uint256 _totalSupply,
            uint256 _minerMinted,
            uint256 _treasuryMinted,
            uint256 _remaining,
            uint256 _epoch
        ) = aiToken.getMiningStats();

        assertEq(_totalSupply, 100 ether);
        assertEq(_minerMinted, 98 ether);
        assertEq(_treasuryMinted, 2 ether);
        assertEq(_remaining, 1_000_000_000 ether - 100 ether);
        assertEq(_epoch, 0);
    }

    // ============ AIMining Tests ============

    function test_AIMining_InitialState() public view {
        assertEq(address(mining.aiToken()), address(aiToken));
        assertEq(address(mining.chainConfig()), address(chainConfig));
        assertTrue(mining.miningEnabled());
    }

    function test_AIMining_EstimateReward() public view {
        // Consumer tier: 0.5x of 50 ether = 25 ether
        uint256 consumerReward = mining.estimateReward(ChainConfig.GPUTier.Consumer);
        assertEq(consumerReward, 25 ether);

        // Professional tier: 1.0x of 50 ether = 50 ether
        uint256 proReward = mining.estimateReward(ChainConfig.GPUTier.Professional);
        assertEq(proReward, 50 ether);

        // DataCenter tier: 1.5x of 50 ether = 75 ether
        uint256 dcReward = mining.estimateReward(ChainConfig.GPUTier.DataCenter);
        assertEq(dcReward, 75 ether);

        // Sovereign tier: 2.0x of 50 ether = 100 ether
        uint256 sovReward = mining.estimateReward(ChainConfig.GPUTier.Sovereign);
        assertEq(sovReward, 100 ether);
    }

    function test_AIMining_GetDifficulty() public view {
        uint256 difficulty = mining.getDifficulty();
        assertGt(difficulty, 0);
    }

    function test_AIMining_GetMiningStats() public view {
        (
            uint256 totalProofs,
            uint256 totalRewards,
            uint256 currentReward,
            uint256 difficulty
        ) = mining.getMiningStats();

        assertEq(totalProofs, 0);
        assertEq(totalRewards, 0);
        assertEq(currentReward, 50 ether);
        assertGt(difficulty, 0);
    }

    function test_AIMining_DisableMining() public {
        mining.setMiningEnabled(false);
        assertFalse(mining.miningEnabled());

        mining.setMiningEnabled(true);
        assertTrue(mining.miningEnabled());
    }

    // ============ ComputeMarket Tests ============

    function test_ComputeMarket_InitialState() public view {
        assertEq(address(market.paymentToken()), address(aiToken));
        assertEq(market.treasury(), treasury);
    }

    function test_ComputeMarket_GetMarketPrice() public view {
        uint256 price = market.getMarketPrice();
        assertEq(price, 1e15); // 0.001 AI per token initial
    }

    function test_ComputeMarket_GetMarketStats() public view {
        (
            uint256 supply,
            uint256 demand,
            uint256 price,
            uint256 utilization
        ) = market.getMarketStats();

        assertEq(supply, 0);
        assertEq(demand, 0);
        assertEq(price, 1e15);
        assertEq(utilization, 0);
    }

    function test_ComputeMarket_EstimateCost() public view {
        // 1000 tokens at 0.001 AI per token = 1 AI
        uint256 cost = market.estimateCost(1000);
        assertEq(cost, 1e15 * 1000 / 1e18);
    }

    function test_ComputeMarket_ProviderCount() public view {
        assertEq(market.getProviderCount(), 0);
    }

    // ============ Integration Tests ============

    function test_Integration_GPUTierRewardScaling() public view {
        // Verify reward scaling matches config multipliers
        uint256 baseReward = chainConfig.getCurrentReward(CHAIN_C);

        for (uint8 i = 0; i < 4; i++) {
            ChainConfig.GPUTier tier = ChainConfig.GPUTier(i);
            uint256 multiplier = chainConfig.gpuMultipliers(tier);
            uint256 expected = (baseReward * multiplier) / 10000;
            uint256 actual = mining.estimateReward(tier);
            assertEq(actual, expected);
        }
    }

    function test_Integration_TreasuryAllocation() public {
        // Verify 2% goes to treasury
        uint256 reward = 100 ether;

        vm.prank(address(mining));
        aiToken.mintReward(miner1, reward);

        uint256 treasuryBal = aiToken.balanceOf(treasury);
        assertEq(treasuryBal, 2 ether); // 2% of 100
    }
}
