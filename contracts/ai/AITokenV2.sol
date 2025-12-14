// SPDX-License-Identifier: MIT
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AIToken
 * @notice Proof of AI Token - Teleport-enabled across 10 launch chains
 *
 * TOKENOMICS (Global):
 * ┌─────────────────────────────────────────────────────────────┐
 * │  1B AI - LP Allocation (100M per chain × 10 chains)        │
 * │  1B AI - Mining Airdrop (Bitcoin reward schedule)          │
 * │  ───────────────────────────────────────────────────────── │
 * │  2B AI - Total Initial Supply                              │
 * │                                                             │
 * │  Future: Up to 1T AI by unlocking top 100 EVMs             │
 * └─────────────────────────────────────────────────────────────┘
 *
 * LAUNCH CHAINS (10):
 * - Lux C-Chain (96369)    - Hanzo EVM (36963)    - Zoo EVM (200200)
 * - Ethereum (1)           - Base (8453)          - BNB Chain (56)
 * - Avalanche (43114)      - Arbitrum (42161)     - Optimism (10)
 * - Polygon (137)
 *
 * PRICING:
 * - Initial: ~$1/AI
 * - $100M liquidity available per chain
 * - Each chain competes on price/compute performance
 *
 * ARCHITECTURE:
 * - Lux network = source of truth (Warp messaging)
 * - Teleport bridge for external chains (MPC threshold)
 * - Safe multi-sig manages contracts initially
 * - Each chain can set own mining rates/prices
 */
contract AIToken is ERC20, AccessControl, ReentrancyGuard {
    // ============ Constants ============

    /// @notice LP allocation per chain: 100 million tokens
    uint256 public constant LP_ALLOCATION = 100_000_000 ether;

    /// @notice Mining allocation per chain: 100 million tokens (Bitcoin schedule)
    uint256 public constant MINING_ALLOCATION = 100_000_000 ether;

    /// @notice Total per-chain cap: 200 million tokens
    uint256 public constant CHAIN_SUPPLY_CAP = 200_000_000 ether;

    /// @notice Halving interval in blocks (Bitcoin-aligned)
    uint256 public constant HALVING_INTERVAL = 210_000;

    /// @notice Initial block reward: 50 AI
    uint256 public constant INITIAL_REWARD = 50 ether;

    /// @notice Treasury allocation in basis points (200 = 2%)
    uint256 public constant TREASURY_BPS = 200;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Roles ============

    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    // ============ State ============

    /// @notice Safe multi-sig address
    address public safe;

    /// @notice Treasury address
    address public treasury;

    /// @notice Genesis block for mining
    uint256 public genesisBlock;

    /// @notice Total minted via LP allocation
    uint256 public lpMinted;

    /// @notice Total minted via mining
    uint256 public miningMinted;

    /// @notice Total minted to treasury
    uint256 public treasuryMinted;

    /// @notice Chain ID
    uint256 public immutable CHAIN_ID;

    /// @notice Per-epoch mining stats
    mapping(uint256 => uint256) public epochMinted;

    // ============ Events ============

    event LPMinted(address indexed recipient, uint256 amount);
    event MiningReward(address indexed miner, uint256 amount, uint256 treasuryAmount, uint256 epoch);
    event BridgeMint(address indexed to, uint256 amount, bytes32 indexed teleportId);
    event BridgeBurn(address indexed from, uint256 amount, bytes32 indexed destChainId);
    event GenesisSet(uint256 blockNumber);

    // ============ Errors ============

    error SupplyCapExceeded();
    error LPCapExceeded();
    error MiningCapExceeded();
    error GenesisAlreadySet();
    error GenesisNotSet();
    error InvalidAddress();
    error ZeroAmount();

    // ============ Constructor ============

    constructor(address _safe, address _treasury) ERC20("AI", "AI") {
        if (_safe == address(0) || _treasury == address(0)) revert InvalidAddress();

        CHAIN_ID = block.chainid;
        safe = _safe;
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _safe);
    }

    // ============ LP Functions ============

    /**
     * @notice Mint LP allocation (100M per chain)
     * @dev Called by Safe to seed liquidity pools
     */
    function mintLP(address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        if (lpMinted + amount > LP_ALLOCATION) revert LPCapExceeded();

        lpMinted += amount;
        _mint(recipient, amount);

        emit LPMinted(recipient, amount);
    }

    // ============ Bridge Functions ============

    /**
     * @notice Mint via Teleport bridge
     */
    function bridgeMint(
        address to,
        uint256 amount,
        bytes32 teleportId
    ) external onlyRole(BRIDGE_ROLE) returns (bool) {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        if (totalSupply() + amount > CHAIN_SUPPLY_CAP) revert SupplyCapExceeded();

        _mint(to, amount);
        emit BridgeMint(to, amount, teleportId);
        return true;
    }

    /**
     * @notice Burn for cross-chain transfer
     */
    function bridgeBurn(uint256 amount, bytes32 destChainId) external returns (bool) {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
        emit BridgeBurn(msg.sender, amount, destChainId);
        return true;
    }

    // ============ Mining Functions ============

    /**
     * @notice Mint mining reward (Bitcoin schedule)
     */
    function mintReward(address miner, uint256 amount) external nonReentrant onlyRole(MINER_ROLE) {
        if (genesisBlock == 0) revert GenesisNotSet();
        if (amount == 0) revert ZeroAmount();

        uint256 treasuryAmount = (amount * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 minerAmount = amount - treasuryAmount;
        uint256 total = minerAmount + treasuryAmount;

        if (miningMinted + treasuryMinted + total > MINING_ALLOCATION) revert MiningCapExceeded();

        uint256 epoch = currentEpoch();
        epochMinted[epoch] += total;
        miningMinted += minerAmount;
        treasuryMinted += treasuryAmount;

        _mint(miner, minerAmount);
        if (treasuryAmount > 0) {
            _mint(treasury, treasuryAmount);
        }

        emit MiningReward(miner, minerAmount, treasuryAmount, epoch);
    }

    // ============ View Functions ============

    function currentEpoch() public view returns (uint256) {
        if (genesisBlock == 0) return 0;
        uint256 blocks = block.number > genesisBlock ? block.number - genesisBlock : 0;
        return blocks / HALVING_INTERVAL;
    }

    function currentReward() public view returns (uint256) {
        uint256 epoch = currentEpoch();
        if (epoch >= 64) return 0;
        return INITIAL_REWARD >> epoch;
    }

    function remainingLP() public view returns (uint256) {
        return LP_ALLOCATION - lpMinted;
    }

    function remainingMining() public view returns (uint256) {
        return MINING_ALLOCATION - miningMinted - treasuryMinted;
    }

    function getStats() external view returns (
        uint256 _totalSupply,
        uint256 _lpMinted,
        uint256 _miningMinted,
        uint256 _treasuryMinted,
        uint256 _epoch,
        uint256 _reward
    ) {
        return (totalSupply(), lpMinted, miningMinted, treasuryMinted, currentEpoch(), currentReward());
    }

    // ============ Admin Functions ============

    function setGenesis() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (genesisBlock != 0) revert GenesisAlreadySet();
        genesisBlock = block.number;
        emit GenesisSet(block.number);
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress();
        treasury = _treasury;
    }

    function setSafe(address _safe) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_safe == address(0)) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, _safe);
        _revokeRole(DEFAULT_ADMIN_ROLE, safe);
        safe = _safe;
    }

    function authorizeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINER_ROLE, miner);
    }

    function authorizeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BRIDGE_ROLE, bridge);
    }

    function revokeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINER_ROLE, miner);
    }

    function revokeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BRIDGE_ROLE, bridge);
    }
}

/**
 * @title LaunchChains
 * @notice Configuration for 10-chain launch
 */
library LaunchChains {
    // Lux Native (3 chains)
    uint256 constant LUX = 96369;
    uint256 constant HANZO = 36963;
    uint256 constant ZOO = 200200;

    // External EVMs (7 chains)
    uint256 constant ETHEREUM = 1;
    uint256 constant BASE = 8453;
    uint256 constant BNB = 56;
    uint256 constant AVALANCHE = 43114;
    uint256 constant ARBITRUM = 42161;
    uint256 constant OPTIMISM = 10;
    uint256 constant POLYGON = 137;

    /// @notice Total chains at launch
    uint256 constant LAUNCH_CHAINS = 10;

    /// @notice LP per chain
    uint256 constant LP_PER_CHAIN = 100_000_000 ether;

    /// @notice Mining per chain
    uint256 constant MINING_PER_CHAIN = 100_000_000 ether;

    /// @notice Total LP across all chains
    uint256 constant TOTAL_LP = 1_000_000_000 ether; // 1B

    /// @notice Total mining across all chains
    uint256 constant TOTAL_MINING = 1_000_000_000 ether; // 1B

    /// @notice Initial AI supply (LP + Mining)
    uint256 constant INITIAL_SUPPLY = 2_000_000_000 ether; // 2B

    /// @notice Maximum with 100 chains unlocked
    uint256 constant MAX_SUPPLY = 1_000_000_000_000 ether; // 1T

    function isLaunchChain(uint256 chainId) internal pure returns (bool) {
        return chainId == LUX || chainId == HANZO || chainId == ZOO ||
               chainId == ETHEREUM || chainId == BASE || chainId == BNB ||
               chainId == AVALANCHE || chainId == ARBITRUM || chainId == OPTIMISM ||
               chainId == POLYGON;
    }

    function isLuxNative(uint256 chainId) internal pure returns (bool) {
        return chainId == LUX || chainId == HANZO || chainId == ZOO;
    }

    function getLaunchChains() internal pure returns (uint256[10] memory) {
        return [LUX, HANZO, ZOO, ETHEREUM, BASE, BNB, AVALANCHE, ARBITRUM, OPTIMISM, POLYGON];
    }
}
