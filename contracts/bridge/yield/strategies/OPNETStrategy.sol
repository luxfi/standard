// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

/**
 * @title OPNETStrategy
 * @notice Yield strategy for BTC bridged from OP_NET (Bitcoin L1, AssemblyScript runtime)
 * @dev Holds bridged BTC and routes it to Babylon staking for yield.
 *
 * OP_NET is non-EVM so deposits arrive via MPC-signed proofs through the Teleporter.
 * This strategy wraps BabylonStaking for the BTC held on the Lux side.
 *
 * Flow:
 * 1. User locks BTC in OP_NET bridge contract (btc-runtime)
 * 2. MPC attests deposit, Teleporter mints LBTC on Lux
 * 3. Vault deposits LBTC into this strategy
 * 4. Strategy stakes into Babylon for yield
 * 5. Yield harvested and routed to LiquidYield
 */

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IYieldStrategy } from "../IYieldStrategy.sol";

/// @notice Babylon BTC staking interface (same as BabylonStrategy.sol)
interface IBabylonStaking {
    function stake(uint256 amount, uint64 lockTime) external returns (bytes32 stakeId);
    function unstake(bytes32 stakeId) external;
    function claimRewards(bytes32 stakeId) external returns (uint256);
    function getStake(bytes32 stakeId)
        external
        view
        returns (uint256 amount, uint64 lockTime, uint64 unlockTime, bool active);
    function pendingRewards(bytes32 stakeId) external view returns (uint256);
    function stakingAPY() external view returns (uint256);
}

contract OPNETStrategy is IYieldStrategy, Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    uint64 public constant MIN_LOCK = 30 days;
    uint64 public constant MAX_LOCK = 365 days;

    /// @notice OP_NET virtual chain ID (0x100000003)
    uint64 public constant OPNET_CHAIN_ID = 4294967299;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Babylon staking contract
    IBabylonStaking public immutable babylonStaking;

    /// @notice BTC token (LBTC bridged from OP_NET)
    IERC20 public immutable btcToken;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Default lock period for Babylon stakes
    uint64 public defaultLockPeriod;

    /// @notice Active Babylon stake IDs
    bytes32[] public activeStakes;
    mapping(bytes32 => uint256) public stakeIndex;

    /// @notice Total BTC staked in Babylon
    uint256 public totalStakedAmount;

    /// @notice Total deposited for accounting
    uint256 public override totalDeposited;

    /// @notice Total rewards harvested
    uint256 public totalHarvested;

    /// @notice Strategy active flag
    bool public active = true;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Staked(bytes32 indexed stakeId, uint256 amount, uint64 lockTime);
    event Unstaked(bytes32 indexed stakeId, uint256 amount);
    event RewardsHarvested(bytes32 indexed stakeId, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error ZeroAmount();
    error InsufficientBalance();
    error InvalidLockPeriod();
    error StakeLocked();

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
     * @param _vault Vault that controls this strategy
     * @param _babylonStaking Babylon staking contract
     * @param _btcToken LBTC token address (bridged from OP_NET)
     * @param _lockPeriod Default Babylon lock period
     */
    constructor(address _vault, address _babylonStaking, address _btcToken, uint64 _lockPeriod) Ownable(msg.sender) {
        if (_lockPeriod < MIN_LOCK || _lockPeriod > MAX_LOCK) revert InvalidLockPeriod();

        vault = _vault;
        babylonStaking = IBabylonStaking(_babylonStaking);
        btcToken = IERC20(_btcToken);
        defaultLockPeriod = _lockPeriod;

        btcToken.approve(_babylonStaking, type(uint256).max);
        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IYieldStrategy
    // ═══════════════════════════════════════════════════════════════════════

    function deposit(uint256 amount) external payable override onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        btcToken.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        bytes32 stakeId = babylonStaking.stake(amount, defaultLockPeriod);

        stakeIndex[stakeId] = activeStakes.length;
        activeStakes.push(stakeId);
        totalStakedAmount += amount;

        shares = amount;
        emit Staked(stakeId, amount, defaultLockPeriod);
    }

    function withdraw(uint256 shares) external override onlyVault returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (shares > totalStakedAmount) revert InsufficientBalance();

        uint256 remaining = shares;
        uint256 totalUnstaked; // Track full amount unstaked from Babylon
        uint256 i = 0;

        while (remaining > 0 && i < activeStakes.length) {
            bytes32 stakeId = activeStakes[i];
            (uint256 stakeAmount,, uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(stakeId);

            if (!stakeActive || block.timestamp < unlockTime) {
                i++;
                continue;
            }

            uint256 pending = babylonStaking.pendingRewards(stakeId);
            if (pending > 0) {
                babylonStaking.claimRewards(stakeId);
                emit RewardsHarvested(stakeId, pending);
            }

            babylonStaking.unstake(stakeId);

            // Always unstake the full Babylon position; return min(stakeAmount, remaining) to caller.
            // Any excess stays as idle balance and is picked up by the next deposit().
            uint256 withdrawn = stakeAmount > remaining ? remaining : stakeAmount;
            remaining -= withdrawn;
            assets += withdrawn;
            totalUnstaked += stakeAmount;

            emit Unstaked(stakeId, stakeAmount);
            _removeStake(stakeId);
        }

        if (assets == 0) revert StakeLocked();

        // Decrement by full unstaked amount so accounting stays correct.
        totalStakedAmount -= totalUnstaked;
        totalDeposited = assets <= totalDeposited ? totalDeposited - assets : 0;

        btcToken.safeTransfer(vault, assets);
    }

    function harvest() external override returns (uint256 harvested) {
        for (uint256 i = 0; i < activeStakes.length; i++) {
            uint256 pending = babylonStaking.pendingRewards(activeStakes[i]);
            if (pending > 0) {
                uint256 claimed = babylonStaking.claimRewards(activeStakes[i]);
                harvested += claimed;
                emit RewardsHarvested(activeStakes[i], claimed);
            }
        }

        totalHarvested += harvested;
        lastHarvest = block.timestamp;

        if (harvested > 0) {
            btcToken.safeTransfer(vault, harvested);
        }
    }

    function totalAssets() external view override returns (uint256) {
        return totalStakedAmount + _pendingRewardsTotal();
    }

    function currentAPY() external view override returns (uint256) {
        return babylonStaking.stakingAPY();
    }

    function asset() external view override returns (address) {
        return address(btcToken);
    }

    function isActive() external view override returns (bool) {
        return active;
    }

    function name() external pure override returns (string memory) {
        return "OP_NET BTC Babylon Staking Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════

    function activeStakeCount() external view returns (uint256) {
        return activeStakes.length;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setLockPeriod(uint64 _lockPeriod) external onlyOwner {
        if (_lockPeriod < MIN_LOCK || _lockPeriod > MAX_LOCK) revert InvalidLockPeriod();
        defaultLockPeriod = _lockPeriod;
    }

    /**
     * @notice HIGH-04: Retry unstaking a specific stake that failed during emergency withdraw.
     * @param stakeIdx Index in activeStakes array
     */
    function retryUnstake(uint256 stakeIdx) external onlyOwner {
        bytes32 stakeId = activeStakes[stakeIdx];
        (uint256 stakeAmount,, uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(stakeId);
        if (!stakeActive || block.timestamp < unlockTime) revert StakeLocked();

        uint256 pending = babylonStaking.pendingRewards(stakeId);
        if (pending > 0) babylonStaking.claimRewards(stakeId);
        babylonStaking.unstake(stakeId);

        totalStakedAmount = stakeAmount <= totalStakedAmount ? totalStakedAmount - stakeAmount : 0;
        emit Unstaked(stakeId, stakeAmount);
        _removeStake(stakeId);

        uint256 balance = btcToken.balanceOf(address(this));
        if (balance > 0) btcToken.safeTransfer(vault, balance);
    }

    /**
     * @notice HIGH-04: Emergency withdraw only removes stakes that CAN be unstaked.
     * Locked stakes remain in activeStakes for later retryUnstake().
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 unstaked;
        // Iterate backwards so _removeStake swap-and-pop is safe.
        for (uint256 i = activeStakes.length; i > 0; i--) {
            bytes32 stakeId = activeStakes[i - 1];
            (uint256 stakeAmount,, uint64 unlockTime, bool stakeActive) = babylonStaking.getStake(stakeId);

            if (stakeActive && block.timestamp >= unlockTime) {
                uint256 pending = babylonStaking.pendingRewards(stakeId);
                if (pending > 0) babylonStaking.claimRewards(stakeId);
                babylonStaking.unstake(stakeId);
                unstaked += stakeAmount;
                emit Unstaked(stakeId, stakeAmount);
                _removeStake(stakeId);
            }
            // HIGH-04: Locked stakes are NOT deleted — they stay for retryUnstake().
        }

        totalStakedAmount = unstaked <= totalStakedAmount ? totalStakedAmount - unstaked : 0;
        active = false;

        uint256 balance = btcToken.balanceOf(address(this));
        if (balance > 0) btcToken.safeTransfer(owner(), balance);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _pendingRewardsTotal() internal view returns (uint256 total) {
        for (uint256 i = 0; i < activeStakes.length; i++) {
            total += babylonStaking.pendingRewards(activeStakes[i]);
        }
    }

    function _removeStake(bytes32 stakeId) internal {
        uint256 idx = stakeIndex[stakeId];
        uint256 lastIdx = activeStakes.length - 1;

        if (idx != lastIdx) {
            bytes32 lastId = activeStakes[lastIdx];
            activeStakes[idx] = lastId;
            stakeIndex[lastId] = idx;
        }

        activeStakes.pop();
        delete stakeIndex[stakeId];
    }
}
