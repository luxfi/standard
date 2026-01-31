// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface IKarma {
    function mint(address to, uint256 amount, bytes32 reason) external;
    function burn(address from, uint256 amount, bytes32 reason) external;
    function slash(address account, uint256 amount, bytes32 reason) external;
    function recordActivity(address account) external;
    function balanceOf(address account) external view returns (uint256);
    function verify(address account) external;
    function linkDID(address account, bytes32 did) external;
}

interface ISoulID {
    function soulOf(address account) external view returns (uint256);
    function hasSoul(address account) external view returns (bool);
    function mintSoul(address to) external returns (uint256);
    function updateKarma(uint256 tokenId, uint256 karma) external;
    function updateTrustLevel(uint256 tokenId, uint256 level) external;
    function issueBadge(uint256 tokenId, bytes32 badgeType, uint256 expiresAt, bytes32 metadata) external returns (uint256);
    function reputationOf(address account) external view returns (
        uint256 karma,
        uint256 humanityScore,
        uint256 governanceParticipation,
        uint256 communityContribution,
        uint256 protocolUsage,
        uint256 trustLevel,
        uint256 lastUpdated
    );
}

/**
 * @title KarmaController - Unified Karma and Reputation Controller
 * @notice Orchestrates Karma minting, SoulID updates, and cross-chain reputation
 * @dev Implements LP-3004 Karma Controller Standard
 *
 * KARMA FLOW:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  earnKarma(account, amount, reason)                                         │
 * │  └─> Mints Karma to account for positive actions                            │
 * │  └─> Updates SoulID karma snapshot                                          │
 * │  └─> Records activity (reduces decay)                                       │
 * │                                                                             │
 * │  giveKarma(from, to, amount, reason)                                        │
 * │  └─> Transfer-like: burns from sender, mints to receiver                    │
 * │  └─> Enables community praise/recognition                                   │
 * │  └─> Both parties get activity recorded                                     │
 * │                                                                             │
 * │  purgeKarma(account, amount, reason)                                        │
 * │  └─> Burns Karma as penalty/slashing                                        │
 * │  └─> Updates SoulID karma snapshot                                          │
 * │  └─> Governance-controlled or self-sacrifice                                │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * OMNI-CHAIN PATTERN:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  Lux Network (Primary)                                                      │
 * │  ├─> Karma.sol: Source of truth for K balances                              │
 * │  ├─> SoulID.sol: SBT with reputation fields                                 │
 * │  └─> KarmaController.sol: Orchestration layer                               │
 * │                                                                             │
 * │  ASHA/CYRUS/MIGA/PARS Chains (Secondary)                                    │
 * │  ├─> KarmaOracle.sol: Read-only Karma balance oracle                        │
 * │  └─> Uses MPC signatures to attest Karma from Lux                           │
 * │                                                                             │
 * │  Cross-chain Karma is READ-ONLY on secondary chains:                        │
 * │  - Governance weight calculations                                           │
 * │  - Access control decisions                                                 │
 * │  - Trust score verification                                                 │
 * │                                                                             │
 * │  All WRITE operations go through Lux primary:                               │
 * │  - earnKarma, giveKarma, purgeKarma                                         │
 * │  - Cross-chain calls bridge to Lux for execution                            │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract KarmaController is AccessControl, ReentrancyGuard, Pausable {
    // ============ Roles ============

    /// @notice Role for governance to configure controller
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Role for authorized karma sources (hooks, bridges)
    bytes32 public constant KARMA_SOURCE_ROLE = keccak256("KARMA_SOURCE_ROLE");

    /// @notice Role for slashing authority
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    // ============ Constants ============

    /// @notice Maximum karma that can be given at once (prevents abuse)
    uint256 public constant MAX_GIVE_AMOUNT = 100e18;

    /// @notice Minimum karma required to give karma (stake)
    uint256 public constant MIN_KARMA_TO_GIVE = 10e18;

    /// @notice Cooldown between giving karma to same recipient
    uint256 public constant GIVE_COOLDOWN = 1 days;

    /// @notice Badge type for karma givers
    bytes32 public constant BADGE_KARMA_GIVER = keccak256("KARMA_GIVER");

    /// @notice Badge type for karma earners
    bytes32 public constant BADGE_KARMA_EARNER = keccak256("KARMA_EARNER");

    // ============ State ============

    /// @notice The Karma token contract
    IKarma public karma;

    /// @notice The SoulID contract
    ISoulID public soulID;

    /// @notice Last give timestamp per giver per recipient
    mapping(address => mapping(address => uint256)) public lastGiveTime;

    /// @notice Total karma given by address
    mapping(address => uint256) public totalGiven;

    /// @notice Total karma received by address
    mapping(address => uint256) public totalReceived;

    /// @notice Total karma earned by address (from earnKarma)
    mapping(address => uint256) public totalEarned;

    /// @notice Total karma purged from address
    mapping(address => uint256) public totalPurged;

    /// @notice Whether auto-SoulID minting is enabled
    bool public autoMintSoul;

    // ============ Events ============

    event KarmaEarned(
        address indexed account,
        uint256 amount,
        bytes32 indexed reason,
        address indexed source
    );

    event KarmaGiven(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 indexed reason
    );

    event KarmaPurged(
        address indexed account,
        uint256 amount,
        bytes32 indexed reason,
        address indexed authority
    );

    event SoulIDSynced(address indexed account, uint256 tokenId, uint256 karmaBalance);

    // ============ Errors ============

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientKarma();
    error AmountTooLarge();
    error CooldownNotExpired();
    error CannotGiveToSelf();
    error NoSoulID();

    // ============ Constructor ============

    constructor(address _karma, address _soulID, address admin, address dao) {
        if (_karma == address(0) || admin == address(0) || dao == address(0)) {
            revert ZeroAddress();
        }

        karma = IKarma(_karma);
        if (_soulID != address(0)) {
            soulID = ISoulID(_soulID);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, dao);
        _grantRole(KARMA_SOURCE_ROLE, admin);
        _grantRole(SLASHER_ROLE, dao);

        autoMintSoul = true;
    }

    // ============ Core Functions ============

    /**
     * @notice Earn karma for positive actions
     * @dev Called by authorized sources (hooks, governance, bridges)
     * @param account Address to receive karma
     * @param amount Amount of karma to mint
     * @param reason Reason code for earning
     */
    function earnKarma(
        address account,
        uint256 amount,
        bytes32 reason
    ) external onlyRole(KARMA_SOURCE_ROLE) whenNotPaused nonReentrant {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Mint karma
        karma.mint(account, amount, reason);
        karma.recordActivity(account);

        // Track stats
        totalEarned[account] += amount;

        // Sync SoulID if exists
        _syncSoulID(account);

        // Auto-mint SoulID if enabled and doesn't exist
        if (autoMintSoul && address(soulID) != address(0) && !soulID.hasSoul(account)) {
            soulID.mintSoul(account);
        }

        emit KarmaEarned(account, amount, reason, msg.sender);
    }

    /**
     * @notice Give karma to another user (praise/recognition)
     * @dev Burns karma from sender, mints to receiver (net neutral)
     * @param to Recipient address
     * @param amount Amount to give (max 100 K)
     * @param reason Reason code for giving
     */
    function giveKarma(
        address to,
        uint256 amount,
        bytes32 reason
    ) external whenNotPaused nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (to == msg.sender) revert CannotGiveToSelf();
        if (amount == 0) revert ZeroAmount();
        if (amount > MAX_GIVE_AMOUNT) revert AmountTooLarge();

        // Check sender has enough karma
        uint256 senderBalance = karma.balanceOf(msg.sender);
        if (senderBalance < amount) revert InsufficientKarma();
        if (senderBalance < MIN_KARMA_TO_GIVE) revert InsufficientKarma();

        // Check cooldown
        if (block.timestamp < lastGiveTime[msg.sender][to] + GIVE_COOLDOWN) {
            revert CooldownNotExpired();
        }

        // Update cooldown
        lastGiveTime[msg.sender][to] = block.timestamp;

        // Burn from sender
        karma.burn(msg.sender, amount, reason);

        // Mint to receiver
        karma.mint(to, amount, reason);

        // Record activity for both
        karma.recordActivity(msg.sender);
        karma.recordActivity(to);

        // Track stats
        totalGiven[msg.sender] += amount;
        totalReceived[to] += amount;

        // Sync SoulIDs
        _syncSoulID(msg.sender);
        _syncSoulID(to);

        emit KarmaGiven(msg.sender, to, amount, reason);
    }

    /**
     * @notice Purge karma as penalty (governance slashing)
     * @dev Only callable by SLASHER_ROLE (governance)
     * @param account Address to purge karma from
     * @param amount Amount to burn
     * @param reason Reason code for purging
     */
    function purgeKarma(
        address account,
        uint256 amount,
        bytes32 reason
    ) external onlyRole(SLASHER_ROLE) whenNotPaused nonReentrant {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Slash karma
        karma.slash(account, amount, reason);

        // Track stats
        totalPurged[account] += amount;

        // Sync SoulID
        _syncSoulID(account);

        emit KarmaPurged(account, amount, reason, msg.sender);
    }

    /**
     * @notice Self-sacrifice karma (voluntary burn)
     * @param amount Amount to burn
     * @param reason Reason code
     */
    function sacrificeKarma(uint256 amount, bytes32 reason) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 balance = karma.balanceOf(msg.sender);
        if (balance < amount) revert InsufficientKarma();

        karma.burn(msg.sender, amount, reason);
        totalPurged[msg.sender] += amount;

        _syncSoulID(msg.sender);

        emit KarmaPurged(msg.sender, amount, reason, msg.sender);
    }

    // ============ Batch Functions ============

    /**
     * @notice Batch earn karma for multiple accounts
     * @param accounts Addresses to receive karma
     * @param amounts Amounts per account
     * @param reason Shared reason code
     */
    function batchEarnKarma(
        address[] calldata accounts,
        uint256[] calldata amounts,
        bytes32 reason
    ) external onlyRole(KARMA_SOURCE_ROLE) whenNotPaused {
        require(accounts.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0) || amounts[i] == 0) continue;

            karma.mint(accounts[i], amounts[i], reason);
            karma.recordActivity(accounts[i]);
            totalEarned[accounts[i]] += amounts[i];

            _syncSoulID(accounts[i]);

            emit KarmaEarned(accounts[i], amounts[i], reason, msg.sender);
        }
    }

    // ============ SoulID Integration ============

    /**
     * @notice Sync karma balance to SoulID
     * @param account Address to sync
     */
    function syncSoulID(address account) external {
        _syncSoulID(account);
    }

    /**
     * @notice Internal SoulID sync
     */
    function _syncSoulID(address account) internal {
        if (address(soulID) == address(0)) return;
        if (!soulID.hasSoul(account)) return;

        uint256 tokenId = soulID.soulOf(account);
        uint256 karmaBalance = karma.balanceOf(account);

        soulID.updateKarma(tokenId, karmaBalance);

        // Update trust level based on karma (simple linear mapping)
        uint256 trustLevel = karmaBalance > 1000e18 ? 100 : (karmaBalance * 100) / 1000e18;
        soulID.updateTrustLevel(tokenId, trustLevel);

        emit SoulIDSynced(account, tokenId, karmaBalance);
    }

    // ============ View Functions ============

    /**
     * @notice Get account stats
     * @param account Address to query
     * @return earned Total earned
     * @return given Total given
     * @return received Total received
     * @return purged Total purged
     * @return balance Current balance
     */
    function getAccountStats(address account) external view returns (
        uint256 earned,
        uint256 given,
        uint256 received,
        uint256 purged,
        uint256 balance
    ) {
        earned = totalEarned[account];
        given = totalGiven[account];
        received = totalReceived[account];
        purged = totalPurged[account];
        balance = karma.balanceOf(account);
    }

    /**
     * @notice Check if user can give karma to recipient
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to give
     * @return canGive Whether giving is allowed
     * @return reason Reason if not allowed
     */
    function canGiveKarma(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool canGive, string memory reason) {
        if (to == address(0)) return (false, "Zero address");
        if (to == from) return (false, "Cannot give to self");
        if (amount == 0) return (false, "Zero amount");
        if (amount > MAX_GIVE_AMOUNT) return (false, "Amount too large");

        uint256 balance = karma.balanceOf(from);
        if (balance < amount) return (false, "Insufficient karma");
        if (balance < MIN_KARMA_TO_GIVE) return (false, "Minimum karma not met");

        if (block.timestamp < lastGiveTime[from][to] + GIVE_COOLDOWN) {
            return (false, "Cooldown not expired");
        }

        return (true, "");
    }

    /**
     * @notice Get cooldown remaining for giving karma
     * @param from Sender address
     * @param to Recipient address
     * @return remaining Seconds remaining (0 if expired)
     */
    function getCooldownRemaining(address from, address to) external view returns (uint256 remaining) {
        uint256 nextAllowed = lastGiveTime[from][to] + GIVE_COOLDOWN;
        if (block.timestamp >= nextAllowed) return 0;
        return nextAllowed - block.timestamp;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set SoulID contract
     * @param _soulID New SoulID address
     */
    function setSoulID(address _soulID) external onlyRole(GOVERNOR_ROLE) {
        soulID = ISoulID(_soulID);
    }

    /**
     * @notice Set auto-mint SoulID
     * @param enabled Whether to auto-mint
     */
    function setAutoMintSoul(bool enabled) external onlyRole(GOVERNOR_ROLE) {
        autoMintSoul = enabled;
    }

    /**
     * @notice Pause controller
     */
    function pause() external onlyRole(GOVERNOR_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause controller
     */
    function unpause() external onlyRole(GOVERNOR_ROLE) {
        _unpause();
    }
}
