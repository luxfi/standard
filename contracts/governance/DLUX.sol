// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DLUX - DAO LUX Rebasing Governance Token
 * @notice OHM-style rebasing token with demurrage mechanics
 * @dev Implements LP-3002 Governance Token Stack
 *
 * DLUX TOKENOMICS:
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │  DLUX is a rebasing governance token backed 1:1 by staked LUX              │
 * │                                                                             │
 * │  Properties:                                                                │
 * │  - Backing: 1 LUX = 1 DLUX (redeemable)                                     │
 * │  - Rebase Rate: 0.3-0.5% per epoch (8 hours)                                │
 * │  - Demurrage: 0.1% per day on unstaked DLUX                                 │
 * │  - Transferable: Yes                                                        │
 * │                                                                             │
 * │  Staking Tiers:                                                             │
 * │  - Bronze (100+): 1.0x boost                                                │
 * │  - Silver (1K+): 1.1x boost, 7d lock                                        │
 * │  - Gold (10K+): 1.25x boost, 30d lock                                       │
 * │  - Diamond (100K+): 1.5x boost, 90d lock                                    │
 * │  - Quantum (1M+): 2.0x boost, 365d lock                                     │
 * │                                                                             │
 * │  Rebase Math:                                                               │
 * │  Daily APY = (1 + rebaseRate)^3 - 1 (3 epochs/day)                          │
 * │  Example: 0.4% per epoch = 1.2% daily ≈ 7800% APY                           │
 * │                                                                             │
 * │  Demurrage Math:                                                            │
 * │  balance_after = balance_before × (1 - 0.001)^days                          │
 * │  After 365 days: 1000 DLUX → 694.0 DLUX (unstaked)                          │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract DLUX is ERC20, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Role for rebase operators
    bytes32 public constant REBASE_ROLE = keccak256("REBASE_ROLE");

    /// @notice Role for parameter governance
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Epoch duration (8 hours)
    uint256 public constant EPOCH_DURATION = 8 hours;

    /// @notice Demurrage rate per day in basis points (10 = 0.1%)
    uint256 public constant DEMURRAGE_BPS = 10;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Maximum rebase rate per epoch in basis points (50 = 0.5%)
    uint256 public constant MAX_REBASE_RATE = 50;

    /// @notice Minimum rebase rate per epoch in basis points (30 = 0.3%)
    uint256 public constant MIN_REBASE_RATE = 30;

    /// @notice Staking tier thresholds (in wei)
    uint256 public constant TIER_BRONZE = 100e18;
    uint256 public constant TIER_SILVER = 1_000e18;
    uint256 public constant TIER_GOLD = 10_000e18;
    uint256 public constant TIER_DIAMOND = 100_000e18;
    uint256 public constant TIER_QUANTUM = 1_000_000e18;

    /// @notice Lock periods per tier
    uint256 public constant LOCK_SILVER = 7 days;
    uint256 public constant LOCK_GOLD = 30 days;
    uint256 public constant LOCK_DIAMOND = 90 days;
    uint256 public constant LOCK_QUANTUM = 365 days;

    /// @notice Tier boosts in basis points (10000 = 1.0x)
    uint256 public constant BOOST_BRONZE = 10000;   // 1.0x
    uint256 public constant BOOST_SILVER = 11000;   // 1.1x
    uint256 public constant BOOST_GOLD = 12500;     // 1.25x
    uint256 public constant BOOST_DIAMOND = 15000;  // 1.5x
    uint256 public constant BOOST_QUANTUM = 20000;  // 2.0x

    // ============ Types ============

    enum Tier { None, Bronze, Silver, Gold, Diamond, Quantum }

    struct StakeInfo {
        uint256 amount;         // Amount staked
        uint256 lockEnd;        // Lock end timestamp
        uint256 lastRebase;     // Last rebase claim timestamp
        uint256 pendingRebase;  // Accumulated unclaimed rebases
        Tier tier;              // Current tier
    }

    struct DemurrageInfo {
        uint256 balance;        // Balance subject to demurrage
        uint256 lastUpdate;     // Last demurrage calculation timestamp
    }

    // ============ State ============

    /// @notice The LUX token
    IERC20 public immutable lux;

    /// @notice Current rebase rate in basis points
    uint256 public rebaseRate;

    /// @notice Current epoch
    uint256 public epoch;

    /// @notice Last epoch timestamp
    uint256 public lastEpochTime;

    /// @notice Total staked DLUX
    uint256 public totalStaked;

    /// @notice Protocol treasury address
    address public treasury;

    /// @notice Staking info per user
    mapping(address => StakeInfo) public stakes;

    /// @notice Demurrage tracking for unstaked balances
    mapping(address => DemurrageInfo) private _demurrage;

    /// @notice Whether emissions are paused
    bool public paused;

    // ============ Events ============

    event Staked(address indexed user, uint256 amount, Tier tier, uint256 lockEnd);
    event Unstaked(address indexed user, uint256 amount, uint256 luxReturned);
    event RebaseClaimed(address indexed user, uint256 amount);
    event Rebased(uint256 epoch, uint256 totalRebased, uint256 rate);
    event DemurrageApplied(address indexed account, uint256 burned);
    event TierUpgraded(address indexed user, Tier from, Tier to);
    event RebaseRateUpdated(uint256 oldRate, uint256 newRate);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event Paused(bool status);

    // ============ Errors ============

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error LockNotExpired();
    error InvalidTier();
    error InvalidRebaseRate();
    error EpochNotReady();
    error IsPaused();
    error DowngradeTier();

    // ============ Constructor ============

    constructor(
        address _lux,
        address _treasury,
        address admin
    ) ERC20("DAO LUX", "DLUX") {
        if (_lux == address(0) || _treasury == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }

        lux = IERC20(_lux);
        treasury = _treasury;
        rebaseRate = 40; // 0.4% per epoch default

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REBASE_ROLE, admin);
        _grantRole(GOVERNOR_ROLE, admin);

        lastEpochTime = block.timestamp;
    }

    // ============ External Functions ============

    /// @notice Stake LUX to receive DLUX
    /// @param amount Amount of LUX to stake
    /// @param tier Desired staking tier
    /// @return dluxMinted Amount of DLUX minted
    function stake(uint256 amount, Tier tier) external nonReentrant returns (uint256 dluxMinted) {
        if (paused) revert IsPaused();
        if (amount == 0) revert ZeroAmount();
        if (tier == Tier.None) revert InvalidTier();

        // Validate tier requirements
        uint256 newTotal = stakes[msg.sender].amount + amount;
        _validateTier(tier, newTotal);

        // Transfer LUX from user
        lux.safeTransferFrom(msg.sender, address(this), amount);

        // Update stake info
        StakeInfo storage info = stakes[msg.sender];

        // Claim any pending rebases first
        if (info.pendingRebase > 0) {
            _claimRebase(msg.sender);
        }

        // Calculate new lock end
        uint256 lockPeriod = _getLockPeriod(tier);
        uint256 newLockEnd = block.timestamp + lockPeriod;

        // Only extend lock, never reduce
        if (newLockEnd < info.lockEnd) {
            newLockEnd = info.lockEnd;
        }

        // Check for tier upgrade
        Tier oldTier = info.tier;
        if (tier > oldTier) {
            emit TierUpgraded(msg.sender, oldTier, tier);
        } else if (tier < oldTier) {
            revert DowngradeTier();
        }

        info.amount = newTotal;
        info.lockEnd = newLockEnd;
        info.lastRebase = block.timestamp;
        info.tier = tier;

        totalStaked += amount;
        dluxMinted = amount;

        // Mint DLUX 1:1
        _mint(msg.sender, amount);

        emit Staked(msg.sender, amount, tier, newLockEnd);
    }

    /// @notice Unstake DLUX to receive LUX
    /// @param amount Amount of DLUX to unstake
    /// @return luxReturned Amount of LUX returned
    function unstake(uint256 amount) external nonReentrant returns (uint256 luxReturned) {
        if (amount == 0) revert ZeroAmount();

        StakeInfo storage info = stakes[msg.sender];
        if (amount > info.amount) revert InsufficientBalance();
        if (block.timestamp < info.lockEnd) revert LockNotExpired();

        // Claim pending rebases first
        if (info.pendingRebase > 0) {
            _claimRebase(msg.sender);
        }

        // Update stake info
        info.amount -= amount;
        totalStaked -= amount;

        // Burn DLUX
        _burn(msg.sender, amount);

        // Return LUX 1:1
        luxReturned = amount;
        lux.safeTransfer(msg.sender, luxReturned);

        // Update tier if needed
        if (info.amount < _getTierMinimum(info.tier)) {
            info.tier = _calculateTier(info.amount);
        }

        emit Unstaked(msg.sender, amount, luxReturned);
    }

    /// @notice Redeem DLUX for underlying LUX 1:1 (no lock)
    /// @dev Only works for unstaked DLUX balance
    /// @param amount Amount to redeem
    /// @return luxReturned Amount of LUX returned
    function redeem(uint256 amount) external nonReentrant returns (uint256 luxReturned) {
        if (amount == 0) revert ZeroAmount();

        // Apply demurrage first
        _applyDemurrage(msg.sender);

        uint256 unstaked = balanceOf(msg.sender) - stakes[msg.sender].amount;
        if (amount > unstaked) revert InsufficientBalance();

        // Burn DLUX
        _burn(msg.sender, amount);

        // Return LUX 1:1
        luxReturned = amount;
        lux.safeTransfer(msg.sender, luxReturned);
    }

    /// @notice Claim accumulated rebases
    /// @return rebased Amount of DLUX rebased
    function claimRebase() external nonReentrant returns (uint256 rebased) {
        return _claimRebase(msg.sender);
    }

    /// @notice Get pending rebase amount for account
    /// @param account Address to query
    /// @return pending Pending rebase amount
    function pendingRebase(address account) external view returns (uint256 pending) {
        StakeInfo memory info = stakes[account];
        if (info.amount == 0) return 0;

        pending = info.pendingRebase;

        // Calculate additional rebases since last claim
        uint256 epochsSince = (block.timestamp - info.lastRebase) / EPOCH_DURATION;
        if (epochsSince > 0) {
            uint256 boost = _getTierBoost(info.tier);
            uint256 epochRebase = (info.amount * rebaseRate * boost) / (BPS_DENOMINATOR * BPS_DENOMINATOR);
            pending += epochRebase * epochsSince;
        }

        return pending;
    }

    /// @notice Apply demurrage to account (anyone can call)
    /// @param account Address to apply demurrage
    function applyDemurrage(address account) external {
        _applyDemurrage(account);
    }

    /// @notice Trigger epoch rebase (callable by anyone when epoch is ready)
    function rebase() external nonReentrant {
        if (paused) revert IsPaused();
        if (block.timestamp < lastEpochTime + EPOCH_DURATION) revert EpochNotReady();

        uint256 epochs = (block.timestamp - lastEpochTime) / EPOCH_DURATION;
        if (epochs == 0) revert EpochNotReady();

        // Update epoch tracking
        epoch += epochs;
        lastEpochTime = lastEpochTime + (epochs * EPOCH_DURATION);

        // Calculate total rebase amount
        uint256 totalRebased = (totalStaked * rebaseRate * epochs) / BPS_DENOMINATOR;

        emit Rebased(epoch, totalRebased, rebaseRate);
    }

    // ============ View Functions ============

    /// @notice Get staking tier for account
    /// @param account Address to query
    /// @return tier Current tier
    /// @return boost Boost multiplier in basis points
    function tierOf(address account) external view returns (Tier tier, uint256 boost) {
        tier = stakes[account].tier;
        boost = _getTierBoost(tier);
    }

    /// @notice Get stake details for account
    /// @param account Address to query
    function getStake(address account) external view returns (
        uint256 amount,
        uint256 lockEnd,
        Tier tier,
        uint256 boost
    ) {
        StakeInfo memory info = stakes[account];
        return (info.amount, info.lockEnd, info.tier, _getTierBoost(info.tier));
    }

    /// @notice Get effective balance after demurrage
    /// @param account Address to query
    /// @return Effective balance
    function effectiveBalance(address account) external view returns (uint256) {
        uint256 staked = stakes[account].amount;
        uint256 unstaked = balanceOf(account) - staked;

        if (unstaked == 0) return staked;

        // Calculate demurrage on unstaked portion
        DemurrageInfo memory dem = _demurrage[account];
        if (dem.lastUpdate == 0) {
            dem.balance = unstaked;
            dem.lastUpdate = block.timestamp;
        }

        uint256 daysPassed = (block.timestamp - dem.lastUpdate) / 1 days;
        if (daysPassed > 0) {
            // Compound demurrage
            for (uint256 i = 0; i < daysPassed && i < 365; i++) {
                unstaked = (unstaked * (BPS_DENOMINATOR - DEMURRAGE_BPS)) / BPS_DENOMINATOR;
            }
        }

        return staked + unstaked;
    }

    // ============ Governance Functions ============

    /// @notice Set rebase rate (governance only)
    /// @param newRate New rate in basis points
    function setRebaseRate(uint256 newRate) external onlyRole(GOVERNOR_ROLE) {
        if (newRate < MIN_REBASE_RATE || newRate > MAX_REBASE_RATE) {
            revert InvalidRebaseRate();
        }
        emit RebaseRateUpdated(rebaseRate, newRate);
        rebaseRate = newRate;
    }

    /// @notice Set treasury address
    /// @param newTreasury New treasury address
    function setTreasury(address newTreasury) external onlyRole(GOVERNOR_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice Pause/unpause emissions
    /// @param _paused Paused status
    function setPaused(bool _paused) external onlyRole(GOVERNOR_ROLE) {
        paused = _paused;
        emit Paused(_paused);
    }

    // ============ Internal Functions ============

    function _claimRebase(address account) internal returns (uint256 rebased) {
        StakeInfo storage info = stakes[account];
        if (info.amount == 0) return 0;

        // Calculate epochs since last claim
        uint256 epochsSince = (block.timestamp - info.lastRebase) / EPOCH_DURATION;

        if (epochsSince > 0) {
            uint256 boost = _getTierBoost(info.tier);
            uint256 epochRebase = (info.amount * rebaseRate * boost) / (BPS_DENOMINATOR * BPS_DENOMINATOR);
            info.pendingRebase += epochRebase * epochsSince;
        }

        rebased = info.pendingRebase;
        if (rebased > 0) {
            info.pendingRebase = 0;
            info.lastRebase = block.timestamp;

            // Mint rebased DLUX (backed by treasury)
            _mint(account, rebased);

            emit RebaseClaimed(account, rebased);
        }
    }

    function _applyDemurrage(address account) internal {
        uint256 staked = stakes[account].amount;
        uint256 total = balanceOf(account);
        uint256 unstaked = total > staked ? total - staked : 0;

        if (unstaked == 0) return;

        DemurrageInfo storage dem = _demurrage[account];
        if (dem.lastUpdate == 0) {
            dem.balance = unstaked;
            dem.lastUpdate = block.timestamp;
            return;
        }

        uint256 daysPassed = (block.timestamp - dem.lastUpdate) / 1 days;
        if (daysPassed == 0) return;

        // Calculate demurrage
        uint256 remaining = unstaked;
        for (uint256 i = 0; i < daysPassed && i < 365; i++) {
            remaining = (remaining * (BPS_DENOMINATOR - DEMURRAGE_BPS)) / BPS_DENOMINATOR;
        }

        uint256 burned = unstaked - remaining;
        if (burned > 0) {
            _burn(account, burned);
            emit DemurrageApplied(account, burned);
        }

        dem.balance = remaining;
        dem.lastUpdate = block.timestamp;
    }

    function _validateTier(Tier tier, uint256 amount) internal pure {
        uint256 minimum = _getTierMinimum(tier);
        if (amount < minimum) revert InvalidTier();
    }

    function _getTierMinimum(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Quantum) return TIER_QUANTUM;
        if (tier == Tier.Diamond) return TIER_DIAMOND;
        if (tier == Tier.Gold) return TIER_GOLD;
        if (tier == Tier.Silver) return TIER_SILVER;
        if (tier == Tier.Bronze) return TIER_BRONZE;
        return 0;
    }

    function _getTierBoost(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Quantum) return BOOST_QUANTUM;
        if (tier == Tier.Diamond) return BOOST_DIAMOND;
        if (tier == Tier.Gold) return BOOST_GOLD;
        if (tier == Tier.Silver) return BOOST_SILVER;
        if (tier == Tier.Bronze) return BOOST_BRONZE;
        return BPS_DENOMINATOR; // 1.0x for no tier
    }

    function _getLockPeriod(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.Quantum) return LOCK_QUANTUM;
        if (tier == Tier.Diamond) return LOCK_DIAMOND;
        if (tier == Tier.Gold) return LOCK_GOLD;
        if (tier == Tier.Silver) return LOCK_SILVER;
        return 0; // Bronze has no lock
    }

    function _calculateTier(uint256 amount) internal pure returns (Tier) {
        if (amount >= TIER_QUANTUM) return Tier.Quantum;
        if (amount >= TIER_DIAMOND) return Tier.Diamond;
        if (amount >= TIER_GOLD) return Tier.Gold;
        if (amount >= TIER_SILVER) return Tier.Silver;
        if (amount >= TIER_BRONZE) return Tier.Bronze;
        return Tier.None;
    }

    /// @dev Override to apply demurrage before transfers
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Apply demurrage on sender if not minting
        if (from != address(0)) {
            _applyDemurrage(from);
        }

        super._update(from, to, amount);

        // Initialize demurrage tracking for receiver
        if (to != address(0) && from != address(0)) {
            DemurrageInfo storage dem = _demurrage[to];
            if (dem.lastUpdate == 0) {
                dem.lastUpdate = block.timestamp;
            }
        }
    }
}
