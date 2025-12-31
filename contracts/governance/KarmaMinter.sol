// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface IKarma {
    function mint(address to, uint256 amount, bytes32 reason) external;
    function burn(address from, uint256 amount, bytes32 reason) external;
    function recordActivity(address account) external;
    function verify(address account) external;
    function linkDID(address account, bytes32 did) external;
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title KarmaMinter - DAO-Controlled Karma Minting
 * @notice Configurable mint params for positive events with hooks
 * @dev Implements LP-3002 extension for event-based Karma rewards
 *
 * EVENT TYPES:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  Identity Events:                                                           │
 * │  - DID_VERIFICATION: Link/verify DID                                        │
 * │  - HUMANITY_PROOF: Proof of humanity attestation                            │
 * │                                                                             │
 * │  Governance Events:                                                         │
 * │  - PROPOSAL_CREATED: Create governance proposal                             │
 * │  - PROPOSAL_PASSED: Proposal passes quorum/majority                         │
 * │  - VOTE_CAST: Vote on proposal                                              │
 * │  - DELEGATE_RECEIVED: Receive delegation from others                        │
 * │                                                                             │
 * │  Protocol Events:                                                           │
 * │  - LIQUIDITY_PROVIDED: Add liquidity to DEX pools                           │
 * │  - STAKE_LONG_TERM: Stake for extended period                               │
 * │  - BRIDGE_USAGE: Use cross-chain bridge                                     │
 * │                                                                             │
 * │  Community Events:                                                          │
 * │  - BUG_BOUNTY: Report security issue                                        │
 * │  - CONTRIBUTION: Community contribution (docs, code, etc.)                  │
 * │  - REFERRAL: Bring new users                                                │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract KarmaMinter is AccessControl, Pausable {
    // ============ Roles ============

    /// @notice Role for DAO governance to configure mint params
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Role for hook contracts that can trigger minting
    bytes32 public constant HOOK_ROLE = keccak256("HOOK_ROLE");

    // ============ Event Type Constants ============

    // Identity Events
    bytes32 public constant EVENT_DID_VERIFICATION = keccak256("DID_VERIFICATION");
    bytes32 public constant EVENT_HUMANITY_PROOF = keccak256("HUMANITY_PROOF");

    // Governance Events
    bytes32 public constant EVENT_PROPOSAL_CREATED = keccak256("PROPOSAL_CREATED");
    bytes32 public constant EVENT_PROPOSAL_PASSED = keccak256("PROPOSAL_PASSED");
    bytes32 public constant EVENT_VOTE_CAST = keccak256("VOTE_CAST");
    bytes32 public constant EVENT_DELEGATE_RECEIVED = keccak256("DELEGATE_RECEIVED");

    // Protocol Events
    bytes32 public constant EVENT_LIQUIDITY_PROVIDED = keccak256("LIQUIDITY_PROVIDED");
    bytes32 public constant EVENT_STAKE_LONG_TERM = keccak256("STAKE_LONG_TERM");
    bytes32 public constant EVENT_BRIDGE_USAGE = keccak256("BRIDGE_USAGE");

    // Community Events
    bytes32 public constant EVENT_BUG_BOUNTY = keccak256("BUG_BOUNTY");
    bytes32 public constant EVENT_CONTRIBUTION = keccak256("CONTRIBUTION");
    bytes32 public constant EVENT_REFERRAL = keccak256("REFERRAL");

    // ============ Structs ============

    /// @notice Configuration for each event type
    struct MintConfig {
        uint256 baseAmount;      // Base K amount to mint
        uint256 maxAmount;       // Max K per event (for variable rewards)
        uint256 cooldown;        // Cooldown between rewards for same user
        uint256 dailyLimit;      // Max K per day for this event type
        uint256 dailyMinted;     // K minted today for this event
        uint256 lastResetDay;    // Last day dailyMinted was reset
        bool enabled;            // Whether this event type is active
        bool requiresVerified;   // Whether user must be verified
    }

    // ============ State ============

    /// @notice The Karma contract
    IKarma public karma;

    /// @notice Mint config per event type
    mapping(bytes32 => MintConfig) public mintConfigs;

    /// @notice Last reward timestamp per user per event type
    mapping(address => mapping(bytes32 => uint256)) public lastReward;

    /// @notice Total K minted per user (for analytics)
    mapping(address => uint256) public totalMintedTo;

    /// @notice Global daily limit across all events
    uint256 public globalDailyLimit;

    /// @notice Global daily minted amount
    uint256 public globalDailyMinted;

    /// @notice Last global reset day
    uint256 public globalLastResetDay;

    // ============ Events ============

    event KarmaRewarded(
        address indexed recipient,
        bytes32 indexed eventType,
        uint256 amount,
        bytes32 reason
    );
    event KarmaStruck(
        address indexed striker,
        address indexed target,
        uint256 strikerBurned,
        uint256 targetBurned,
        bytes32 reason
    );
    event MintConfigUpdated(bytes32 indexed eventType, MintConfig config);
    event HookAdded(address indexed hook, string description);
    event HookRemoved(address indexed hook);
    event GlobalLimitUpdated(uint256 oldLimit, uint256 newLimit);

    // ============ Constants for Strike ============

    /// @notice Ratio of striker K burned to target K burned (2:1 = burn 2 to strike 1)
    uint256 public constant STRIKE_RATIO = 2;

    /// @notice Max percentage of target's K that can be struck per day (10%)
    uint256 public constant MAX_STRIKE_PERCENT = 1000;

    // ============ Errors ============

    error ZeroAddress();
    error EventNotEnabled();
    error CooldownNotExpired();
    error DailyLimitExceeded();
    error GlobalLimitExceeded();
    error AmountExceedsMax();
    error UserNotVerified();
    error CannotMintForSelf();
    error InsufficientKarmaToStrike();
    error StrikeAmountTooLarge();

    // ============ Constructor ============

    constructor(address _karma, address admin, address dao) {
        if (_karma == address(0) || admin == address(0) || dao == address(0)) {
            revert ZeroAddress();
        }

        karma = IKarma(_karma);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, dao);
        _grantRole(HOOK_ROLE, admin); // Admin can initially trigger hooks

        globalDailyLimit = 1_000_000e18; // 1M K per day global limit

        // Initialize default configs
        _initializeDefaultConfigs();
    }

    // ============ Hook Functions (Called by authorized contracts) ============

    /// @notice Reward Karma for an event (called by hooks)
    /// @dev IMPORTANT: Cannot mint to msg.sender - must always mint to others
    /// @param recipient Address to reward
    /// @param eventType Type of event
    /// @param amount Amount of K to mint (must be <= config.maxAmount)
    /// @param reason Additional context (proposal ID, contribution hash, etc.)
    function rewardKarma(
        address recipient,
        bytes32 eventType,
        uint256 amount,
        bytes32 reason
    ) external onlyRole(HOOK_ROLE) whenNotPaused {
        // Cannot mint karma for yourself
        if (recipient == msg.sender) revert CannotMintForSelf();

        MintConfig storage config = mintConfigs[eventType];

        if (!config.enabled) revert EventNotEnabled();

        // Check cooldown
        if (block.timestamp < lastReward[recipient][eventType] + config.cooldown) {
            revert CooldownNotExpired();
        }

        // Reset daily limits if new day
        _resetDailyLimits(eventType);

        // Validate amount
        uint256 mintAmount = amount > 0 ? amount : config.baseAmount;
        if (mintAmount > config.maxAmount) revert AmountExceedsMax();

        // Check daily limits
        if (config.dailyMinted + mintAmount > config.dailyLimit) {
            revert DailyLimitExceeded();
        }
        if (globalDailyMinted + mintAmount > globalDailyLimit) {
            revert GlobalLimitExceeded();
        }

        // Update state
        config.dailyMinted += mintAmount;
        globalDailyMinted += mintAmount;
        lastReward[recipient][eventType] = block.timestamp;
        totalMintedTo[recipient] += mintAmount;

        // Mint Karma
        karma.mint(recipient, mintAmount, reason);

        // Record activity (reduces decay)
        karma.recordActivity(recipient);

        emit KarmaRewarded(recipient, eventType, mintAmount, reason);
    }

    /// @notice Batch reward multiple recipients
    /// @param recipients Addresses to reward
    /// @param eventType Type of event
    /// @param amounts Amounts per recipient (0 = use baseAmount)
    /// @param reason Shared reason for batch
    function batchRewardKarma(
        address[] calldata recipients,
        bytes32 eventType,
        uint256[] calldata amounts,
        bytes32 reason
    ) external onlyRole(HOOK_ROLE) whenNotPaused {
        require(recipients.length == amounts.length, "Length mismatch");

        MintConfig storage config = mintConfigs[eventType];
        if (!config.enabled) revert EventNotEnabled();

        _resetDailyLimits(eventType);

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];

            // Skip if cooldown not expired
            if (block.timestamp < lastReward[recipient][eventType] + config.cooldown) {
                continue;
            }

            uint256 mintAmount = amounts[i] > 0 ? amounts[i] : config.baseAmount;
            if (mintAmount > config.maxAmount) {
                mintAmount = config.maxAmount;
            }

            // Check daily limits
            if (config.dailyMinted + mintAmount > config.dailyLimit) {
                break; // Stop if daily limit reached
            }
            if (globalDailyMinted + mintAmount > globalDailyLimit) {
                break;
            }

            // Update state
            config.dailyMinted += mintAmount;
            globalDailyMinted += mintAmount;
            lastReward[recipient][eventType] = block.timestamp;
            totalMintedTo[recipient] += mintAmount;

            // Mint
            karma.mint(recipient, mintAmount, reason);
            karma.recordActivity(recipient);

            emit KarmaRewarded(recipient, eventType, mintAmount, reason);
        }
    }

    // ============ Strike Functions (Community moderation) ============

    /// @notice Strike another user's Karma by burning your own
    /// @dev Burn 2 K from yourself to strike 1 K from target (2:1 ratio)
    /// @dev Max 10% of target's K can be struck per day
    /// @param target Address to strike
    /// @param amount Amount of target's K to strike (will burn 2x from striker)
    /// @param reason Reason for striking (hash of evidence)
    function strikeKarma(
        address target,
        uint256 amount,
        bytes32 reason
    ) external whenNotPaused {
        if (target == address(0)) revert ZeroAddress();
        if (target == msg.sender) revert CannotMintForSelf(); // Can't strike yourself
        if (amount == 0) revert AmountExceedsMax();

        // Calculate how much striker needs to burn (2:1 ratio)
        uint256 strikerBurn = amount * STRIKE_RATIO;

        // Check striker has enough K
        uint256 strikerBalance = karma.balanceOf(msg.sender);
        if (strikerBalance < strikerBurn) revert InsufficientKarmaToStrike();

        // Check target has enough K
        uint256 targetBalance = karma.balanceOf(target);
        if (amount > targetBalance) revert StrikeAmountTooLarge();

        // Check daily strike limit (max 10% of target's K per day)
        uint256 maxDailyStrike = (targetBalance * MAX_STRIKE_PERCENT) / 10000;
        if (amount > maxDailyStrike) revert StrikeAmountTooLarge();

        // Burn from striker (2x the strike amount)
        karma.burn(msg.sender, strikerBurn, reason);

        // Burn from target (the strike amount)
        karma.burn(target, amount, reason);

        emit KarmaStruck(msg.sender, target, strikerBurn, amount, reason);
    }

    /// @notice Sacrifice your own Karma for the community (burn without striking)
    /// @param amount Amount to burn
    /// @param reason Reason for sacrifice
    function sacrificeKarma(uint256 amount, bytes32 reason) external {
        if (amount == 0) revert AmountExceedsMax();

        uint256 balance = karma.balanceOf(msg.sender);
        if (balance < amount) revert InsufficientKarmaToStrike();

        karma.burn(msg.sender, amount, reason);
    }

    // ============ Governance Functions ============

    /// @notice Update mint config for an event type
    /// @param eventType Event type to configure
    /// @param config New configuration
    function setMintConfig(
        bytes32 eventType,
        MintConfig calldata config
    ) external onlyRole(GOVERNOR_ROLE) {
        mintConfigs[eventType] = config;
        emit MintConfigUpdated(eventType, config);
    }

    /// @notice Enable/disable an event type
    /// @param eventType Event type to toggle
    /// @param enabled Whether to enable
    function setEventEnabled(
        bytes32 eventType,
        bool enabled
    ) external onlyRole(GOVERNOR_ROLE) {
        mintConfigs[eventType].enabled = enabled;
        emit MintConfigUpdated(eventType, mintConfigs[eventType]);
    }

    /// @notice Update base amount for an event type
    /// @param eventType Event type to update
    /// @param baseAmount New base amount
    function setBaseAmount(
        bytes32 eventType,
        uint256 baseAmount
    ) external onlyRole(GOVERNOR_ROLE) {
        mintConfigs[eventType].baseAmount = baseAmount;
        emit MintConfigUpdated(eventType, mintConfigs[eventType]);
    }

    /// @notice Update cooldown for an event type
    /// @param eventType Event type to update
    /// @param cooldown New cooldown in seconds
    function setCooldown(
        bytes32 eventType,
        uint256 cooldown
    ) external onlyRole(GOVERNOR_ROLE) {
        mintConfigs[eventType].cooldown = cooldown;
        emit MintConfigUpdated(eventType, mintConfigs[eventType]);
    }

    /// @notice Update global daily limit
    /// @param newLimit New global daily limit
    function setGlobalDailyLimit(uint256 newLimit) external onlyRole(GOVERNOR_ROLE) {
        emit GlobalLimitUpdated(globalDailyLimit, newLimit);
        globalDailyLimit = newLimit;
    }

    /// @notice Add a hook contract that can trigger rewards
    /// @param hook Address of hook contract
    /// @param description Human-readable description
    function addHook(address hook, string calldata description) external onlyRole(GOVERNOR_ROLE) {
        _grantRole(HOOK_ROLE, hook);
        emit HookAdded(hook, description);
    }

    /// @notice Remove a hook contract
    /// @param hook Address to remove
    function removeHook(address hook) external onlyRole(GOVERNOR_ROLE) {
        _revokeRole(HOOK_ROLE, hook);
        emit HookRemoved(hook);
    }

    /// @notice Pause all minting
    function pause() external onlyRole(GOVERNOR_ROLE) {
        _pause();
    }

    /// @notice Unpause minting
    function unpause() external onlyRole(GOVERNOR_ROLE) {
        _unpause();
    }

    // ============ View Functions ============

    /// @notice Get config for an event type
    function getMintConfig(bytes32 eventType) external view returns (MintConfig memory) {
        return mintConfigs[eventType];
    }

    /// @notice Check if user can receive reward
    function canReceiveReward(
        address recipient,
        bytes32 eventType
    ) external view returns (bool canReceive, string memory reason) {
        MintConfig memory config = mintConfigs[eventType];

        if (!config.enabled) {
            return (false, "Event not enabled");
        }

        if (block.timestamp < lastReward[recipient][eventType] + config.cooldown) {
            return (false, "Cooldown not expired");
        }

        uint256 currentDay = block.timestamp / 1 days;
        uint256 effectiveDailyMinted = config.lastResetDay < currentDay ? 0 : config.dailyMinted;
        if (effectiveDailyMinted + config.baseAmount > config.dailyLimit) {
            return (false, "Event daily limit exceeded");
        }

        uint256 effectiveGlobalMinted = globalLastResetDay < currentDay ? 0 : globalDailyMinted;
        if (effectiveGlobalMinted + config.baseAmount > globalDailyLimit) {
            return (false, "Global daily limit exceeded");
        }

        return (true, "");
    }

    /// @notice Get remaining daily quota for an event type
    function getRemainingDailyQuota(bytes32 eventType) external view returns (uint256) {
        MintConfig memory config = mintConfigs[eventType];
        uint256 currentDay = block.timestamp / 1 days;

        uint256 effectiveMinted = config.lastResetDay < currentDay ? 0 : config.dailyMinted;
        return config.dailyLimit > effectiveMinted ? config.dailyLimit - effectiveMinted : 0;
    }

    // ============ Internal Functions ============

    function _resetDailyLimits(bytes32 eventType) internal {
        uint256 currentDay = block.timestamp / 1 days;

        // Reset event-specific limit
        MintConfig storage config = mintConfigs[eventType];
        if (config.lastResetDay < currentDay) {
            config.dailyMinted = 0;
            config.lastResetDay = currentDay;
        }

        // Reset global limit
        if (globalLastResetDay < currentDay) {
            globalDailyMinted = 0;
            globalLastResetDay = currentDay;
        }
    }

    function _initializeDefaultConfigs() internal {
        // Identity Events (one-time, higher rewards)
        mintConfigs[EVENT_DID_VERIFICATION] = MintConfig({
            baseAmount: 100e18,      // 100 K
            maxAmount: 100e18,
            cooldown: 365 days,      // Once per year
            dailyLimit: 10_000e18,   // 10K K per day
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: false
        });

        mintConfigs[EVENT_HUMANITY_PROOF] = MintConfig({
            baseAmount: 200e18,      // 200 K
            maxAmount: 200e18,
            cooldown: 365 days,
            dailyLimit: 20_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: false
        });

        // Governance Events (frequent, smaller rewards)
        mintConfigs[EVENT_PROPOSAL_CREATED] = MintConfig({
            baseAmount: 25e18,       // 25 K
            maxAmount: 50e18,
            cooldown: 7 days,        // Once per week
            dailyLimit: 500e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: true
        });

        mintConfigs[EVENT_PROPOSAL_PASSED] = MintConfig({
            baseAmount: 50e18,       // 50 K
            maxAmount: 100e18,
            cooldown: 0,             // Per proposal
            dailyLimit: 1_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: true
        });

        mintConfigs[EVENT_VOTE_CAST] = MintConfig({
            baseAmount: 1e18,        // 1 K per vote
            maxAmount: 5e18,
            cooldown: 0,             // Per proposal
            dailyLimit: 10_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: false
        });

        // Protocol Events
        mintConfigs[EVENT_LIQUIDITY_PROVIDED] = MintConfig({
            baseAmount: 10e18,       // 10 K
            maxAmount: 50e18,
            cooldown: 1 days,
            dailyLimit: 50_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: false
        });

        mintConfigs[EVENT_STAKE_LONG_TERM] = MintConfig({
            baseAmount: 5e18,        // 5 K per month staked
            maxAmount: 100e18,
            cooldown: 30 days,
            dailyLimit: 100_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: false
        });

        // Community Events
        mintConfigs[EVENT_BUG_BOUNTY] = MintConfig({
            baseAmount: 100e18,      // 100 K base
            maxAmount: 500e18,       // Up to 500 K for critical
            cooldown: 0,
            dailyLimit: 5_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: true
        });

        mintConfigs[EVENT_CONTRIBUTION] = MintConfig({
            baseAmount: 25e18,       // 25 K
            maxAmount: 100e18,
            cooldown: 7 days,
            dailyLimit: 10_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: false
        });

        mintConfigs[EVENT_REFERRAL] = MintConfig({
            baseAmount: 10e18,       // 10 K per referral
            maxAmount: 10e18,
            cooldown: 0,
            dailyLimit: 50_000e18,
            dailyMinted: 0,
            lastResetDay: 0,
            enabled: true,
            requiresVerified: true
        });
    }
}
