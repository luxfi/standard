// SPDX-License-Identifier: MIT
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AITokenTeleport
 * @notice Teleport-compatible AI Token with 10% initial mint for LP seeding
 * @dev Bridge-compatible ERC20 with mining rewards and halving schedule
 *
 * ARCHITECTURE:
 * - Lux network is source of truth via native Warp messaging
 * - Teleport over threshold LSS on T-chain for cross-chain transfers
 * - Safe multi-sig (MPC) manages contracts initially
 * - Later transitions to DAO/open governance
 *
 * TOKENOMICS:
 * - Max supply: 1,000,000,000 AI (1B per chain)
 * - Initial mint: 100,000,000 AI (10%) for LP seeding
 * - Mining rewards: 900,000,000 AI (90%) via PoAI
 * - Treasury: 2% of mining rewards
 * - Halving: Every 210,000 blocks (Bitcoin-aligned)
 *
 * LP SEEDING (one-sided):
 * - AI/LUX pool on each chain
 * - Initial price: 0.0001 BTC equivalent
 * - Enables AI payments for attestation fees
 */
contract AITokenTeleport is ERC20, AccessControl, ReentrancyGuard {
    // ============ Constants ============

    /// @notice Maximum total supply: 1 billion tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    /// @notice Initial LP allocation: 10% (100 million)
    uint256 public constant INITIAL_LP_ALLOCATION = 100_000_000 ether;

    /// @notice Mining allocation: 90% (900 million)
    uint256 public constant MINING_ALLOCATION = 900_000_000 ether;

    /// @notice Halving interval in blocks (Bitcoin-aligned)
    uint256 public constant HALVING_INTERVAL = 210_000;

    /// @notice Initial block reward: 50 AI
    uint256 public constant INITIAL_REWARD = 50 ether;

    /// @notice Treasury allocation in basis points (200 = 2%)
    uint256 public constant TREASURY_BPS = 200;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Roles ============

    /// @notice Role for mining contracts that can mint
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

    /// @notice Role for bridge (Teleport) operations
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    // ============ State ============

    /// @notice Safe multi-sig address (initial owner)
    address public safe;

    /// @notice Research treasury address
    address public treasury;

    /// @notice Genesis block number (when mining started)
    uint256 public genesisBlock;

    /// @notice Total minted to miners (excluding treasury)
    uint256 public minerMinted;

    /// @notice Total minted to treasury
    uint256 public treasuryMinted;

    /// @notice Whether initial LP allocation has been minted
    bool public initialMintComplete;

    /// @notice Chain ID this token is deployed on
    uint256 public immutable CHAIN_ID;

    /// @notice Mapping of halving epoch to amount minted
    mapping(uint256 => uint256) public epochMinted;

    // ============ Events ============

    event InitialLPMinted(address indexed recipient, uint256 amount);
    event MiningRewardMinted(address indexed miner, uint256 amount, uint256 treasuryAmount, uint256 epoch);
    event BridgeMint(address indexed to, uint256 amount, bytes32 indexed teleportId);
    event BridgeBurn(address indexed from, uint256 amount, bytes32 indexed destChainId);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event SafeUpdated(address indexed oldSafe, address indexed newSafe);
    event GenesisBlockSet(uint256 blockNumber);

    // ============ Errors ============

    error MaxSupplyExceeded(uint256 requested, uint256 available);
    error MiningCapExceeded(uint256 requested, uint256 available);
    error GenesisAlreadySet();
    error GenesisNotSet();
    error InitialMintAlreadyComplete();
    error InvalidAddress();
    error ZeroAmount();

    // ============ Constructor ============

    /**
     * @notice Deploy AITokenTeleport
     * @param _safe Safe multi-sig address (initial admin)
     * @param _treasury Treasury address for mining rewards
     */
    constructor(address _safe, address _treasury) ERC20("AI", "AI") {
        if (_safe == address(0)) revert InvalidAddress();
        if (_treasury == address(0)) revert InvalidAddress();

        CHAIN_ID = block.chainid;
        safe = _safe;
        treasury = _treasury;

        // Safe multi-sig is initial admin
        _grantRole(DEFAULT_ADMIN_ROLE, _safe);
    }

    // ============ Initial LP Mint ============

    /**
     * @notice Mint 10% initial allocation for LP seeding
     * @dev Can only be called once by admin (Safe)
     * @param lpRecipient Address to receive LP allocation (typically Safe or LP contract)
     */
    function mintInitialLP(address lpRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (initialMintComplete) revert InitialMintAlreadyComplete();
        if (lpRecipient == address(0)) revert InvalidAddress();

        initialMintComplete = true;
        _mint(lpRecipient, INITIAL_LP_ALLOCATION);

        emit InitialLPMinted(lpRecipient, INITIAL_LP_ALLOCATION);
    }

    // ============ Bridge Functions (Teleport) ============

    /**
     * @notice Mint tokens via Teleport bridge
     * @dev Only callable by authorized bridge (Teleport MPC)
     * @param to Recipient address
     * @param amount Amount to mint
     * @param teleportId Unique transfer ID from source chain
     */
    function bridgeMint(
        address to,
        uint256 amount,
        bytes32 teleportId
    ) external onlyRole(BRIDGE_ROLE) returns (bool) {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        // Check doesn't exceed max supply
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert MaxSupplyExceeded(amount, MAX_SUPPLY - totalSupply());
        }

        _mint(to, amount);
        emit BridgeMint(to, amount, teleportId);

        return true;
    }

    /**
     * @notice Burn tokens for Teleport bridge transfer
     * @dev Caller burns their own tokens for cross-chain transfer
     * @param amount Amount to burn
     * @param destChainId Destination chain identifier
     */
    function bridgeBurn(
        uint256 amount,
        bytes32 destChainId
    ) external returns (bool) {
        if (amount == 0) revert ZeroAmount();

        _burn(msg.sender, amount);
        emit BridgeBurn(msg.sender, amount, destChainId);

        return true;
    }

    /**
     * @notice Admin burn for bridge operations
     * @dev Only bridge role can burn from specific accounts
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function bridgeBurnFrom(
        address from,
        uint256 amount
    ) external onlyRole(BRIDGE_ROLE) returns (bool) {
        if (from == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        _burn(from, amount);
        emit BridgeBurn(from, amount, bytes32(0));

        return true;
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

        // Check mining cap (90% of supply)
        uint256 currentMiningMinted = minerMinted + treasuryMinted;
        if (currentMiningMinted + totalMint > MINING_ALLOCATION) {
            revert MiningCapExceeded(totalMint, MINING_ALLOCATION - currentMiningMinted);
        }

        // Track minting
        uint256 epoch = currentEpoch();
        epochMinted[epoch] += totalMint;
        minerMinted += minerAmount;
        treasuryMinted += treasuryAmount;

        // Mint tokens
        _mint(miner, minerAmount);
        if (treasuryAmount > 0) {
            _mint(treasury, treasuryAmount);
        }

        emit MiningRewardMinted(miner, minerAmount, treasuryAmount, epoch);
    }

    // ============ View Functions ============

    /**
     * @notice Get current halving epoch
     */
    function currentEpoch() public view returns (uint256) {
        if (genesisBlock == 0) return 0;
        uint256 blocksSinceGenesis = block.number > genesisBlock ? block.number - genesisBlock : 0;
        return blocksSinceGenesis / HALVING_INTERVAL;
    }

    /**
     * @notice Get current block reward after halvings
     */
    function currentReward() public view returns (uint256) {
        uint256 epoch = currentEpoch();
        if (epoch >= 64) return 0;
        return INITIAL_REWARD >> epoch;
    }

    /**
     * @notice Get remaining mining allocation
     */
    function remainingMiningSupply() public view returns (uint256) {
        uint256 minted = minerMinted + treasuryMinted;
        return minted >= MINING_ALLOCATION ? 0 : MINING_ALLOCATION - minted;
    }

    /**
     * @notice Get mining statistics
     */
    function getMiningStats() external view returns (
        uint256 _totalSupply,
        uint256 _minerMinted,
        uint256 _treasuryMinted,
        uint256 _remainingMining,
        uint256 _epoch,
        uint256 _currentReward
    ) {
        return (
            totalSupply(),
            minerMinted,
            treasuryMinted,
            remainingMiningSupply(),
            currentEpoch(),
            currentReward()
        );
    }

    // ============ Admin Functions ============

    /**
     * @notice Set genesis block to start mining
     */
    function setGenesisBlock() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (genesisBlock != 0) revert GenesisAlreadySet();
        genesisBlock = block.number;
        emit GenesisBlockSet(block.number);
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidAddress();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    /**
     * @notice Update Safe multi-sig address
     * @dev Transfers admin role to new Safe
     */
    function setSafe(address newSafe) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newSafe == address(0)) revert InvalidAddress();

        address oldSafe = safe;
        safe = newSafe;

        // Transfer admin role
        _grantRole(DEFAULT_ADMIN_ROLE, newSafe);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldSafe);

        emit SafeUpdated(oldSafe, newSafe);
    }

    /**
     * @notice Authorize mining contract
     */
    function authorizeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINER_ROLE, miner);
    }

    /**
     * @notice Revoke mining authorization
     */
    function revokeMiner(address miner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINER_ROLE, miner);
    }

    /**
     * @notice Authorize bridge (Teleport)
     */
    function authorizeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BRIDGE_ROLE, bridge);
    }

    /**
     * @notice Revoke bridge authorization
     */
    function revokeBridge(address bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BRIDGE_ROLE, bridge);
    }
}

/**
 * @title AITokenTeleportFactory
 * @notice Factory for deploying AITokenTeleport across chains
 */
contract AITokenTeleportFactory {
    event TokenDeployed(uint256 indexed chainId, address token, address safe, address treasury);

    /// @notice Deploy AI token for a specific chain
    function deploy(
        address safe,
        address treasury
    ) external returns (address token) {
        token = address(new AITokenTeleport(safe, treasury));
        emit TokenDeployed(block.chainid, token, safe, treasury);
    }
}
