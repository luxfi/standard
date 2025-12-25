// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title BabylonStrategy
 * @notice Yield strategies for Babylon BTC staking ecosystem
 * @dev Supports two yield sources:
 *
 * 1. BabylonBTCStrategy - Native BTC staking via Babylon protocol
 *    - Timelock-based staking with variable lock periods
 *    - Direct integration with Babylon's BTC staking contracts
 *    - Rewards from securing PoS chains via BTC restaking
 *
 * 2. LombardLBTCStrategy - Lombard LBTC liquid staking
 *    - Liquid staking token wrapping Babylon-staked BTC
 *    - No lockup, instant liquidity via LBTC token
 *    - Composable with DeFi protocols
 *
 * Babylon Protocol Overview:
 * - BTC holders stake to secure PoS chains (Cosmos, Ethereum L2s, etc.)
 * - No bridge/wrap required for native BTC staking
 * - Slashing enforced via Bitcoin script covenants
 * - Rewards paid in native BTC or chain tokens
 *
 * Lombard LBTC:
 * - Liquid staking derivative for Babylon-staked BTC
 * - 1:1 backed by BTC in Babylon staking
 * - Enables DeFi composability while earning staking yield
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// BABYLON INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Babylon BTC staking interface
interface IBabylonStaking {
    /// @notice Stake BTC with timelock
    /// @param amount Amount of BTC (in satoshis) to stake
    /// @param lockTime Lock duration in seconds
    /// @return stakeId Unique identifier for this stake
    function stake(uint256 amount, uint64 lockTime) external returns (bytes32 stakeId);

    /// @notice Unstake BTC after lock period expires
    /// @param stakeId Stake identifier from stake()
    function unstake(bytes32 stakeId) external;

    /// @notice Claim accumulated rewards for a stake
    /// @param stakeId Stake identifier
    /// @return Amount of rewards claimed
    function claimRewards(bytes32 stakeId) external returns (uint256);

    /// @notice Get stake details
    /// @param stakeId Stake identifier
    /// @return amount Staked amount in satoshis
    /// @return lockTime Original lock duration
    /// @return unlockTime Timestamp when stake can be withdrawn
    /// @return active Whether stake is still active
    function getStake(bytes32 stakeId) external view returns (
        uint256 amount,
        uint64 lockTime,
        uint64 unlockTime,
        bool active
    );

    /// @notice Get pending rewards for a stake
    /// @param stakeId Stake identifier
    /// @return Pending reward amount
    function pendingRewards(bytes32 stakeId) external view returns (uint256);

    /// @notice Get total BTC staked in protocol
    /// @return Total staked in satoshis
    function totalStaked() external view returns (uint256);

    /// @notice Get current staking APY
    /// @return APY in basis points (500 = 5%)
    function stakingAPY() external view returns (uint256);
}

/// @notice Lombard LBTC liquid staking token interface
interface ILBTC {
    /// @notice Deposit BTC to receive LBTC
    /// @param btcAmount Amount of BTC to deposit
    /// @return lbtcAmount Amount of LBTC received
    function deposit(uint256 btcAmount) external returns (uint256 lbtcAmount);

    /// @notice Withdraw BTC by burning LBTC
    /// @param lbtcAmount Amount of LBTC to burn
    /// @return btcAmount Amount of BTC received
    function withdraw(uint256 lbtcAmount) external returns (uint256 btcAmount);

    /// @notice Get current exchange rate (BTC per LBTC, scaled by 1e18)
    /// @return Exchange rate
    function exchangeRate() external view returns (uint256);

    /// @notice Get total BTC held by protocol
    /// @return Total assets in BTC
    function totalAssets() external view returns (uint256);

    /// @notice ERC20 balance of account
    function balanceOf(address account) external view returns (uint256);

    /// @notice ERC20 transfer
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice ERC20 approve
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Total LBTC supply
    function totalSupply() external view returns (uint256);
}

/// @notice Lombard staking interface for additional yield
interface ILombardStaking {
    /// @notice Stake LBTC for additional rewards
    /// @param amount Amount of LBTC to stake
    /// @return shares Staking shares received
    function stake(uint256 amount) external returns (uint256 shares);

    /// @notice Unstake LBTC
    /// @param shares Shares to unstake
    /// @return amount LBTC amount received
    function unstake(uint256 shares) external returns (uint256 amount);

    /// @notice Claim pending rewards
    /// @return Reward amount claimed
    function claimRewards() external returns (uint256);

    /// @notice Get pending rewards for account
    /// @param account Staker address
    /// @return Pending rewards
    function pendingRewards(address account) external view returns (uint256);

    /// @notice Get staked LBTC balance
    /// @param account Staker address
    /// @return Staked amount
    function stakedBalance(address account) external view returns (uint256);

    /// @notice Get current APY
    /// @return APY in basis points
    function getAPY() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BABYLON BTC STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title BabylonBTCStrategy
 * @notice Native BTC staking via Babylon protocol with timelock
 * @dev Manages BTC stakes with variable lock periods for maximum yield
 *
 * Lock Period Tiers:
 * - 30 days: Base APY
 * - 90 days: Base + 1%
 * - 180 days: Base + 2%
 * - 365 days: Base + 3%
 *
 * Security Model:
 * - BTC locked via Bitcoin script covenants
 * - Slashing enforced on-chain for validator misbehavior
 * - No custody risk - self-custodial staking
 */
contract BabylonBTCStrategy is Ownable{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Satoshis per BTC
    uint256 public constant SATOSHIS = 1e8;

    /// @notice Minimum lock period (30 days)
    uint64 public constant MIN_LOCK = 30 days;

    /// @notice Maximum lock period (365 days)
    uint64 public constant MAX_LOCK = 365 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Babylon staking contract
    IBabylonStaking public immutable babylonStaking;

    /// @notice WBTC or LBTC token used as deposit
    IERC20 public immutable btcToken;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Default lock period for new stakes
    uint64 public defaultLockPeriod;

    /// @notice Active stake IDs managed by this strategy
    bytes32[] public activeStakes;

    /// @notice Mapping of stake ID to index in activeStakes
    mapping(bytes32 => uint256) public stakeIndex;

    /// @notice Total BTC staked across all active stakes
    uint256 public totalStakedAmount;

    /// @notice Total rewards harvested
    uint256 public totalHarvested;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Compound rewards automatically
    bool public autoCompound = true;

    /// @notice Total deposited amount for accounting
    uint256 public totalDeposited;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when BTC is staked
    event Staked(bytes32 indexed stakeId, uint256 amount, uint64 lockTime, uint64 unlockTime);

    /// @notice Emitted when BTC is unstaked
    event Unstaked(bytes32 indexed stakeId, uint256 amount);

    /// @notice Emitted when rewards are harvested
    event RewardsHarvested(bytes32 indexed stakeId, uint256 amount);

    /// @notice Emitted when rewards are compounded
    event RewardsCompounded(uint256 amount, bytes32 newStakeId);

    /// @notice Emitted when lock period is updated
    event LockPeriodUpdated(uint64 oldPeriod, uint64 newPeriod);

    /// @notice Emitted when auto-compound setting changes
    event AutoCompoundUpdated(bool enabled);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Strategy is not active
    error NotActive();

    /// @notice Only vault can call
    error OnlyVault();

    /// @notice Insufficient balance for operation
    error InsufficientBalance();

    /// @notice Amount is zero
    error ZeroAmount();

    /// @notice Invalid lock period
    error InvalidLockPeriod();

    /// @notice Stake is still locked
    error StakeLocked();

    /// @notice Stake not found
    error StakeNotFound();

    /// @notice No stakes available
    error NoActiveStakes();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Construct Babylon BTC strategy
     * @param _vault Vault that controls this strategy
     * @param _babylonStaking Babylon staking contract address
     * @param _btcToken WBTC or wrapped BTC token address
     * @param _lockPeriod Default lock period in seconds
     */
    constructor(
        address _vault,
        address _babylonStaking,
        address _btcToken,
        uint64 _lockPeriod
    ) Ownable(msg.sender) {
        if (_lockPeriod < MIN_LOCK || _lockPeriod > MAX_LOCK) {
            revert InvalidLockPeriod();
        }

        vault = _vault;
        babylonStaking = IBabylonStaking(_babylonStaking);
        btcToken = IERC20(_btcToken);
        defaultLockPeriod = _lockPeriod;

        // Approve Babylon staking to spend BTC
        btcToken.approve(_babylonStaking, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer BTC from vault
        btcToken.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        // Stake in Babylon with default lock period
        bytes32 stakeId = babylonStaking.stake(amount, defaultLockPeriod);

        // Track stake
        stakeIndex[stakeId] = activeStakes.length;
        activeStakes.push(stakeId);
        totalStakedAmount += amount;

        // Shares equal to amount for simplicity (1:1)
        shares = amount;

        // Get stake details for event
        (, , uint64 unlockTime, ) = babylonStaking.getStake(stakeId);
        emit Staked(stakeId, amount, defaultLockPeriod, unlockTime);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalStakedAmount) revert InsufficientBalance();

        // Find unlocked stakes to withdraw from
        uint256 remaining = shares;
        uint256 i = 0;

        while (remaining > 0 && i < activeStakes.length) {
            bytes32 stakeId = activeStakes[i];
            (uint256 stakeAmount, , uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(stakeId);

            // Skip if locked or inactive
            if (!stakeActive || block.timestamp < unlockTime) {
                i++;
                continue;
            }

            // Claim any pending rewards first
            uint256 rewards = babylonStaking.pendingRewards(stakeId);
            if (rewards > 0) {
                babylonStaking.claimRewards(stakeId);
                emit RewardsHarvested(stakeId, rewards);
            }

            // Unstake
            babylonStaking.unstake(stakeId);

            uint256 withdrawn = stakeAmount > remaining ? remaining : stakeAmount;
            remaining -= withdrawn;
            amount += withdrawn;

            emit Unstaked(stakeId, stakeAmount);

            // Remove from active stakes
            _removeStake(stakeId);
        }

        if (amount == 0) revert StakeLocked();

        totalStakedAmount -= amount;

        // Update total deposited
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        // Transfer BTC to recipient
        btcToken.safeTransfer(vault, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        for (uint256 i = 0; i < activeStakes.length; i++) {
            bytes32 stakeId = activeStakes[i];
            uint256 pending = babylonStaking.pendingRewards(stakeId);

            if (pending > 0) {
                uint256 claimed = babylonStaking.claimRewards(stakeId);
                harvested += claimed;
                emit RewardsHarvested(stakeId, claimed);
            }
        }

        totalHarvested += harvested;
        lastHarvest = block.timestamp;

        // Auto-compound if enabled
        if (autoCompound && harvested > 0) {
            bytes32 newStakeId = babylonStaking.stake(harvested, defaultLockPeriod);
            stakeIndex[newStakeId] = activeStakes.length;
            activeStakes.push(newStakeId);
            totalStakedAmount += harvested;
            emit RewardsCompounded(harvested, newStakeId);
        } else if (harvested > 0) {
            // Transfer to vault if not compounding
            btcToken.safeTransfer(vault, harvested);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalStakedAmount + _pendingRewardsTotal();
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        return babylonStaking.stakingAPY();
    }

    /// @notice
    function asset() external view returns (address) {
        return address(btcToken);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Babylon BTC Staking Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get total pending rewards across all stakes
    function pendingRewardsTotal() external view returns (uint256) {
        return _pendingRewardsTotal();
    }

    /// @notice Get number of active stakes
    function activeStakeCount() external view returns (uint256) {
        return activeStakes.length;
    }

    /// @notice Get stake details by index
    function getStakeByIndex(uint256 index) external view returns (
        bytes32 stakeId,
        uint256 amount,
        uint64 lockTime,
        uint64 unlockTime,
        bool stakeActive,
        uint256 pendingRewards
    ) {
        if (index >= activeStakes.length) revert StakeNotFound();
        stakeId = activeStakes[index];
        (amount, lockTime, unlockTime, stakeActive) = babylonStaking.getStake(stakeId);
        pendingRewards = babylonStaking.pendingRewards(stakeId);
    }

    /// @notice Get unlocked stakes ready for withdrawal
    function getUnlockedStakes() external view returns (bytes32[] memory, uint256 totalUnlocked) {
        uint256 count = 0;

        // First pass: count unlocked
        for (uint256 i = 0; i < activeStakes.length; i++) {
            (, , uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(activeStakes[i]);
            if (stakeActive && block.timestamp >= unlockTime) {
                count++;
            }
        }

        // Second pass: collect
        bytes32[] memory unlocked = new bytes32[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < activeStakes.length; i++) {
            (uint256 stakeAmount, , uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(activeStakes[i]);
            if (stakeActive && block.timestamp >= unlockTime) {
                unlocked[j] = activeStakes[i];
                totalUnlocked += stakeAmount;
                j++;
            }
        }

        return (unlocked, totalUnlocked);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set default lock period
    function setLockPeriod(uint64 _lockPeriod) external onlyOwner {
        if (_lockPeriod < MIN_LOCK || _lockPeriod > MAX_LOCK) {
            revert InvalidLockPeriod();
        }
        emit LockPeriodUpdated(defaultLockPeriod, _lockPeriod);
        defaultLockPeriod = _lockPeriod;
    }

    /// @notice Set auto-compound setting
    function setAutoCompound(bool _enabled) external onlyOwner {
        autoCompound = _enabled;
        emit AutoCompoundUpdated(_enabled);
    }

    /// @notice Set strategy active status
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /// @notice Set vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Emergency withdraw all unlocked stakes
    function emergencyWithdraw() external onlyOwner {
        uint256 totalWithdrawn = 0;

        for (uint256 i = activeStakes.length; i > 0; i--) {
            bytes32 stakeId = activeStakes[i - 1];
            (uint256 stakeAmount, , uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(stakeId);

            if (stakeActive && block.timestamp >= unlockTime) {
                // Claim rewards
                uint256 rewards = babylonStaking.pendingRewards(stakeId);
                if (rewards > 0) {
                    babylonStaking.claimRewards(stakeId);
                    totalWithdrawn += rewards;
                }

                // Unstake
                babylonStaking.unstake(stakeId);
                totalWithdrawn += stakeAmount;

                // Remove from array
                activeStakes.pop();
            }
        }

        totalStakedAmount = 0;
        active = false;

        // Transfer all BTC to owner
        uint256 balance = btcToken.balanceOf(address(this));
        if (balance > 0) {
            btcToken.safeTransfer(owner(), balance);
        }
    }

    /// @notice Rescue stuck tokens (not BTC being staked)
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(btcToken), "Cannot rescue staked token");
        IERC20(token).safeTransfer(owner(), amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Calculate total pending rewards
    function _pendingRewardsTotal() internal view returns (uint256 total) {
        for (uint256 i = 0; i < activeStakes.length; i++) {
            total += babylonStaking.pendingRewards(activeStakes[i]);
        }
    }

    /// @dev Remove stake from active stakes array
    function _removeStake(bytes32 stakeId) internal {
        uint256 index = stakeIndex[stakeId];
        uint256 lastIndex = activeStakes.length - 1;

        if (index != lastIndex) {
            bytes32 lastStakeId = activeStakes[lastIndex];
            activeStakes[index] = lastStakeId;
            stakeIndex[lastStakeId] = index;
        }

        activeStakes.pop();
        delete stakeIndex[stakeId];
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOMBARD LBTC STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title LombardLBTCStrategy
 * @notice Liquid BTC staking via Lombard LBTC
 * @dev Wraps BTC into LBTC liquid staking token with optional Lombard staking
 *
 * Yield Sources:
 * 1. Base LBTC yield from Babylon staking (auto-compounding)
 * 2. Additional Lombard staking rewards (if staked in Lombard vault)
 *
 * Advantages over native Babylon staking:
 * - Instant liquidity (no lockup)
 * - DeFi composability (use as collateral, LP, etc.)
 * - Automatic reward compounding
 *
 * Trade-offs:
 * - Smart contract risk (LBTC contracts)
 * - Slight yield reduction for liquidity premium
 * - Exchange rate risk (LBTC:BTC ratio)
 */
contract LombardLBTCStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Precision for exchange rate
    uint256 public constant PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Lombard LBTC token
    ILBTC public immutable lbtc;

    /// @notice Lombard staking contract (optional)
    ILombardStaking public immutable lombardStaking;

    /// @notice Whether Lombard staking is enabled
    bool public immutable hasLombardStaking;

    /// @notice Underlying BTC token (WBTC)
    IERC20 public immutable btcToken;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice LBTC balance held (either directly or staked)
    uint256 public totalLBTC;

    /// @notice Staking shares if staked in Lombard
    uint256 public stakingShares;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Last exchange rate (for yield tracking)
    uint256 public lastExchangeRate;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Total rewards harvested
    uint256 public totalHarvested;

    /// @notice Total deposited amount for accounting
    uint256 public totalDeposited;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when BTC is deposited for LBTC
    event Deposited(uint256 btcAmount, uint256 lbtcReceived, bool staked);

    /// @notice Emitted when LBTC is withdrawn for BTC
    event Withdrawn(uint256 lbtcBurned, uint256 btcReceived);

    /// @notice Emitted when yield is harvested
    event YieldHarvested(uint256 yieldAmount);

    /// @notice Emitted when Lombard rewards are claimed
    event LombardRewardsClaimed(uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Strategy is not active
    error NotActive();

    /// @notice Only vault can call
    error OnlyVault();

    /// @notice Insufficient balance
    error InsufficientBalance();

    /// @notice Zero amount
    error ZeroAmount();

    /// @notice Slippage too high
    error SlippageTooHigh();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Construct Lombard LBTC strategy
     * @param _vault Vault that controls this strategy
     * @param _lbtc LBTC token address
     * @param _btcToken WBTC token address
     * @param _lombardStaking Lombard staking contract (address(0) to skip)
     */
    constructor(
        address _vault,
        address _lbtc,
        address _btcToken,
        address _lombardStaking
    ) Ownable(msg.sender) {
        vault = _vault;
        lbtc = ILBTC(_lbtc);
        btcToken = IERC20(_btcToken);
        lombardStaking = ILombardStaking(_lombardStaking);
        hasLombardStaking = _lombardStaking != address(0);

        // Approve LBTC to spend BTC for deposits
        btcToken.approve(_lbtc, type(uint256).max);

        // Approve Lombard staking to spend LBTC if enabled
        if (hasLombardStaking) {
            lbtc.approve(_lombardStaking, type(uint256).max);
        }

        // Initialize exchange rate tracking
        lastExchangeRate = lbtc.exchangeRate();
        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer BTC from vault
        btcToken.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        // Deposit BTC for LBTC
        uint256 lbtcReceived = lbtc.deposit(amount);
        totalLBTC += lbtcReceived;

        // Stake in Lombard if available
        if (hasLombardStaking) {
            uint256 newShares = lombardStaking.stake(lbtcReceived);
            stakingShares += newShares;
        }

        // Shares equal to LBTC received
        shares = lbtcReceived;

        emit Deposited(amount, lbtcReceived, hasLombardStaking);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalLBTC) revert InsufficientBalance();

        // Unstake from Lombard if staked
        if (hasLombardStaking && stakingShares > 0) {
            // Calculate proportional shares to unstake
            uint256 sharesToUnstake = (stakingShares * shares) / totalLBTC;
            lombardStaking.unstake(sharesToUnstake);
            stakingShares -= sharesToUnstake;

            // Claim any pending rewards
            uint256 rewards = lombardStaking.pendingRewards(address(this));
            if (rewards > 0) {
                lombardStaking.claimRewards();
                emit LombardRewardsClaimed(rewards);
            }
        }

        totalLBTC -= shares;

        // Withdraw BTC by burning LBTC
        amount = lbtc.withdraw(shares);

        // Update total deposited
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        // Transfer BTC to recipient
        btcToken.safeTransfer(vault, amount);

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Calculate yield from exchange rate appreciation
        uint256 currentRate = lbtc.exchangeRate();

        if (currentRate > lastExchangeRate && totalLBTC > 0) {
            // Yield = LBTC * (new_rate - old_rate) / PRECISION
            uint256 rateGain = currentRate - lastExchangeRate;
            uint256 yieldInBTC = (totalLBTC * rateGain) / PRECISION;
            harvested += yieldInBTC;
            emit YieldHarvested(yieldInBTC);
        }

        // Claim Lombard staking rewards if available
        if (hasLombardStaking) {
            uint256 pending = lombardStaking.pendingRewards(address(this));
            if (pending > 0) {
                uint256 claimed = lombardStaking.claimRewards();
                harvested += claimed;
                emit LombardRewardsClaimed(claimed);
            }
        }

        lastExchangeRate = currentRate;
        lastHarvest = block.timestamp;
        totalHarvested += harvested;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        // LBTC value in BTC terms
        uint256 lbtcValue = (totalLBTC * lbtc.exchangeRate()) / PRECISION;

        // Add pending Lombard rewards
        if (hasLombardStaking) {
            lbtcValue += lombardStaking.pendingRewards(address(this));
        }

        return lbtcValue;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Base LBTC yield (from Babylon staking)
        // Estimate based on exchange rate growth
        uint256 baseAPY = 500; // 5% default estimate

        // Add Lombard staking APY if enabled
        if (hasLombardStaking) {
            baseAPY += lombardStaking.getAPY();
        }

        return baseAPY;
    }

    /// @notice
    function asset() external view returns (address) {
        return address(btcToken);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Lombard LBTC Liquid Staking Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get current LBTC exchange rate
    function exchangeRate() external view returns (uint256) {
        return lbtc.exchangeRate();
    }

    /// @notice Get pending Lombard staking rewards
    function pendingRewards() external view returns (uint256) {
        if (!hasLombardStaking) return 0;
        return lombardStaking.pendingRewards(address(this));
    }

    /// @notice Get LBTC balance breakdown
    function balanceBreakdown() external view returns (
        uint256 lbtcTotal,
        uint256 lbtcHeld,
        uint256 lbtcStaked,
        uint256 btcValue
    ) {
        lbtcTotal = totalLBTC;
        lbtcHeld = hasLombardStaking ? 0 : totalLBTC;
        lbtcStaked = hasLombardStaking ? lombardStaking.stakedBalance(address(this)) : 0;
        btcValue = (totalLBTC * lbtc.exchangeRate()) / PRECISION;
    }

    /// @notice Calculate unrealized yield from exchange rate appreciation
    function unrealizedYield() external view returns (uint256) {
        uint256 currentRate = lbtc.exchangeRate();
        if (currentRate <= lastExchangeRate || totalLBTC == 0) return 0;

        uint256 rateGain = currentRate - lastExchangeRate;
        return (totalLBTC * rateGain) / PRECISION;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set strategy active status
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /// @notice Set vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        // Unstake from Lombard if staked
        if (hasLombardStaking && stakingShares > 0) {
            lombardStaking.unstake(stakingShares);
            lombardStaking.claimRewards();
            stakingShares = 0;
        }

        // Withdraw all LBTC for BTC
        uint256 lbtcBalance = lbtc.balanceOf(address(this));
        if (lbtcBalance > 0) {
            lbtc.withdraw(lbtcBalance);
        }

        totalLBTC = 0;
        active = false;

        // Transfer all BTC to owner
        uint256 btcBalance = btcToken.balanceOf(address(this));
        if (btcBalance > 0) {
            btcToken.safeTransfer(owner(), btcBalance);
        }
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(btcToken) && token != address(lbtc), "Cannot rescue strategy tokens");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORIES
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title BabylonStrategyFactory
 * @notice Factory for deploying Babylon BTC staking strategies
 */
contract BabylonStrategyFactory {
    /// @notice Emitted when a Babylon strategy is deployed
    event BabylonStrategyDeployed(
        address indexed strategy,
        address indexed vault,
        address babylonStaking,
        uint64 lockPeriod
    );

    /// @notice Emitted when a Lombard strategy is deployed
    event LombardStrategyDeployed(
        address indexed strategy,
        address indexed vault,
        address lbtc,
        bool hasStaking
    );

    /**
     * @notice Deploy a Babylon BTC staking strategy
     * @param vault Vault address
     * @param babylonStaking Babylon staking contract
     * @param btcToken WBTC token address
     * @param lockPeriod Default lock period in seconds
     */
    function deployBabylon(
        address vault,
        address babylonStaking,
        address btcToken,
        uint64 lockPeriod
    ) external returns (address strategy) {
        strategy = address(new BabylonBTCStrategy(
            vault,
            babylonStaking,
            btcToken,
            lockPeriod
        ));

        emit BabylonStrategyDeployed(strategy, vault, babylonStaking, lockPeriod);
    }

    /**
     * @notice Deploy a Lombard LBTC liquid staking strategy
     * @param vault Vault address
     * @param lbtc LBTC token address
     * @param btcToken WBTC token address
     * @param lombardStaking Lombard staking contract (address(0) to skip)
     */
    function deployLombard(
        address vault,
        address lbtc,
        address btcToken,
        address lombardStaking
    ) external returns (address strategy) {
        strategy = address(new LombardLBTCStrategy(
            vault,
            lbtc,
            btcToken,
            lombardStaking
        ));

        emit LombardStrategyDeployed(strategy, vault, lbtc, lombardStaking != address(0));
    }
}
