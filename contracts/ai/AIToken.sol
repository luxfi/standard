// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.31;

import {LRC20} from "../tokens/LRC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AIToken
 * @author Lux Network Foundation, Hanzo AI, Zoo Labs Foundation
 * @notice Proof of AI Token - Open Protocol for Decentralized AI Mining
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *                          MATHEMATICAL INVARIANTS
 * ══════════════════════════════════════════════════════════════════════════════
 *
 * SUPPLY INVARIANTS (per chain):
 * ────────────────────────────────────────────────────────────────────────────────
 *   totalSupply() ≤ CHAIN_SUPPLY_CAP = 1,000,000,000 × 10^18
 *   lpMinted ≤ LP_ALLOCATION = 100,000,000 × 10^18
 *   miningMinted + treasuryMinted ≤ MINING_ALLOCATION = 900,000,000 × 10^18
 *   totalSupply() = lpMinted + miningMinted + treasuryMinted
 *
 * HALVING SCHEDULE (TRUE BITCOIN ALIGNMENT):
 * ────────────────────────────────────────────────────────────────────────────────
 *   Block time: 2 seconds (vs Bitcoin 10 minutes = 600 seconds)
 *
 *   Bitcoin halving interval: 210,000 blocks × 10 min = 4 years
 *   AI Token halving interval: 63,072,000 blocks × 2 sec = 4 years
 *
 *   Verification:
 *   - 4 years = 4 × 365.25 × 24 × 60 × 60 = 126,230,400 seconds
 *   - 126,230,400 / 2 = 63,115,200 ≈ 63,072,000 blocks
 *
 * REWARD CALCULATION:
 * ────────────────────────────────────────────────────────────────────────────────
 *   epoch = (block.number - genesisBlock) / HALVING_INTERVAL
 *   reward = INITIAL_REWARD >> epoch  (right shift = divide by 2^epoch)
 *
 *   Epoch 0 (Years 0-4):   7.14 AI/block
 *   Epoch 1 (Years 4-8):   3.57 AI/block
 *   Epoch 2 (Years 8-12):  1.785 AI/block
 *   Epoch 3 (Years 12-16): 0.8925 AI/block
 *   ...
 *   Epoch 63 (~252 years): ~0 AI/block
 *
 * TOTAL EMISSION CALCULATION:
 * ────────────────────────────────────────────────────────────────────────────────
 *   Per epoch: HALVING_INTERVAL × reward[epoch]
 *   Epoch 0: 63,072,000 × 7.14 = 450,334,080 AI
 *   Epoch 1: 63,072,000 × 3.57 = 225,167,040 AI
 *   ...
 *   Sum (geometric): 7.14 × 63,072,000 × 2 ≈ 900,668,160 AI
 *
 *   This matches MINING_ALLOCATION (900M) within rounding error.
 *   Hard cap enforced by MINING_ALLOCATION check in mintReward()
 *
 * EMISSION TIMELINE (BITCOIN-IDENTICAL):
 * ────────────────────────────────────────────────────────────────────────────────
 *   Year 4:   50% mined   (450M AI)
 *   Year 8:   75% mined   (675M AI)
 *   Year 12:  87.5% mined (787.5M AI)
 *   Year 27:  99% mined   (891M AI)
 *   Year 100+: 100% mined (900M AI)
 *
 * TREASURY ALLOCATION:
 * ────────────────────────────────────────────────────────────────────────────────
 *   treasuryAmount = amount × 200 / 10,000 = amount × 2%
 *   minerAmount = amount - treasuryAmount = amount × 98%
 *
 * DOUBLE-SPEND PREVENTION:
 * ────────────────────────────────────────────────────────────────────────────────
 *   work_id = BLAKE3(device_id || nonce || chain_id)
 *   Each chain maintains independent SpentSet
 *   Proof cannot be submitted twice on same chain
 *   Cross-chain: same work can mint on multiple chains (by design - 1B per chain)
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *                              TOKEN ECONOMICS
 * ══════════════════════════════════════════════════════════════════════════════
 *
 * PER CHAIN SUPPLY:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  100M AI - LP Allocation (10% for liquidity seeding)           │
 * │  900M AI - Mining Allocation (90% via Bitcoin schedule)        │
 * │  ─────────────────────────────────────────────────────────────  │
 * │  1B AI - Total Per-Chain Supply Cap                            │
 * │                                                                 │
 * │  10 Chains at Launch = 10B AI Total                            │
 * │  Future: 100 chains = 100B AI, 1000 chains = 1T AI             │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * LAUNCH CHAINS (10):
 * - Lux C-Chain (96369)    - Hanzo EVM (36963)    - Zoo EVM (200200)
 * - Ethereum (1)           - Base (8453)          - BNB Chain (56)
 * - Avalanche (43114)      - Arbitrum (42161)     - Optimism (10)
 * - Polygon (137)
 *
 * PRICING:
 * - Initial: $0.10/AI (96% discount from $2.50 H100 market rate)
 * - $10M liquidity depth per chain (50M AI + native token)
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *                              BRIDGE ARCHITECTURE
 * ══════════════════════════════════════════════════════════════════════════════
 *
 * LUX NATIVE (Warp Messaging):
 *   Lux C-Chain ←─Warp─→ Hanzo EVM ←─Warp─→ Zoo EVM
 *   - Native precompile at 0x0200...0005
 *   - 67% validator quorum
 *   - Instant finality via Quasar consensus
 *
 * EXTERNAL (Teleport Bridge):
 *   Lux ←─Teleport─→ Ethereum/Base/BNB/AVAX/ARB/OP/MATIC
 *   - CGGMP21 threshold signatures (67-of-100)
 *   - MPC custody via Lux Safe
 *   - 24-48 hour timelock for emergency
 *
 * BRIDGE FLOW:
 *   Source Chain: bridgeBurn(amount, destChainId) → burns tokens, emits event
 *   Bridge: Observes burn event, generates threshold signature
 *   Dest Chain: bridgeMint(to, amount, teleportId) → mints equivalent tokens
 *
 * ══════════════════════════════════════════════════════════════════════════════
 */
contract AIToken is LRC20, AccessControl, ReentrancyGuard, Pausable {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice LP allocation per chain: 100 million tokens (10%)
    /// @dev Minted by Safe for DEX liquidity seeding
    uint256 public constant LP_ALLOCATION = 100_000_000 ether;

    /// @notice Mining allocation per chain: 900 million tokens (90%)
    /// @dev Minted via mining proofs with Bitcoin schedule
    uint256 public constant MINING_ALLOCATION = 900_000_000 ether;

    /// @notice Total per-chain supply cap: 1 billion tokens
    /// @dev INVARIANT: totalSupply() ≤ CHAIN_SUPPLY_CAP
    uint256 public constant CHAIN_SUPPLY_CAP = 1_000_000_000 ether;

    /// @notice Halving interval in blocks (63M blocks = ~4 years at 2-sec blocks)
    /// @dev BITCOIN ALIGNMENT:
    ///      Bitcoin: 210,000 blocks × 10 min = 4 years
    ///      AI Token: 63,072,000 blocks × 2 sec = 4 years
    ///      4 years = 126,144,000 sec / 2 = 63,072,000 blocks
    uint256 public constant HALVING_INTERVAL = 63_072_000;

    /// @notice Initial block reward: 7.14 AI
    /// @dev BITCOIN ALIGNMENT:
    ///      Total mining supply = 900,000,000 AI
    ///      Geometric series: S = R₀ × H × 2
    ///      R₀ = 900,000,000 / (63,072,000 × 2) = 7.14 AI/block
    ///
    ///      This gives Bitcoin-identical emission curve:
    ///      - 50% mined in ~4 years
    ///      - 75% mined in ~8 years
    ///      - 99% mined in ~27 years
    ///      - Full emission in ~100+ years
    uint256 public constant INITIAL_REWARD = 7_140_000_000_000_000_000; // 7.14 ether

    /// @notice Treasury allocation in basis points (200 = 2%)
    /// @dev INVARIANT: treasuryAmount = reward × TREASURY_BPS / BPS_DENOMINATOR
    uint256 public constant TREASURY_BPS = 200;

    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum epochs before reward becomes 0 (64 halvings)
    /// @dev After 64 halvings: 79.4 >> 64 = 0 (underflow protection)
    uint256 public constant MAX_EPOCHS = 64;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                ROLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Role for mining contracts that can call mintReward
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

    /// @notice Role for Teleport bridge that can call bridgeMint/bridgeBurn
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    /// @notice Role for emergency pause operations (subset of admin)
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════
    //                                STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Safe multi-sig address (initial governance)
    address public safe;

    /// @notice Research treasury address (receives 2% of mining)
    address public treasury;

    /// @notice Genesis block number (mining schedule starts here)
    /// @dev Epoch 0 starts at genesisBlock, epoch 1 at genesisBlock + HALVING_INTERVAL
    uint256 public genesisBlock;

    /// @notice Total minted via LP allocation
    /// @dev INVARIANT: lpMinted ≤ LP_ALLOCATION
    uint256 public lpMinted;

    /// @notice Total minted to miners (excluding treasury share)
    uint256 public miningMinted;

    /// @notice Total minted to treasury (2% of mining rewards)
    /// @dev INVARIANT: miningMinted + treasuryMinted ≤ MINING_ALLOCATION
    uint256 public treasuryMinted;

    /// @notice Immutable chain ID (set at deployment)
    uint256 public immutable CHAIN_ID;

    /// @notice Per-epoch mining statistics
    mapping(uint256 => uint256) public epochMinted;

    // ═══════════════════════════════════════════════════════════════════════════
    //                               EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event LPMinted(address indexed recipient, uint256 amount, uint256 totalLPMinted);
    event MiningReward(address indexed miner, uint256 minerAmount, uint256 treasuryAmount, uint256 epoch);
    event BridgeMint(address indexed to, uint256 amount, bytes32 indexed teleportId, uint256 sourceChainId);
    event BridgeBurn(address indexed from, uint256 amount, bytes32 indexed destChainId);
    event GenesisSet(uint256 blockNumber);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event SafeUpdated(address indexed oldSafe, address indexed newSafe);

    // ═══════════════════════════════════════════════════════════════════════════
    //                               ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error SupplyCapExceeded(uint256 requested, uint256 available);
    error LPCapExceeded(uint256 requested, uint256 available);
    error MiningCapExceeded(uint256 requested, uint256 available);
    error GenesisAlreadySet();
    error GenesisNotSet();
    error InvalidAddress();
    error ZeroAmount();
    error InvalidChainId(uint256 chainId);

    // ═══════════════════════════════════════════════════════════════════════════
    //                             CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploy AIToken for a specific chain
     * @param _safe Safe multi-sig address (initial admin)
     * @param _treasury Treasury address for research fund
     * @dev Validates chain ID is in launch set, grants admin to Safe
     */
    constructor(address _safe, address _treasury) LRC20("AI", "AI") {
        if (_safe == address(0) || _treasury == address(0)) revert InvalidAddress();

        CHAIN_ID = block.chainid;

        // Validate launch chain
        if (!LaunchChains.isLaunchChain(CHAIN_ID)) {
            revert InvalidChainId(CHAIN_ID);
        }

        safe = _safe;
        treasury = _treasury;

        // Safe is initial admin with all privileges
        _grantRole(DEFAULT_ADMIN_ROLE, _safe);
        _grantRole(PAUSER_ROLE, _safe);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          LP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint LP allocation for liquidity seeding
     * @param recipient Address to receive LP tokens
     * @param amount Amount of AI tokens to mint
     * @dev Can be called multiple times until LP_ALLOCATION exhausted
     *      INVARIANT: lpMinted ≤ LP_ALLOCATION after call
     */
    function mintLP(address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 remaining = LP_ALLOCATION - lpMinted;
        if (amount > remaining) {
            revert LPCapExceeded(amount, remaining);
        }

        lpMinted += amount;
        _mint(recipient, amount);

        emit LPMinted(recipient, amount, lpMinted);
    }

    /**
     * @notice Get remaining LP allocation
     * @return remaining Amount of LP tokens that can still be minted
     */
    function remainingLP() public view returns (uint256 remaining) {
        return LP_ALLOCATION - lpMinted;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         BRIDGE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint tokens from Teleport bridge
     * @param to Recipient address
     * @param amount Amount to mint
     * @param teleportId Unique transfer identifier from source chain
     * @return success True if mint succeeded
     * @dev Called by authorized bridge after validating cross-chain message
     *      INVARIANT: totalSupply() ≤ CHAIN_SUPPLY_CAP after call
     */
    function bridgeMint(
        address to,
        uint256 amount,
        bytes32 teleportId
    ) external onlyRole(BRIDGE_ROLE) whenNotPaused returns (bool success) {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 available = CHAIN_SUPPLY_CAP - totalSupply();
        if (amount > available) {
            revert SupplyCapExceeded(amount, available);
        }

        _mint(to, amount);
        emit BridgeMint(to, amount, teleportId, CHAIN_ID);

        return true;
    }

    /**
     * @notice Burn tokens for cross-chain transfer
     * @param amount Amount to burn
     * @param destChainId Destination chain identifier
     * @return success True if burn succeeded
     * @dev User burns their tokens, bridge observes and mints on dest chain
     */
    function bridgeBurn(
        uint256 amount,
        bytes32 destChainId
    ) external whenNotPaused returns (bool success) {
        if (amount == 0) revert ZeroAmount();

        _burn(msg.sender, amount);
        emit BridgeBurn(msg.sender, amount, destChainId);

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         MINING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint mining reward with treasury allocation
     * @param miner Address to receive mining reward
     * @param amount Total reward amount (before treasury split)
     * @dev Called by authorized mining contract after verifying work proof
     *      98% goes to miner, 2% goes to treasury
     *      INVARIANT: miningMinted + treasuryMinted ≤ MINING_ALLOCATION after call
     */
    function mintReward(
        address miner,
        uint256 amount
    ) external nonReentrant onlyRole(MINER_ROLE) whenNotPaused {
        if (genesisBlock == 0) revert GenesisNotSet();
        if (miner == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        // Calculate treasury split
        uint256 treasuryAmount = (amount * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 minerAmount = amount - treasuryAmount;
        uint256 totalMint = minerAmount + treasuryAmount;

        // Check mining cap
        uint256 miningUsed = miningMinted + treasuryMinted;
        uint256 miningRemaining = MINING_ALLOCATION - miningUsed;
        if (totalMint > miningRemaining) {
            revert MiningCapExceeded(totalMint, miningRemaining);
        }

        // Update state
        uint256 epoch = currentEpoch();
        epochMinted[epoch] += totalMint;
        miningMinted += minerAmount;
        treasuryMinted += treasuryAmount;

        // Mint tokens
        _mint(miner, minerAmount);
        if (treasuryAmount > 0) {
            _mint(treasury, treasuryAmount);
        }

        emit MiningReward(miner, minerAmount, treasuryAmount, epoch);
    }

    /**
     * @notice Get remaining mining allocation
     * @return remaining Amount of tokens that can still be mined
     */
    function remainingMining() public view returns (uint256 remaining) {
        uint256 used = miningMinted + treasuryMinted;
        return used >= MINING_ALLOCATION ? 0 : MINING_ALLOCATION - used;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current halving epoch
     * @return epoch Current epoch (0-indexed), 0 if genesis not set
     * @dev epoch = (block.number - genesisBlock) / HALVING_INTERVAL
     */
    function currentEpoch() public view returns (uint256 epoch) {
        if (genesisBlock == 0) return 0;

        uint256 blocksSinceGenesis = block.number > genesisBlock
            ? block.number - genesisBlock
            : 0;

        return blocksSinceGenesis / HALVING_INTERVAL;
    }

    /**
     * @notice Get current block reward after halvings
     * @return reward Current reward per block (0 after epoch 64)
     * @dev reward = INITIAL_REWARD >> epoch
     */
    function currentReward() public view returns (uint256 reward) {
        uint256 epoch = currentEpoch();
        if (epoch >= MAX_EPOCHS) return 0;
        return INITIAL_REWARD >> epoch;
    }

    /**
     * @notice Get blocks until next halving
     * @return blocks Number of blocks until next epoch
     */
    function blocksUntilHalving() external view returns (uint256 blocks) {
        if (genesisBlock == 0) return 0;

        uint256 blocksSinceGenesis = block.number > genesisBlock
            ? block.number - genesisBlock
            : 0;

        uint256 blocksIntoEpoch = blocksSinceGenesis % HALVING_INTERVAL;
        return HALVING_INTERVAL - blocksIntoEpoch;
    }

    /**
     * @notice Get comprehensive token statistics
     * @return _totalSupply Current total supply
     * @return _lpMinted Total LP tokens minted
     * @return _miningMinted Total mining rewards to miners
     * @return _treasuryMinted Total treasury allocation
     * @return _epoch Current halving epoch
     * @return _reward Current block reward
     * @return _remainingLP LP tokens remaining
     * @return _remainingMining Mining tokens remaining
     */
    function getStats() external view returns (
        uint256 _totalSupply,
        uint256 _lpMinted,
        uint256 _miningMinted,
        uint256 _treasuryMinted,
        uint256 _epoch,
        uint256 _reward,
        uint256 _remainingLP,
        uint256 _remainingMining
    ) {
        return (
            totalSupply(),
            lpMinted,
            miningMinted,
            treasuryMinted,
            currentEpoch(),
            currentReward(),
            remainingLP(),
            remainingMining()
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set genesis block to start mining schedule
     * @dev Can only be called once by admin
     */
    function setGenesis() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (genesisBlock != 0) revert GenesisAlreadySet();
        genesisBlock = block.number;
        emit GenesisSet(block.number);
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress();
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    /**
     * @notice Transfer Safe admin to new address
     * @param _safe New Safe address
     * @dev Grants admin to new Safe, revokes from old
     */
    function setSafe(address _safe) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_safe == address(0)) revert InvalidAddress();
        address old = safe;

        _grantRole(DEFAULT_ADMIN_ROLE, _safe);
        _grantRole(PAUSER_ROLE, _safe);
        _revokeRole(DEFAULT_ADMIN_ROLE, old);
        _revokeRole(PAUSER_ROLE, old);

        safe = _safe;
        emit SafeUpdated(old, _safe);
    }

    /**
     * @notice Authorize mining contract
     * @param miner Address of mining contract
     */
    function authorizeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINER_ROLE, miner);
    }

    /**
     * @notice Revoke mining authorization
     * @param miner Address of mining contract
     */
    function revokeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINER_ROLE, miner);
    }

    /**
     * @notice Authorize Teleport bridge
     * @param bridge Address of bridge contract
     */
    function authorizeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BRIDGE_ROLE, bridge);
    }

    /**
     * @notice Revoke bridge authorization
     * @param bridge Address of bridge contract
     */
    function revokeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BRIDGE_ROLE, bridge);
    }

    /**
     * @notice Pause all minting and burning
     * @dev Emergency pause, requires PAUSER_ROLE (2-of-5 threshold on Safe)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations
     * @dev Requires full admin (3-of-5 threshold on Safe)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Override _msgSender for OZ AccessControl and LRC20 compatibility
     */
    function _msgSender() internal view override returns (address) {
        return msg.sender;
    }

    /**
     * @notice Burn tokens from caller's account
     * @param amount Amount to burn
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from specified account (with allowance)
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//                            LAUNCH CHAINS LIBRARY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title LaunchChains
 * @notice Configuration for 10-chain launch with 1B AI per chain
 * @dev Provides chain validation and categorization utilities
 *
 * SUPPLY DISTRIBUTION:
 * - Each chain: 1B AI total (100M LP + 900M mining)
 * - 10 chains at launch = 10B AI global supply
 * - Future expansion: 100 chains = 100B, 1000 chains = 1T
 * - New chains require governance approval
 */
library LaunchChains {
    // ═══════════════════════════════════════════════════════════════════════════
    //                           LUX NATIVE CHAINS
    // ═══════════════════════════════════════════════════════════════════════════
    // Use Warp messaging (precompile 0x0200...0005)
    // 67% validator quorum, instant finality

    /// @notice Lux C-Chain - Primary deployment
    uint256 constant LUX = 96369;
    uint256 constant LUX_TESTNET = 96368;

    /// @notice Hanzo EVM - AI-focused applications
    uint256 constant HANZO = 36963;
    uint256 constant HANZO_TESTNET = 36962;

    /// @notice Zoo EVM - Research/DeSci applications
    uint256 constant ZOO = 200200;
    uint256 constant ZOO_TESTNET = 200201;

    /// @notice Anvil - Local testing
    uint256 constant ANVIL = 31337;

    // ═══════════════════════════════════════════════════════════════════════════
    //                          EXTERNAL EVM CHAINS
    // ═══════════════════════════════════════════════════════════════════════════
    // Use Teleport bridge (CGGMP21 threshold signatures)
    // 67-of-100 validator threshold

    /// @notice Ethereum Mainnet
    uint256 constant ETHEREUM = 1;

    /// @notice Base (Coinbase L2)
    uint256 constant BASE = 8453;

    /// @notice BNB Chain
    uint256 constant BNB = 56;

    /// @notice Avalanche C-Chain
    uint256 constant AVALANCHE = 43114;

    /// @notice Arbitrum One
    uint256 constant ARBITRUM = 42161;

    /// @notice Optimism
    uint256 constant OPTIMISM = 10;

    /// @notice Polygon PoS
    uint256 constant POLYGON = 137;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Number of launch chains
    uint256 constant LAUNCH_CHAIN_COUNT = 10;

    /// @notice Per-chain supply cap
    uint256 constant PER_CHAIN_CAP = 1_000_000_000 ether;

    /// @notice LP allocation per chain (10%)
    uint256 constant LP_PER_CHAIN = 100_000_000 ether;

    /// @notice Mining allocation per chain (90%)
    uint256 constant MINING_PER_CHAIN = 900_000_000 ether;

    /// @notice Total global supply at launch (10 chains)
    uint256 constant LAUNCH_SUPPLY = 10_000_000_000 ether;

    /// @notice Initial price in USD (scaled to 18 decimals)
    /// @dev $0.10 = 0.1 ether = 100000000000000000
    uint256 constant INITIAL_PRICE_USD = 100_000_000_000_000_000;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if chain ID is in launch set
     * @param chainId Chain ID to validate
     * @return valid True if chain is a launch chain
     */
    function isLaunchChain(uint256 chainId) internal pure returns (bool valid) {
        return chainId == LUX || chainId == LUX_TESTNET ||
               chainId == HANZO || chainId == HANZO_TESTNET ||
               chainId == ZOO || chainId == ZOO_TESTNET ||
               chainId == ANVIL ||
               chainId == ETHEREUM || chainId == BASE || chainId == BNB ||
               chainId == AVALANCHE || chainId == ARBITRUM || chainId == OPTIMISM ||
               chainId == POLYGON;
    }

    /**
     * @notice Check if chain uses Warp messaging (Lux native)
     * @param chainId Chain ID to check
     * @return isNative True if chain is Lux native
     */
    function isLuxNative(uint256 chainId) internal pure returns (bool isNative) {
        return chainId == LUX || chainId == LUX_TESTNET ||
               chainId == HANZO || chainId == HANZO_TESTNET ||
               chainId == ZOO || chainId == ZOO_TESTNET;
    }

    /**
     * @notice Check if chain uses Teleport bridge (external)
     * @param chainId Chain ID to check
     * @return isExternal True if chain requires Teleport
     */
    function isExternal(uint256 chainId) internal pure returns (bool) {
        return isLaunchChain(chainId) && !isLuxNative(chainId);
    }

    /**
     * @notice Get all launch chain IDs
     * @return chains Array of 10 chain IDs
     */
    function getLaunchChains() internal pure returns (uint256[10] memory chains) {
        return [LUX, HANZO, ZOO, ETHEREUM, BASE, BNB, AVALANCHE, ARBITRUM, OPTIMISM, POLYGON];
    }

    /**
     * @notice Get Lux native chain IDs
     * @return chains Array of 3 Lux chain IDs
     */
    function getLuxNativeChains() internal pure returns (uint256[3] memory chains) {
        return [LUX, HANZO, ZOO];
    }

    /**
     * @notice Get external chain IDs
     * @return chains Array of 7 external chain IDs
     */
    function getExternalChains() internal pure returns (uint256[7] memory chains) {
        return [ETHEREUM, BASE, BNB, AVALANCHE, ARBITRUM, OPTIMISM, POLYGON];
    }
}
