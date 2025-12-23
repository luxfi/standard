// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ChainConfig
 * @notice Per-chain configuration for AI mining economics
 * @dev Stores base reward rates, GPU tier multipliers, difficulty parameters,
 *      treasury address, and halving block tracking.
 *
 * Supported Chain IDs:
 * - 96369: C-Chain (Lux mainnet)
 * - 36963: Hanzo EVM
 * - 200200: Zoo EVM
 *
 * Halving Schedule:
 * - Aligned with Bitcoin: every 210,000 blocks
 * - Initial block reward: 50 AI (configurable per chain)
 * - Halving reduces reward by 50% each epoch
 */
contract ChainConfig is Ownable {
    // ============ Constants ============

    /// @notice Halving interval (Bitcoin-aligned: 210,000 blocks)
    uint256 public constant HALVING_INTERVAL = 210_000;

    /// @notice Maximum number of halvings before reward reaches floor
    uint256 public constant MAX_HALVINGS = 32;

    /// @notice Minimum reward floor (1e12 wei = 0.000001 AI)
    uint256 public constant MIN_REWARD = 1e12;

    /// @notice Supported chain IDs
    uint256 public constant CHAIN_C = 96369;
    uint256 public constant CHAIN_HANZO = 36963;
    uint256 public constant CHAIN_ZOO = 200200;

    // ============ Types ============

    /// @notice GPU hardware tier for reward multipliers
    enum GPUTier {
        Consumer,     // 0: Consumer GPUs (RTX 30xx, 40xx)
        Professional, // 1: Professional (A4000, A5000, A6000)
        DataCenter,   // 2: Data center (A100, H100)
        Sovereign     // 3: Sovereign TEE (H100 TDX, Blackwell)
    }

    /// @notice Chain configuration parameters
    struct Config {
        uint256 baseRewardRate;        // Base reward per valid proof (in wei)
        uint256 difficultyTarget;      // Current difficulty target
        uint256 difficultyAdjustInterval; // Blocks between difficulty adjustments
        uint256 targetBlockTime;       // Target seconds between blocks
        address treasury;              // Treasury address for research allocation
        uint256 treasuryBps;           // Treasury allocation in basis points (100 = 1%)
        uint256 genesisBlock;          // Block when mining started
        bool active;                   // Whether mining is active on this chain
    }

    // ============ State ============

    /// @notice Chain ID to configuration mapping
    mapping(uint256 => Config) public configs;

    /// @notice GPU tier to multiplier mapping (basis points: 10000 = 1x)
    mapping(GPUTier => uint256) public gpuMultipliers;

    /// @notice Last difficulty adjustment block per chain
    mapping(uint256 => uint256) public lastAdjustmentBlock;

    /// @notice Cumulative proofs submitted per adjustment period
    mapping(uint256 => uint256) public proofsThisPeriod;

    /// @notice Authorized mining contracts per chain
    mapping(uint256 => mapping(address => bool)) public authorizedMiners;

    // ============ Events ============

    event ConfigUpdated(uint256 indexed chainId, Config config);
    event GPUMultiplierUpdated(GPUTier indexed tier, uint256 multiplier);
    event DifficultyAdjusted(uint256 indexed chainId, uint256 oldDifficulty, uint256 newDifficulty);
    event MinerAuthorized(uint256 indexed chainId, address indexed miner);
    event MinerRevoked(uint256 indexed chainId, address indexed miner);
    event TreasuryUpdated(uint256 indexed chainId, address indexed treasury);

    // ============ Errors ============

    error InvalidChainId(uint256 chainId);
    error ChainNotActive(uint256 chainId);
    error InvalidTreasury();
    error InvalidBasisPoints();
    error ZeroAddress();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {
        // Initialize GPU tier multipliers (basis points)
        gpuMultipliers[GPUTier.Consumer] = 5000;       // 0.5x
        gpuMultipliers[GPUTier.Professional] = 10000;  // 1.0x
        gpuMultipliers[GPUTier.DataCenter] = 15000;    // 1.5x
        gpuMultipliers[GPUTier.Sovereign] = 20000;     // 2.0x

        // Initialize default configs for supported chains
        _initializeChain(CHAIN_C, 50 ether);      // C-Chain: 50 AI base
        _initializeChain(CHAIN_HANZO, 50 ether);  // Hanzo: 50 AI base
        _initializeChain(CHAIN_ZOO, 50 ether);    // Zoo: 50 AI base
    }

    // ============ View Functions ============

    /**
     * @notice Get current halving epoch for a chain
     * @param chainId The chain ID
     * @return epoch Current halving epoch (0-indexed)
     */
    function getHalvingEpoch(uint256 chainId) public view returns (uint256 epoch) {
        Config storage config = configs[chainId];
        if (!config.active || config.genesisBlock == 0) return 0;

        uint256 blocksSinceGenesis = block.number > config.genesisBlock
            ? block.number - config.genesisBlock
            : 0;

        epoch = blocksSinceGenesis / HALVING_INTERVAL;
        if (epoch > MAX_HALVINGS) epoch = MAX_HALVINGS;
    }

    /**
     * @notice Calculate current block reward after halvings
     * @param chainId The chain ID
     * @return reward Current reward amount in wei
     */
    function getCurrentReward(uint256 chainId) public view returns (uint256 reward) {
        Config storage config = configs[chainId];
        if (!config.active) return 0;

        uint256 epoch = getHalvingEpoch(chainId);
        reward = config.baseRewardRate >> epoch; // Divide by 2^epoch

        // Apply minimum floor
        if (reward < MIN_REWARD) reward = MIN_REWARD;
    }

    /**
     * @notice Calculate reward for a given GPU tier
     * @param chainId The chain ID
     * @param tier The GPU hardware tier
     * @return reward Reward amount adjusted for GPU tier
     */
    function getRewardForTier(uint256 chainId, GPUTier tier) external view returns (uint256 reward) {
        uint256 baseReward = getCurrentReward(chainId);
        uint256 multiplier = gpuMultipliers[tier];
        reward = (baseReward * multiplier) / 10000;
    }

    /**
     * @notice Get blocks until next halving
     * @param chainId The chain ID
     * @return blocks Number of blocks until next halving
     */
    function blocksUntilHalving(uint256 chainId) external view returns (uint256 blocks) {
        Config storage config = configs[chainId];
        if (!config.active || config.genesisBlock == 0) return 0;

        uint256 blocksSinceGenesis = block.number > config.genesisBlock
            ? block.number - config.genesisBlock
            : 0;

        uint256 blocksIntoEpoch = blocksSinceGenesis % HALVING_INTERVAL;
        blocks = HALVING_INTERVAL - blocksIntoEpoch;
    }

    /**
     * @notice Check if chain ID is supported
     * @param chainId The chain ID to check
     * @return supported True if chain is supported
     */
    function isValidChainId(uint256 chainId) public pure returns (bool supported) {
        return chainId == CHAIN_C || chainId == CHAIN_HANZO || chainId == CHAIN_ZOO;
    }

    /**
     * @notice Get full config for a chain
     * @param chainId The chain ID
     * @return config The chain configuration
     */
    function getConfig(uint256 chainId) external view returns (Config memory config) {
        return configs[chainId];
    }

    // ============ Admin Functions ============

    /**
     * @notice Update chain configuration
     * @param chainId The chain ID to configure
     * @param baseRewardRate Base reward per proof
     * @param difficultyTarget Initial difficulty target
     * @param difficultyAdjustInterval Blocks between adjustments
     * @param targetBlockTime Target block time in seconds
     */
    function setConfig(
        uint256 chainId,
        uint256 baseRewardRate,
        uint256 difficultyTarget,
        uint256 difficultyAdjustInterval,
        uint256 targetBlockTime
    ) external onlyOwner {
        if (!isValidChainId(chainId)) revert InvalidChainId(chainId);

        Config storage config = configs[chainId];
        config.baseRewardRate = baseRewardRate;
        config.difficultyTarget = difficultyTarget;
        config.difficultyAdjustInterval = difficultyAdjustInterval;
        config.targetBlockTime = targetBlockTime;

        emit ConfigUpdated(chainId, config);
    }

    /**
     * @notice Set treasury address and allocation for a chain
     * @param chainId The chain ID
     * @param treasury Treasury address
     * @param bps Basis points for treasury allocation (max 1000 = 10%)
     */
    function setTreasury(uint256 chainId, address treasury, uint256 bps) external onlyOwner {
        if (!isValidChainId(chainId)) revert InvalidChainId(chainId);
        if (treasury == address(0)) revert ZeroAddress();
        if (bps > 1000) revert InvalidBasisPoints(); // Max 10%

        Config storage config = configs[chainId];
        config.treasury = treasury;
        config.treasuryBps = bps;

        emit TreasuryUpdated(chainId, treasury);
    }

    /**
     * @notice Update GPU tier multiplier
     * @param tier The GPU tier
     * @param multiplier New multiplier in basis points
     */
    function setGPUMultiplier(GPUTier tier, uint256 multiplier) external onlyOwner {
        gpuMultipliers[tier] = multiplier;
        emit GPUMultiplierUpdated(tier, multiplier);
    }

    /**
     * @notice Activate or deactivate mining on a chain
     * @param chainId The chain ID
     * @param active Whether mining should be active
     */
    function setChainActive(uint256 chainId, bool active) external onlyOwner {
        if (!isValidChainId(chainId)) revert InvalidChainId(chainId);
        configs[chainId].active = active;
    }

    /**
     * @notice Authorize a mining contract
     * @param chainId The chain ID
     * @param miner The mining contract address
     */
    function authorizeMiner(uint256 chainId, address miner) external onlyOwner {
        if (!isValidChainId(chainId)) revert InvalidChainId(chainId);
        if (miner == address(0)) revert ZeroAddress();

        authorizedMiners[chainId][miner] = true;
        emit MinerAuthorized(chainId, miner);
    }

    /**
     * @notice Revoke mining contract authorization
     * @param chainId The chain ID
     * @param miner The mining contract address
     */
    function revokeMiner(uint256 chainId, address miner) external onlyOwner {
        authorizedMiners[chainId][miner] = false;
        emit MinerRevoked(chainId, miner);
    }

    // ============ Internal Functions ============

    /**
     * @notice Initialize default config for a chain
     * @param chainId The chain ID
     * @param baseReward Base reward amount
     */
    function _initializeChain(uint256 chainId, uint256 baseReward) internal {
        configs[chainId] = Config({
            baseRewardRate: baseReward,
            difficultyTarget: 2 ** 240, // Initial easy difficulty
            difficultyAdjustInterval: 2016, // ~2 weeks at 10min blocks
            targetBlockTime: 600, // 10 minutes (Bitcoin-like)
            treasury: address(0), // Set later
            treasuryBps: 200, // 2% to research treasury
            genesisBlock: 0, // Set when mining starts
            active: false // Activate explicitly
        });
    }

    // ============ Mining Contract Interface ============

    /**
     * @notice Record proof submission for difficulty adjustment
     * @dev Called by authorized mining contracts
     * @param chainId The chain ID
     */
    function recordProof(uint256 chainId) external {
        if (!authorizedMiners[chainId][msg.sender]) revert InvalidChainId(chainId);

        proofsThisPeriod[chainId]++;

        Config storage config = configs[chainId];
        uint256 blocksSinceAdjust = block.number - lastAdjustmentBlock[chainId];

        if (blocksSinceAdjust >= config.difficultyAdjustInterval) {
            _adjustDifficulty(chainId);
        }
    }

    /**
     * @notice Adjust difficulty based on proof rate
     * @param chainId The chain ID
     */
    function _adjustDifficulty(uint256 chainId) internal {
        Config storage config = configs[chainId];

        uint256 proofs = proofsThisPeriod[chainId];
        uint256 expectedProofs = config.difficultyAdjustInterval;

        uint256 oldDifficulty = config.difficultyTarget;
        uint256 newDifficulty;

        if (proofs > expectedProofs * 2) {
            // Too many proofs, increase difficulty (lower target)
            newDifficulty = oldDifficulty / 2;
        } else if (proofs < expectedProofs / 2) {
            // Too few proofs, decrease difficulty (raise target)
            newDifficulty = oldDifficulty * 2;
            if (newDifficulty > 2 ** 255) newDifficulty = 2 ** 255; // Cap
        } else {
            // Proportional adjustment
            newDifficulty = (oldDifficulty * expectedProofs) / proofs;
        }

        config.difficultyTarget = newDifficulty;
        lastAdjustmentBlock[chainId] = block.number;
        proofsThisPeriod[chainId] = 0;

        emit DifficultyAdjusted(chainId, oldDifficulty, newDifficulty);
    }
}
