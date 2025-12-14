// SPDX-License-Identifier: MIT
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AIToken
 * @notice ERC20 token with mining-based minting, supply cap, and halving schedule
 * @dev Fixed 1B supply cap per chain. Minting only via verified mining proofs.
 *      2% of each mint goes to research treasury.
 *
 * Supply Economics:
 * - Max supply: 1,000,000,000 AI (1 billion)
 * - Initial block reward: 50 AI
 * - Halving: Every 210,000 blocks (Bitcoin-aligned)
 * - Treasury: 2% of minted rewards to research fund
 *
 * Chain Deployment:
 * - C-Chain (96369): Primary deployment
 * - Hanzo EVM (36963): Secondary deployment
 * - Zoo EVM (200200): Community deployment
 */
contract AIToken is ERC20, ERC20Burnable, AccessControl, ReentrancyGuard {
    // ============ Constants ============

    /// @notice Maximum total supply: 1 billion tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    /// @notice Halving interval in blocks (Bitcoin-aligned)
    uint256 public constant HALVING_INTERVAL = 210_000;

    /// @notice Treasury allocation in basis points (200 = 2%)
    uint256 public constant TREASURY_BPS = 200;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Role for mining contracts that can mint
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

    // ============ State ============

    /// @notice Research treasury address
    address public treasury;

    /// @notice Genesis block number (when mining started)
    uint256 public genesisBlock;

    /// @notice Total minted to miners (excluding treasury)
    uint256 public minerMinted;

    /// @notice Total minted to treasury
    uint256 public treasuryMinted;

    /// @notice Chain ID this token is deployed on
    uint256 public immutable CHAIN_ID;

    /// @notice Mapping of halving epoch to whether emission occurred
    mapping(uint256 => uint256) public epochMinted;

    // ============ Events ============

    event MiningRewardMinted(address indexed miner, uint256 amount, uint256 treasuryAmount, uint256 epoch);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event GenesisBlockSet(uint256 blockNumber);
    event MinerAuthorized(address indexed miner);
    event MinerRevoked(address indexed miner);

    // ============ Errors ============

    error MaxSupplyExceeded(uint256 requested, uint256 available);
    error GenesisAlreadySet();
    error GenesisNotSet();
    error InvalidTreasury();
    error ZeroAmount();
    error InvalidChainId();

    // ============ Constructor ============

    /**
     * @notice Deploy AIToken
     * @param _treasury Initial treasury address
     */
    constructor(address _treasury) ERC20("AI", "AI") {
        if (_treasury == address(0)) revert InvalidTreasury();

        CHAIN_ID = block.chainid;
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @notice Get current halving epoch
     * @return epoch Current epoch (0-indexed)
     */
    function currentEpoch() public view returns (uint256 epoch) {
        if (genesisBlock == 0) return 0;

        uint256 blocksSinceGenesis = block.number > genesisBlock
            ? block.number - genesisBlock
            : 0;

        return blocksSinceGenesis / HALVING_INTERVAL;
    }

    /**
     * @notice Get remaining mintable supply
     * @return remaining Tokens that can still be minted
     */
    function remainingSupply() public view returns (uint256 remaining) {
        uint256 minted = totalSupply();
        return minted >= MAX_SUPPLY ? 0 : MAX_SUPPLY - minted;
    }

    /**
     * @notice Get blocks until next halving
     * @return blocks Number of blocks until next halving
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
     * @notice Calculate base reward for current epoch
     * @param initialReward The initial reward before any halvings
     * @return reward Current epoch reward
     */
    function epochReward(uint256 initialReward) public view returns (uint256 reward) {
        uint256 epoch = currentEpoch();
        if (epoch >= 64) return 0; // Prevent overflow

        reward = initialReward >> epoch; // Divide by 2^epoch
    }

    /**
     * @notice Check if an address can mint (has MINER_ROLE)
     * @param account Address to check
     * @return canMint True if address can mint
     */
    function isMiner(address account) external view returns (bool canMint) {
        return hasRole(MINER_ROLE, account);
    }

    // ============ Mining Functions ============

    /**
     * @notice Mint mining reward to miner and treasury
     * @dev Only callable by addresses with MINER_ROLE
     * @param miner Address to receive mining reward
     * @param amount Amount to mint (before treasury split)
     */
    function mintReward(address miner, uint256 amount) external nonReentrant onlyRole(MINER_ROLE) {
        if (genesisBlock == 0) revert GenesisNotSet();
        if (amount == 0) revert ZeroAmount();

        // Calculate treasury allocation
        uint256 treasuryAmount = (amount * TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 minerAmount = amount - treasuryAmount;
        uint256 totalMint = minerAmount + treasuryAmount;

        // Check supply cap
        uint256 available = remainingSupply();
        if (totalMint > available) {
            revert MaxSupplyExceeded(totalMint, available);
        }

        // Track minting
        uint256 epoch = currentEpoch();
        epochMinted[epoch] += totalMint;
        minerMinted += minerAmount;
        treasuryMinted += treasuryAmount;

        // Mint tokens
        _mint(miner, minerAmount);
        if (treasuryAmount > 0 && treasury != address(0)) {
            _mint(treasury, treasuryAmount);
        }

        emit MiningRewardMinted(miner, minerAmount, treasuryAmount, epoch);
    }

    /**
     * @notice Batch mint rewards to multiple miners
     * @dev Gas-efficient for batch reward distribution
     * @param miners Array of miner addresses
     * @param amounts Array of amounts to mint
     */
    function batchMintReward(
        address[] calldata miners,
        uint256[] calldata amounts
    ) external nonReentrant onlyRole(MINER_ROLE) {
        if (genesisBlock == 0) revert GenesisNotSet();
        require(miners.length == amounts.length, "Length mismatch");

        uint256 epoch = currentEpoch();
        uint256 totalMinerMint;
        uint256 totalTreasuryMint;

        for (uint256 i = 0; i < miners.length; i++) {
            if (amounts[i] == 0) continue;

            uint256 treasuryAmount = (amounts[i] * TREASURY_BPS) / BPS_DENOMINATOR;
            uint256 minerAmount = amounts[i] - treasuryAmount;

            _mint(miners[i], minerAmount);
            totalMinerMint += minerAmount;
            totalTreasuryMint += treasuryAmount;

            emit MiningRewardMinted(miners[i], minerAmount, treasuryAmount, epoch);
        }

        // Single treasury mint for efficiency
        if (totalTreasuryMint > 0 && treasury != address(0)) {
            _mint(treasury, totalTreasuryMint);
        }

        // Check supply cap after minting
        if (totalSupply() > MAX_SUPPLY) {
            revert MaxSupplyExceeded(totalMinerMint + totalTreasuryMint, remainingSupply());
        }

        epochMinted[epoch] += totalMinerMint + totalTreasuryMint;
        minerMinted += totalMinerMint;
        treasuryMinted += totalTreasuryMint;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set genesis block to start mining
     * @dev Can only be called once
     */
    function setGenesisBlock() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (genesisBlock != 0) revert GenesisAlreadySet();
        genesisBlock = block.number;
        emit GenesisBlockSet(block.number);
    }

    /**
     * @notice Set genesis block to a specific block number
     * @param blockNumber The genesis block number
     */
    function setGenesisBlockAt(uint256 blockNumber) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (genesisBlock != 0) revert GenesisAlreadySet();
        genesisBlock = blockNumber;
        emit GenesisBlockSet(blockNumber);
    }

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidTreasury();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Authorize a mining contract to mint
     * @param miner Address of mining contract
     */
    function authorizeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINER_ROLE, miner);
        emit MinerAuthorized(miner);
    }

    /**
     * @notice Revoke mining authorization
     * @param miner Address of mining contract
     */
    function revokeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINER_ROLE, miner);
        emit MinerRevoked(miner);
    }

    // ============ Utility Functions ============

    /**
     * @notice Get mining statistics
     * @return _totalSupply Current total supply
     * @return _minerMinted Total minted to miners
     * @return _treasuryMinted Total minted to treasury
     * @return _remaining Remaining mintable supply
     * @return _epoch Current halving epoch
     */
    function getMiningStats() external view returns (
        uint256 _totalSupply,
        uint256 _minerMinted,
        uint256 _treasuryMinted,
        uint256 _remaining,
        uint256 _epoch
    ) {
        return (
            totalSupply(),
            minerMinted,
            treasuryMinted,
            remainingSupply(),
            currentEpoch()
        );
    }
}
