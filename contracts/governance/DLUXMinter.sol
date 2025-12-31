// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDLUX {
    function mint(address to, uint256 amount, bytes32 reason) external;
    function batchMint(address[] calldata recipients, uint256[] calldata amounts, bytes32 reason) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title DLUXMinter - DAO-Controlled DLUX Emissions
 * @notice Strategic emission controller for DLUX governance token
 * @dev Implements LP-3002 extension for protocol-incentivized DLUX distribution
 *
 * DLUX EMISSION ARCHITECTURE:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  DLUX is the actual governance token - minted for strategic activities     │
 * │                                                                             │
 * │  Emission Categories:                                                       │
 * │  ┌───────────────────────────────────────────────────────────────────────┐ │
 * │  │ PROTOCOL EMISSIONS:                                                   │ │
 * │  │ - VALIDATOR_EMISSION: Bonus rewards for validators                    │ │
 * │  │ - BRIDGE_USAGE: Incentives for cross-chain bridge activity            │ │
 * │  │ - LP_PROVISION: Rewards for DEX liquidity providers                   │ │
 * │  │ - STAKING_BONUS: Extra rewards for long-term stakers                  │ │
 * │  │ - LENDING_REWARD: Rewards for lending protocol participants           │ │
 * │  └───────────────────────────────────────────────────────────────────────┘ │
 * │  ┌───────────────────────────────────────────────────────────────────────┐ │
 * │  │ COMMUNITY EMISSIONS:                                                  │ │
 * │  │ - REFERRAL: Referral program rewards                                  │ │
 * │  │ - COMMUNITY_GRANT: Grants for contributors                            │ │
 * │  │ - TREASURY_ALLOCATION: DAO treasury distributions                     │ │
 * │  │ - AIRDROP: Strategic airdrops                                         │ │
 * │  └───────────────────────────────────────────────────────────────────────┘ │
 * │                                                                             │
 * │  Collateral Backing:                                                        │
 * │  - Users can deposit LUX as collateral to mint DLUX                        │
 * │  - Unbacked emissions are tracked separately                               │
 * │  - Backing ratio = totalCollateral / totalSupply                           │
 * │  - DAO can set minimum backing ratio requirements                          │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract DLUXMinter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Roles ============

    /// @notice Role for DAO governance to configure emission params
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Role for hook contracts that can trigger emissions
    bytes32 public constant EMITTER_ROLE = keccak256("EMITTER_ROLE");

    // ============ Emission Type Constants ============

    // Protocol Emissions
    bytes32 public constant EMISSION_VALIDATOR = keccak256("VALIDATOR_EMISSION");
    bytes32 public constant EMISSION_BRIDGE = keccak256("BRIDGE_USAGE");
    bytes32 public constant EMISSION_LP = keccak256("LP_PROVISION");
    bytes32 public constant EMISSION_STAKING = keccak256("STAKING_BONUS");
    bytes32 public constant EMISSION_LENDING = keccak256("LENDING_REWARD");

    // Community Emissions
    bytes32 public constant EMISSION_REFERRAL = keccak256("REFERRAL");
    bytes32 public constant EMISSION_GRANT = keccak256("COMMUNITY_GRANT");
    bytes32 public constant EMISSION_TREASURY = keccak256("TREASURY_ALLOCATION");
    bytes32 public constant EMISSION_AIRDROP = keccak256("AIRDROP");

    // ============ Structs ============

    /// @notice Configuration for each emission type
    struct EmissionConfig {
        uint256 baseAmount;       // Base DLUX amount per emission
        uint256 maxAmount;        // Max DLUX per single emission
        uint256 cooldown;         // Cooldown between emissions for same recipient
        uint256 dailyLimit;       // Max DLUX per day for this emission type
        uint256 dailyEmitted;     // DLUX emitted today
        uint256 lastResetDay;     // Last day dailyEmitted was reset
        uint256 multiplierBps;    // Emission multiplier in basis points (10000 = 1x)
        bool enabled;             // Whether this emission type is active
        bool requiresCollateral;  // Whether collateral is required for this emission
    }

    /// @notice User collateral deposit info
    struct CollateralInfo {
        uint256 amount;           // Amount of LUX deposited as collateral
        uint256 dluxMinted;       // DLUX minted against this collateral
        uint256 depositTime;      // When collateral was deposited
    }

    // ============ State ============

    /// @notice The DLUX token
    IDLUX public dlux;

    /// @notice The LUX token (for collateral)
    IERC20 public lux;

    /// @notice Emission config per emission type
    mapping(bytes32 => EmissionConfig) public emissionConfigs;

    /// @notice Last emission timestamp per user per emission type
    mapping(address => mapping(bytes32 => uint256)) public lastEmission;

    /// @notice Total DLUX emitted per user (for analytics)
    mapping(address => uint256) public totalEmittedTo;

    /// @notice User collateral deposits
    mapping(address => CollateralInfo) public collateral;

    /// @notice Total collateral deposited
    uint256 public totalCollateral;

    /// @notice Total unbacked emissions
    uint256 public totalUnbackedEmissions;

    /// @notice Global daily limit across all emissions
    uint256 public globalDailyLimit;

    /// @notice Global daily emitted amount
    uint256 public globalDailyEmitted;

    /// @notice Last global reset day
    uint256 public globalLastResetDay;

    /// @notice Minimum backing ratio in basis points (5000 = 50%)
    uint256 public minBackingRatioBps;

    /// @notice Treasury address for excess collateral
    address public treasury;

    // ============ Events ============

    event DLUXEmitted(
        address indexed recipient,
        bytes32 indexed emissionType,
        uint256 amount,
        bytes32 reason
    );
    event EmissionConfigUpdated(bytes32 indexed emissionType, EmissionConfig config);
    event EmitterAdded(address indexed emitter, string description);
    event EmitterRemoved(address indexed emitter);
    event GlobalLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event CollateralDeposited(address indexed user, uint256 luxAmount, uint256 dluxMinted);
    event CollateralWithdrawn(address indexed user, uint256 luxAmount, uint256 dluxBurned);
    event BackingRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ============ Errors ============

    error ZeroAddress();
    error ZeroAmount();
    error EmissionNotEnabled();
    error CooldownNotExpired();
    error DailyLimitExceeded();
    error GlobalLimitExceeded();
    error AmountExceedsMax();
    error InsufficientCollateral();
    error BackingRatioTooLow();
    error CollateralLocked();

    // ============ Constructor ============

    constructor(
        address _dlux,
        address _lux,
        address _treasury,
        address admin,
        address dao
    ) {
        if (_dlux == address(0) || _lux == address(0) || _treasury == address(0) ||
            admin == address(0) || dao == address(0)) {
            revert ZeroAddress();
        }

        dlux = IDLUX(_dlux);
        lux = IERC20(_lux);
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, dao);
        _grantRole(EMITTER_ROLE, admin); // Admin can initially trigger emissions

        globalDailyLimit = 100_000e18;     // 100K DLUX per day global limit
        minBackingRatioBps = 0;            // 0% minimum backing (can be increased by DAO)

        // Initialize default configs
        _initializeDefaultConfigs();
    }

    // ============ Collateral Functions ============

    /// @notice Deposit LUX as collateral to mint DLUX
    /// @param luxAmount Amount of LUX to deposit
    /// @return dluxMinted Amount of DLUX minted
    function depositCollateral(uint256 luxAmount) external nonReentrant whenNotPaused returns (uint256 dluxMinted) {
        if (luxAmount == 0) revert ZeroAmount();

        // Transfer LUX from user
        lux.safeTransferFrom(msg.sender, address(this), luxAmount);

        // Mint DLUX 1:1
        dluxMinted = luxAmount;

        // Update collateral info
        CollateralInfo storage info = collateral[msg.sender];
        info.amount += luxAmount;
        info.dluxMinted += dluxMinted;
        info.depositTime = block.timestamp;

        totalCollateral += luxAmount;

        // Mint DLUX to user
        dlux.mint(msg.sender, dluxMinted, keccak256("COLLATERAL_DEPOSIT"));

        emit CollateralDeposited(msg.sender, luxAmount, dluxMinted);
    }

    /// @notice Withdraw collateral by burning DLUX
    /// @param dluxAmount Amount of DLUX to burn
    /// @return luxReturned Amount of LUX returned
    function withdrawCollateral(uint256 dluxAmount) external nonReentrant returns (uint256 luxReturned) {
        if (dluxAmount == 0) revert ZeroAmount();

        CollateralInfo storage info = collateral[msg.sender];
        if (dluxAmount > info.dluxMinted) revert InsufficientCollateral();

        // Calculate proportional LUX to return
        luxReturned = (dluxAmount * info.amount) / info.dluxMinted;

        // Update collateral info
        info.amount -= luxReturned;
        info.dluxMinted -= dluxAmount;
        totalCollateral -= luxReturned;

        // User must have DLUX to burn (checked by transfer)
        // Note: In a full implementation, we'd need a burn function on DLUX
        // For now, we transfer to treasury where it gets demurrged
        IERC20(address(dlux)).safeTransferFrom(msg.sender, treasury, dluxAmount);

        // Return LUX
        lux.safeTransfer(msg.sender, luxReturned);

        emit CollateralWithdrawn(msg.sender, luxReturned, dluxAmount);
    }

    // ============ Emission Functions (Called by authorized contracts) ============

    /// @notice Emit DLUX for a strategic activity (called by emitters)
    /// @param recipient Address to receive DLUX
    /// @param emissionType Type of emission
    /// @param amount Amount of DLUX to emit (0 = use baseAmount)
    /// @param reason Additional context (activity hash, tx ID, etc.)
    function emitDLUX(
        address recipient,
        bytes32 emissionType,
        uint256 amount,
        bytes32 reason
    ) external onlyRole(EMITTER_ROLE) whenNotPaused {
        EmissionConfig storage config = emissionConfigs[emissionType];

        if (!config.enabled) revert EmissionNotEnabled();

        // Check cooldown
        if (block.timestamp < lastEmission[recipient][emissionType] + config.cooldown) {
            revert CooldownNotExpired();
        }

        // Reset daily limits if new day
        _resetDailyLimits(emissionType);

        // Calculate emission amount with multiplier
        uint256 emitAmount = amount > 0 ? amount : config.baseAmount;
        emitAmount = (emitAmount * config.multiplierBps) / 10000;
        if (emitAmount > config.maxAmount) revert AmountExceedsMax();

        // Check daily limits
        if (config.dailyEmitted + emitAmount > config.dailyLimit) {
            revert DailyLimitExceeded();
        }
        if (globalDailyEmitted + emitAmount > globalDailyLimit) {
            revert GlobalLimitExceeded();
        }

        // Check backing ratio if required
        if (minBackingRatioBps > 0) {
            uint256 newTotalSupply = dlux.totalSupply() + emitAmount;
            uint256 newBackingRatio = (totalCollateral * 10000) / newTotalSupply;
            if (newBackingRatio < minBackingRatioBps) {
                revert BackingRatioTooLow();
            }
        }

        // Update state
        config.dailyEmitted += emitAmount;
        globalDailyEmitted += emitAmount;
        lastEmission[recipient][emissionType] = block.timestamp;
        totalEmittedTo[recipient] += emitAmount;
        totalUnbackedEmissions += emitAmount;

        // Emit DLUX
        dlux.mint(recipient, emitAmount, reason);

        emit DLUXEmitted(recipient, emissionType, emitAmount, reason);
    }

    /// @notice Batch emit DLUX to multiple recipients
    /// @param recipients Addresses to receive DLUX
    /// @param emissionType Type of emission
    /// @param amounts Amounts per recipient (0 = use baseAmount)
    /// @param reason Shared reason for batch
    function batchEmitDLUX(
        address[] calldata recipients,
        bytes32 emissionType,
        uint256[] calldata amounts,
        bytes32 reason
    ) external onlyRole(EMITTER_ROLE) whenNotPaused {
        require(recipients.length == amounts.length, "Length mismatch");

        EmissionConfig storage config = emissionConfigs[emissionType];
        if (!config.enabled) revert EmissionNotEnabled();

        _resetDailyLimits(emissionType);

        address[] memory validRecipients = new address[](recipients.length);
        uint256[] memory validAmounts = new uint256[](recipients.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];

            // Skip if cooldown not expired
            if (block.timestamp < lastEmission[recipient][emissionType] + config.cooldown) {
                continue;
            }

            uint256 emitAmount = amounts[i] > 0 ? amounts[i] : config.baseAmount;
            emitAmount = (emitAmount * config.multiplierBps) / 10000;
            if (emitAmount > config.maxAmount) {
                emitAmount = config.maxAmount;
            }

            // Check daily limits
            if (config.dailyEmitted + emitAmount > config.dailyLimit) {
                break;
            }
            if (globalDailyEmitted + emitAmount > globalDailyLimit) {
                break;
            }

            // Update state
            config.dailyEmitted += emitAmount;
            globalDailyEmitted += emitAmount;
            lastEmission[recipient][emissionType] = block.timestamp;
            totalEmittedTo[recipient] += emitAmount;
            totalUnbackedEmissions += emitAmount;

            validRecipients[validCount] = recipient;
            validAmounts[validCount] = emitAmount;
            validCount++;

            emit DLUXEmitted(recipient, emissionType, emitAmount, reason);
        }

        // Batch mint
        if (validCount > 0) {
            // Resize arrays to valid count
            address[] memory finalRecipients = new address[](validCount);
            uint256[] memory finalAmounts = new uint256[](validCount);
            for (uint256 i = 0; i < validCount; i++) {
                finalRecipients[i] = validRecipients[i];
                finalAmounts[i] = validAmounts[i];
            }
            dlux.batchMint(finalRecipients, finalAmounts, reason);
        }
    }

    // ============ Governance Functions ============

    /// @notice Update emission config for an emission type
    /// @param emissionType Emission type to configure
    /// @param config New configuration
    function setEmissionConfig(
        bytes32 emissionType,
        EmissionConfig calldata config
    ) external onlyRole(GOVERNOR_ROLE) {
        emissionConfigs[emissionType] = config;
        emit EmissionConfigUpdated(emissionType, config);
    }

    /// @notice Enable/disable an emission type
    /// @param emissionType Emission type to toggle
    /// @param enabled Whether to enable
    function setEmissionEnabled(
        bytes32 emissionType,
        bool enabled
    ) external onlyRole(GOVERNOR_ROLE) {
        emissionConfigs[emissionType].enabled = enabled;
        emit EmissionConfigUpdated(emissionType, emissionConfigs[emissionType]);
    }

    /// @notice Update base amount for an emission type
    /// @param emissionType Emission type to update
    /// @param baseAmount New base amount
    function setBaseAmount(
        bytes32 emissionType,
        uint256 baseAmount
    ) external onlyRole(GOVERNOR_ROLE) {
        emissionConfigs[emissionType].baseAmount = baseAmount;
        emit EmissionConfigUpdated(emissionType, emissionConfigs[emissionType]);
    }

    /// @notice Update emission multiplier
    /// @param emissionType Emission type to update
    /// @param multiplierBps New multiplier in basis points
    function setMultiplier(
        bytes32 emissionType,
        uint256 multiplierBps
    ) external onlyRole(GOVERNOR_ROLE) {
        emissionConfigs[emissionType].multiplierBps = multiplierBps;
        emit EmissionConfigUpdated(emissionType, emissionConfigs[emissionType]);
    }

    /// @notice Update global daily limit
    /// @param newLimit New global daily limit
    function setGlobalDailyLimit(uint256 newLimit) external onlyRole(GOVERNOR_ROLE) {
        emit GlobalLimitUpdated(globalDailyLimit, newLimit);
        globalDailyLimit = newLimit;
    }

    /// @notice Update minimum backing ratio
    /// @param newRatioBps New ratio in basis points
    function setMinBackingRatio(uint256 newRatioBps) external onlyRole(GOVERNOR_ROLE) {
        emit BackingRatioUpdated(minBackingRatioBps, newRatioBps);
        minBackingRatioBps = newRatioBps;
    }

    /// @notice Update treasury address
    /// @param newTreasury New treasury address
    function setTreasury(address newTreasury) external onlyRole(GOVERNOR_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice Add an emitter contract that can trigger emissions
    /// @param emitter Address of emitter contract
    /// @param description Human-readable description
    function addEmitter(address emitter, string calldata description) external onlyRole(GOVERNOR_ROLE) {
        _grantRole(EMITTER_ROLE, emitter);
        emit EmitterAdded(emitter, description);
    }

    /// @notice Remove an emitter contract
    /// @param emitter Address to remove
    function removeEmitter(address emitter) external onlyRole(GOVERNOR_ROLE) {
        _revokeRole(EMITTER_ROLE, emitter);
        emit EmitterRemoved(emitter);
    }

    // ============ Chain Fee Emission ============

    /// @notice Emission rate per LUX of fees (1 DLUX per 10 LUX of fees = 10%)
    uint256 public feeEmissionRate = 1000; // 10% = 1000 BPS

    /// @notice Chain-specific fee emission multipliers (BPS, 10000 = 1x)
    mapping(uint8 => uint256) public chainFeeMultiplier;

    /// @notice Record fee-based DLUX emission when ChainFeeRegistry distributes fees
    /// @dev Called by ChainFeeRegistry after fee distribution
    /// @param chainId The chain that generated the fees (0-10)
    /// @param feeAmount Amount of LUX fees distributed
    function recordFeeEmission(uint8 chainId, uint256 feeAmount) 
        external 
        onlyRole(EMITTER_ROLE) 
        whenNotPaused 
    {
        if (feeAmount == 0) return;

        // Calculate DLUX to emit based on fee amount and chain multiplier
        uint256 multiplier = chainFeeMultiplier[chainId];
        if (multiplier == 0) multiplier = 10000; // Default 1x

        // Base emission: feeEmissionRate% of fees, adjusted by chain multiplier
        uint256 dluxAmount = (feeAmount * feeEmissionRate * multiplier) / (10000 * 10000);

        if (dluxAmount == 0) return;

        // Check global daily limit
        _resetDailyLimits(keccak256("FEE_EMISSION"));
        if (globalDailyEmitted + dluxAmount > globalDailyLimit) {
            dluxAmount = globalDailyLimit - globalDailyEmitted;
        }
        if (dluxAmount == 0) return;

        // Mint to treasury (fees generate DLUX for treasury, not individual users)
        globalDailyEmitted += dluxAmount;
        bytes32 reason = bytes32(uint256(chainId));
        dlux.mint(treasury, dluxAmount, reason);

        emit DLUXEmitted(
            treasury,
            keccak256("FEE_EMISSION"),
            dluxAmount,
            reason
        );
    }

    /// @notice Set fee emission rate (BPS)
    function setFeeEmissionRate(uint256 rate) external onlyRole(GOVERNOR_ROLE) {
        require(rate <= 5000, "Max 50%"); // Cap at 50%
        feeEmissionRate = rate;
    }

    /// @notice Set chain-specific fee multiplier
    function setChainFeeMultiplier(uint8 chainId, uint256 multiplier) external onlyRole(GOVERNOR_ROLE) {
        require(multiplier <= 30000, "Max 3x"); // Cap at 3x
        chainFeeMultiplier[chainId] = multiplier;
    }

    /// @notice Pause all emissions
    function pause() external onlyRole(GOVERNOR_ROLE) {
        _pause();
    }

    /// @notice Unpause emissions
    function unpause() external onlyRole(GOVERNOR_ROLE) {
        _unpause();
    }

    // ============ View Functions ============

    /// @notice Get config for an emission type
    function getEmissionConfig(bytes32 emissionType) external view returns (EmissionConfig memory) {
        return emissionConfigs[emissionType];
    }

    /// @notice Check if recipient can receive emission
    function canReceiveEmission(
        address recipient,
        bytes32 emissionType
    ) external view returns (bool canReceive, string memory reason) {
        EmissionConfig memory config = emissionConfigs[emissionType];

        if (!config.enabled) {
            return (false, "Emission not enabled");
        }

        if (block.timestamp < lastEmission[recipient][emissionType] + config.cooldown) {
            return (false, "Cooldown not expired");
        }

        uint256 currentDay = block.timestamp / 1 days;
        uint256 effectiveDailyEmitted = config.lastResetDay < currentDay ? 0 : config.dailyEmitted;
        if (effectiveDailyEmitted + config.baseAmount > config.dailyLimit) {
            return (false, "Emission daily limit exceeded");
        }

        uint256 effectiveGlobalEmitted = globalLastResetDay < currentDay ? 0 : globalDailyEmitted;
        if (effectiveGlobalEmitted + config.baseAmount > globalDailyLimit) {
            return (false, "Global daily limit exceeded");
        }

        return (true, "");
    }

    /// @notice Get remaining daily quota for an emission type
    function getRemainingDailyQuota(bytes32 emissionType) external view returns (uint256) {
        EmissionConfig memory config = emissionConfigs[emissionType];
        uint256 currentDay = block.timestamp / 1 days;

        uint256 effectiveEmitted = config.lastResetDay < currentDay ? 0 : config.dailyEmitted;
        return config.dailyLimit > effectiveEmitted ? config.dailyLimit - effectiveEmitted : 0;
    }

    /// @notice Get current backing ratio
    function backingRatio() external view returns (uint256 ratioBps) {
        uint256 supply = dlux.totalSupply();
        if (supply == 0) return 10000; // 100% if no supply
        return (totalCollateral * 10000) / supply;
    }

    /// @notice Get collateral info for user
    function getCollateralInfo(address user) external view returns (
        uint256 luxDeposited,
        uint256 dluxMinted,
        uint256 depositTime
    ) {
        CollateralInfo memory info = collateral[user];
        return (info.amount, info.dluxMinted, info.depositTime);
    }

    // ============ Internal Functions ============

    function _resetDailyLimits(bytes32 emissionType) internal {
        uint256 currentDay = block.timestamp / 1 days;

        // Reset emission-specific limit
        EmissionConfig storage config = emissionConfigs[emissionType];
        if (config.lastResetDay < currentDay) {
            config.dailyEmitted = 0;
            config.lastResetDay = currentDay;
        }

        // Reset global limit
        if (globalLastResetDay < currentDay) {
            globalDailyEmitted = 0;
            globalLastResetDay = currentDay;
        }
    }

    function _initializeDefaultConfigs() internal {
        // Protocol Emissions (continuous, activity-based)
        emissionConfigs[EMISSION_VALIDATOR] = EmissionConfig({
            baseAmount: 100e18,        // 100 DLUX base
            maxAmount: 1000e18,        // Max 1000 DLUX per emission
            cooldown: 1 days,          // Daily validator rewards
            dailyLimit: 50_000e18,     // 50K DLUX per day
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,      // 1x
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_BRIDGE] = EmissionConfig({
            baseAmount: 10e18,         // 10 DLUX per bridge tx
            maxAmount: 100e18,
            cooldown: 0,               // No cooldown (per tx)
            dailyLimit: 20_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_LP] = EmissionConfig({
            baseAmount: 50e18,         // 50 DLUX for LP provision
            maxAmount: 500e18,
            cooldown: 1 days,
            dailyLimit: 30_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_STAKING] = EmissionConfig({
            baseAmount: 25e18,         // 25 DLUX staking bonus
            maxAmount: 250e18,
            cooldown: 7 days,          // Weekly staking bonus
            dailyLimit: 25_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_LENDING] = EmissionConfig({
            baseAmount: 20e18,
            maxAmount: 200e18,
            cooldown: 1 days,
            dailyLimit: 15_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        // Community Emissions
        emissionConfigs[EMISSION_REFERRAL] = EmissionConfig({
            baseAmount: 50e18,         // 50 DLUX per referral
            maxAmount: 50e18,
            cooldown: 0,               // Per referral
            dailyLimit: 10_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_GRANT] = EmissionConfig({
            baseAmount: 500e18,        // 500 DLUX grant base
            maxAmount: 10_000e18,      // Up to 10K for major contributions
            cooldown: 30 days,
            dailyLimit: 20_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_TREASURY] = EmissionConfig({
            baseAmount: 1000e18,
            maxAmount: 100_000e18,     // Large treasury allocations
            cooldown: 0,
            dailyLimit: 100_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });

        emissionConfigs[EMISSION_AIRDROP] = EmissionConfig({
            baseAmount: 100e18,
            maxAmount: 1000e18,
            cooldown: 0,
            dailyLimit: 50_000e18,
            dailyEmitted: 0,
            lastResetDay: 0,
            multiplierBps: 10000,
            enabled: true,
            requiresCollateral: false
        });
    }
}
