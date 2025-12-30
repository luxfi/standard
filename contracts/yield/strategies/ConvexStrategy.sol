// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title ConvexStrategy
 * @notice Yield strategies for Convex Finance - boosted Curve LP staking
 * @dev Stakes Curve LP tokens via Convex for boosted CRV + CVX rewards
 *
 * Convex Protocol Overview:
 * - Stakes Curve LP on behalf of users with max veCRV boost
 * - Earns CRV + CVX + extra rewards (protocol incentives)
 * - vlCVX locking for additional boost and governance
 *
 * Yield sources:
 * - Boosted CRV rewards (2.5x max boost from Convex's veCRV)
 * - CVX rewards (proportional to CRV earned)
 * - Extra rewards (protocol incentives, partner tokens)
 * - Curve LP trading fees (embedded in LP value)
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// =============================================================================
// CONVEX INTERFACES
// =============================================================================

/// @notice Convex Booster - main deposit contract
interface IConvexBooster {
    /// @notice Deposit LP tokens and optionally stake in rewards contract
    /// @param _pid Pool ID
    /// @param _amount Amount of LP tokens to deposit
    /// @param _stake Whether to stake in rewards contract
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    /// @notice Withdraw LP tokens from pool
    /// @param _pid Pool ID
    /// @param _amount Amount to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    /// @notice Get pool info
    function poolInfo(uint256 _pid) external view returns (
        address lptoken,
        address token,
        address gauge,
        address crvRewards,
        address stash,
        bool shutdown
    );

    /// @notice Total number of pools
    function poolLength() external view returns (uint256);

    /// @notice Earmark rewards for a pool (trigger reward distribution)
    function earmarkRewards(uint256 _pid) external returns (bool);
}

/// @notice Convex BaseRewardPool - staking and rewards
interface IConvexRewards {
    /// @notice Stake tokens
    function stake(uint256 _amount) external returns (bool);

    /// @notice Withdraw tokens with optional reward claim
    function withdraw(uint256 _amount, bool _claim) external returns (bool);

    /// @notice Withdraw and unwrap to LP tokens
    function withdrawAndUnwrap(uint256 _amount, bool _claim) external returns (bool);

    /// @notice Claim rewards
    function getReward() external returns (bool);

    /// @notice Claim rewards for account with extra rewards option
    function getReward(address _account, bool _claimExtras) external returns (bool);

    /// @notice Get staked balance
    function balanceOf(address _account) external view returns (uint256);

    /// @notice Get pending rewards
    function earned(address _account) external view returns (uint256);

    /// @notice Main reward token (CRV)
    function rewardToken() external view returns (address);

    /// @notice Number of extra reward contracts
    function extraRewardsLength() external view returns (uint256);

    /// @notice Get extra reward contract address
    function extraRewards(uint256 _index) external view returns (address);

    /// @notice When reward period ends
    function periodFinish() external view returns (uint256);

    /// @notice Reward rate per second
    function rewardRate() external view returns (uint256);
}

/// @notice CVX Locker for vote-locked CVX (vlCVX)
interface ICvxLocker {
    /// @notice Lock CVX tokens
    /// @param _account Account to lock for
    /// @param _amount Amount to lock
    /// @param _spendRatio Ratio of rewards to spend on extending lock
    function lock(address _account, uint256 _amount, uint256 _spendRatio) external;

    /// @notice Process expired locks
    /// @param _relock Whether to relock expired tokens
    function processExpiredLocks(bool _relock) external;

    /// @notice Claim rewards from locked CVX
    /// @param _account Account to claim for
    /// @param _stake Whether to stake rewards
    function getReward(address _account, bool _stake) external;

    /// @notice Get locked balance
    function lockedBalanceOf(address _user) external view returns (uint256);

    /// @notice Get claimable rewards
    function claimableRewards(address _account) external view returns (EarnedData[] memory);

    struct EarnedData {
        address token;
        uint256 amount;
    }
}

/// @notice Curve Pool interface (multiple overloads for different pool sizes)
interface ICurvePool {
    /// @notice Add liquidity to 2-coin pool
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external returns (uint256);

    /// @notice Add liquidity to 3-coin pool
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external returns (uint256);

    /// @notice Add liquidity to 4-coin pool
    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external returns (uint256);

    /// @notice Remove liquidity to all coins
    function remove_liquidity(uint256 _amount, uint256[2] memory min_amounts) external returns (uint256[2] memory);

    /// @notice Remove liquidity to single coin
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256);

    /// @notice Get virtual price of LP token
    function get_virtual_price() external view returns (uint256);

    /// @notice Calculate LP tokens for deposit
    function calc_token_amount(uint256[2] memory amounts, bool is_deposit) external view returns (uint256);
}

/// @notice CVX Token interface
interface ICvxToken is IERC20 {
    function reductionPerCliff() external view returns (uint256);
    function totalCliffs() external view returns (uint256);
    function maxSupply() external view returns (uint256);
}

// =============================================================================
// CONVEX CURVE STRATEGY
// =============================================================================

/**
 * @title ConvexCurveStrategy
 * @notice Stake Curve LP tokens via Convex for boosted CRV + CVX rewards
 * @dev Handles deposit, staking, reward claiming, and optional auto-compounding
 *
 * Architecture:
 * 1. User deposits Curve LP tokens
 * 2. Strategy deposits LP to Convex Booster with staking
 * 3. Earns boosted CRV + CVX + extra rewards
 * 4. Harvest sells rewards or compounds back to LP
 *
 * Reward Flow:
 * - CRV: Base reward from Curve gauge (boosted by Convex's veCRV)
 * - CVX: Minted proportionally to CRV earned
 * - Extras: Partner incentives (LDO, FXS, etc.)
 */
contract ConvexCurveStrategy is Ownable {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Convex Booster (Ethereum mainnet)
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice CRV token
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice CVX token
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @notice vlCVX locker
    address public constant CVX_LOCKER = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Seconds per year for APY calculation
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Convex pool ID
    uint256 public immutable poolId;

    /// @notice Curve LP token (underlying)
    address public immutable lpToken;

    /// @notice Convex reward pool contract
    IConvexRewards public immutable rewardPool;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Whether auto-compounding is enabled
    bool public autoCompound;

    /// @notice Whether vlCVX locking is enabled
    bool public lockCvx;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Total LP tokens deposited
    uint256 public totalDeposited;

    /// @notice Accumulated CRV harvested
    uint256 public accumulatedCRV;

    /// @notice Accumulated CVX harvested
    uint256 public accumulatedCVX;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Mapping of extra reward tokens harvested
    mapping(address => uint256) public accumulatedExtraRewards;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed user, uint256 lpAmount);
    event Withdrawn(address indexed user, uint256 lpAmount);
    event RewardsClaimed(uint256 crvAmount, uint256 cvxAmount, address[] extraTokens, uint256[] extraAmounts);
    event Compounded(uint256 crvUsed, uint256 cvxUsed, uint256 lpMinted);
    event CvxLocked(uint256 amount);
    event AutoCompoundToggled(bool enabled);
    event CvxLockToggled(bool enabled);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error NotActive();
    error OnlyVault();
    error ZeroAmount();
    error PoolShutdown();
    error InvalidPool();
    error InsufficientBalance();
    error CompoundFailed();

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
     * @notice Construct Convex Curve strategy
     * @param _vault Vault that controls this strategy
     * @param _poolId Convex pool ID
     * @param _autoCompound Whether to auto-compound rewards
     * @param _lockCvx Whether to lock CVX for vlCVX boost
     */
    constructor(
        address _vault,
        uint256 _poolId,
        bool _autoCompound,
        bool _lockCvx
    ) Ownable(msg.sender) {
        vault = _vault;
        poolId = _poolId;
        autoCompound = _autoCompound;
        lockCvx = _lockCvx;

        // Get pool info from Booster
        (
            address _lpToken,
            ,
            ,
            address _crvRewards,
            ,
            bool shutdown
        ) = IConvexBooster(CONVEX_BOOSTER).poolInfo(_poolId);

        if (shutdown) revert PoolShutdown();
        if (_lpToken == address(0)) revert InvalidPool();

        lpToken = _lpToken;
        rewardPool = IConvexRewards(_crvRewards);

        // Approve Booster to spend LP tokens
        IERC20(_lpToken).approve(CONVEX_BOOSTER, type(uint256).max);

        // Approve CVX locker if locking enabled
        if (_lockCvx) {
            IERC20(CVX).approve(CVX_LOCKER, type(uint256).max);
        }

        lastHarvest = block.timestamp;
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Check pool not shutdown
        (,,,, , bool shutdown) = IConvexBooster(CONVEX_BOOSTER).poolInfo(poolId);
        if (shutdown) revert PoolShutdown();

        // Transfer LP tokens from vault
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to Convex with staking
        IConvexBooster(CONVEX_BOOSTER).deposit(poolId, amount, true);

        totalDeposited += amount;
        shares = amount; // 1:1 for LP tokens

        emit Deposited(msg.sender, amount);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares > totalDeposited) revert InsufficientBalance();

        // Withdraw and unwrap from Convex
        rewardPool.withdrawAndUnwrap(shares, true); // true = claim rewards

        totalDeposited -= shares;
        amount = shares;

        // Transfer LP tokens back to recipient
        IERC20(lpToken).safeTransfer(vault, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim all rewards
        rewardPool.getReward(address(this), true);

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));

        // Collect extra rewards
        uint256 extraCount = rewardPool.extraRewardsLength();
        address[] memory extraTokens = new address[](extraCount);
        uint256[] memory extraAmounts = new uint256[](extraCount);

        for (uint256 i = 0; i < extraCount; i++) {
            address extraRewardPool = rewardPool.extraRewards(i);
            address extraToken = IConvexRewards(extraRewardPool).rewardToken();
            uint256 extraBalance = IERC20(extraToken).balanceOf(address(this));

            extraTokens[i] = extraToken;
            extraAmounts[i] = extraBalance;
            accumulatedExtraRewards[extraToken] += extraBalance;
        }

        accumulatedCRV += crvBalance;
        accumulatedCVX += cvxBalance;

        emit RewardsClaimed(crvBalance, cvxBalance, extraTokens, extraAmounts);

        if (autoCompound && (crvBalance > 0 || cvxBalance > 0)) {
            harvested = _compound(crvBalance, cvxBalance);
        } else {
            // Transfer rewards to vault
            if (crvBalance > 0) {
                IERC20(CRV).safeTransfer(vault, crvBalance);
            }
            if (cvxBalance > 0) {
                if (lockCvx) {
                    _lockCvxRewards(cvxBalance);
                } else {
                    IERC20(CVX).safeTransfer(vault, cvxBalance);
                }
            }

            // Transfer extra rewards
            for (uint256 i = 0; i < extraCount; i++) {
                if (extraAmounts[i] > 0) {
                    IERC20(extraTokens[i]).safeTransfer(vault, extraAmounts[i]);
                }
            }

            // Return CRV value as harvested amount (simplified)
            harvested = crvBalance;
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalDeposited;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate APY from reward rate
        // APY = (rewardRate * SECONDS_PER_YEAR * rewardPrice) / (totalStaked * lpPrice)
        // Simplified: assume 15% base APY for Curve/Convex pools
        uint256 baseAPY = 1500; // 15% default

        // Add boost from vlCVX if locked
        if (lockCvx) {
            uint256 lockedBalance = ICvxLocker(CVX_LOCKER).lockedBalanceOf(address(this));
            if (lockedBalance > 0) {
                baseAPY += 300; // +3% for vlCVX
            }
        }

        return baseAPY;
    }

    /// @notice
    function asset() external view returns (address) {
        return lpToken;
    }

    /// @notice
    function isActive() external view returns (bool) {
        (,,,, , bool shutdown) = IConvexBooster(CONVEX_BOOSTER).poolInfo(poolId);
        return active && !shutdown;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Convex Curve Strategy";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get pending CRV rewards
    function pendingCRV() external view returns (uint256) {
        return rewardPool.earned(address(this));
    }

    /// @notice Get pending CVX rewards (estimated from CRV)
    function pendingCVX() external view returns (uint256) {
        uint256 pendingCrv = rewardPool.earned(address(this));
        return _estimateCvxReward(pendingCrv);
    }

    /// @notice Get all pending extra rewards
    function pendingExtraRewards() external view returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 extraCount = rewardPool.extraRewardsLength();
        tokens = new address[](extraCount);
        amounts = new uint256[](extraCount);

        for (uint256 i = 0; i < extraCount; i++) {
            address extraRewardPool = rewardPool.extraRewards(i);
            tokens[i] = IConvexRewards(extraRewardPool).rewardToken();
            amounts[i] = IConvexRewards(extraRewardPool).earned(address(this));
        }
    }

    /// @notice Get staked balance in reward pool
    function stakedBalance() external view returns (uint256) {
        return rewardPool.balanceOf(address(this));
    }

    /// @notice Get locked CVX balance
    function lockedCvx() external view returns (uint256) {
        return ICvxLocker(CVX_LOCKER).lockedBalanceOf(address(this));
    }

    /// @notice Get pool info
    function getPoolInfo() external view returns (
        address _lpToken,
        address token,
        address gauge,
        address crvRewards,
        address stash,
        bool shutdown
    ) {
        return IConvexBooster(CONVEX_BOOSTER).poolInfo(poolId);
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /// @notice Estimate CVX reward from CRV (based on CVX emission schedule)
    function _estimateCvxReward(uint256 crvAmount) internal view returns (uint256) {
        ICvxToken cvxToken = ICvxToken(CVX);
        uint256 supply = cvxToken.totalSupply();
        uint256 maxSupply = cvxToken.maxSupply();
        uint256 totalCliffs = cvxToken.totalCliffs();
        uint256 reductionPerCliff = cvxToken.reductionPerCliff();

        if (supply >= maxSupply) return 0;

        uint256 cliff = supply / reductionPerCliff;
        if (cliff >= totalCliffs) return 0;

        uint256 reduction = totalCliffs - cliff;
        return (crvAmount * reduction) / totalCliffs;
    }

    /// @notice Compound rewards back into LP (placeholder - needs DEX integration)
    function _compound(uint256 crvAmount, uint256 cvxAmount) internal returns (uint256 lpMinted) {
        // In production, this would:
        // 1. Sell CRV + CVX for underlying tokens via DEX
        // 2. Add liquidity to Curve pool
        // 3. Deposit LP to Convex

        // For now, just transfer to vault for manual handling
        if (crvAmount > 0) {
            IERC20(CRV).safeTransfer(vault, crvAmount);
        }
        if (cvxAmount > 0) {
            if (lockCvx) {
                _lockCvxRewards(cvxAmount);
            } else {
                IERC20(CVX).safeTransfer(vault, cvxAmount);
            }
        }

        emit Compounded(crvAmount, cvxAmount, lpMinted);
        return 0; // No LP minted in simplified version
    }

    /// @notice Lock CVX for vlCVX
    function _lockCvxRewards(uint256 amount) internal {
        if (amount == 0) return;
        ICvxLocker(CVX_LOCKER).lock(address(this), amount, 0);
        emit CvxLocked(amount);
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Toggle auto-compounding
    function setAutoCompound(bool _enabled) external onlyOwner {
        autoCompound = _enabled;
        emit AutoCompoundToggled(_enabled);
    }

    /// @notice Toggle CVX locking
    function setCvxLock(bool _enabled) external onlyOwner {
        lockCvx = _enabled;
        if (_enabled) {
            IERC20(CVX).approve(CVX_LOCKER, type(uint256).max);
        }
        emit CvxLockToggled(_enabled);
    }

    /// @notice Set strategy active status
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /// @notice Set vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Earmark rewards (trigger Convex reward distribution)
    function earmarkRewards() external {
        IConvexBooster(CONVEX_BOOSTER).earmarkRewards(poolId);
    }

    /// @notice Process expired vlCVX locks
    function processExpiredLocks(bool relock) external onlyOwner {
        ICvxLocker(CVX_LOCKER).processExpiredLocks(relock);
    }

    /// @notice Claim vlCVX rewards
    function claimLockerRewards() external {
        ICvxLocker(CVX_LOCKER).getReward(address(this), false);

        // Transfer claimed rewards to vault
        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance > 0) {
            IERC20(CRV).safeTransfer(vault, crvBalance);
        }
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        // Withdraw from Convex
        uint256 staked = rewardPool.balanceOf(address(this));
        if (staked > 0) {
            rewardPool.withdrawAndUnwrap(staked, true);
        }

        // Transfer all tokens to owner
        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
        if (lpBalance > 0) {
            IERC20(lpToken).safeTransfer(owner(), lpBalance);
        }

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance > 0) {
            IERC20(CRV).safeTransfer(owner(), crvBalance);
        }

        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));
        if (cvxBalance > 0) {
            IERC20(CVX).safeTransfer(owner(), cvxBalance);
        }

        totalDeposited = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != lpToken, "Cannot rescue LP tokens");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// CONVEX FRAX STRATEGY
// =============================================================================

/**
 * @title ConvexFraxStrategy
 * @notice Stake Curve/Frax LP via Convex for FXS + CRV + CVX rewards
 * @dev Handles Frax-specific pools with FXS boosting
 *
 * Frax pools are hybrid Curve pools with additional FXS incentives.
 * Convex integrates with Frax to provide boosted FXS + CRV + CVX rewards.
 *
 * Example pools:
 * - FRAX/USDC (fraxBP)
 * - FRAX/FPI
 * - sFRAX/FRAX
 */
contract ConvexFraxStrategy is Ownable {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Convex Booster (Ethereum mainnet)
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice CRV token
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice CVX token
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @notice FXS token
    address public constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;

    /// @notice vlCVX locker
    address public constant CVX_LOCKER = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Convex pool ID for Frax pool
    uint256 public immutable poolId;

    /// @notice Curve/Frax LP token
    address public immutable lpToken;

    /// @notice Convex reward pool
    IConvexRewards public immutable rewardPool;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Whether auto-compounding is enabled
    bool public autoCompound;

    /// @notice Whether vlCVX locking is enabled
    bool public lockCvx;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Total LP tokens deposited
    uint256 public totalDeposited;

    /// @notice Accumulated rewards
    uint256 public accumulatedCRV;
    uint256 public accumulatedCVX;
    uint256 public accumulatedFXS;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed user, uint256 lpAmount);
    event Withdrawn(address indexed user, uint256 lpAmount);
    event RewardsClaimed(uint256 crvAmount, uint256 cvxAmount, uint256 fxsAmount);
    event Compounded(uint256 crvUsed, uint256 cvxUsed, uint256 fxsUsed, uint256 lpMinted);
    event CvxLocked(uint256 amount);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error NotActive();
    error OnlyVault();
    error ZeroAmount();
    error PoolShutdown();
    error InvalidPool();
    error InsufficientBalance();

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert NotActive();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    /**
     * @notice Construct Convex Frax strategy
     * @param _vault Vault that controls this strategy
     * @param _poolId Convex pool ID for Frax pool
     * @param _autoCompound Whether to auto-compound rewards
     * @param _lockCvx Whether to lock CVX for vlCVX
     */
    constructor(
        address _vault,
        uint256 _poolId,
        bool _autoCompound,
        bool _lockCvx
    ) Ownable(msg.sender) {
        vault = _vault;
        poolId = _poolId;
        autoCompound = _autoCompound;
        lockCvx = _lockCvx;

        // Get pool info
        (
            address _lpToken,
            ,
            ,
            address _crvRewards,
            ,
            bool shutdown
        ) = IConvexBooster(CONVEX_BOOSTER).poolInfo(_poolId);

        if (shutdown) revert PoolShutdown();
        if (_lpToken == address(0)) revert InvalidPool();

        lpToken = _lpToken;
        rewardPool = IConvexRewards(_crvRewards);

        // Approve Booster
        IERC20(_lpToken).approve(CONVEX_BOOSTER, type(uint256).max);

        // Approve CVX locker
        if (_lockCvx) {
            IERC20(CVX).approve(CVX_LOCKER, type(uint256).max);
        }

        lastHarvest = block.timestamp;
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        (,,,, , bool shutdown) = IConvexBooster(CONVEX_BOOSTER).poolInfo(poolId);
        if (shutdown) revert PoolShutdown();

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        IConvexBooster(CONVEX_BOOSTER).deposit(poolId, amount, true);

        totalDeposited += amount;
        shares = amount;

        emit Deposited(msg.sender, amount);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares > totalDeposited) revert InsufficientBalance();

        rewardPool.withdrawAndUnwrap(shares, true);

        totalDeposited -= shares;
        amount = shares;

        IERC20(lpToken).safeTransfer(vault, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        rewardPool.getReward(address(this), true);

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));
        uint256 fxsBalance = IERC20(FXS).balanceOf(address(this));

        accumulatedCRV += crvBalance;
        accumulatedCVX += cvxBalance;
        accumulatedFXS += fxsBalance;

        emit RewardsClaimed(crvBalance, cvxBalance, fxsBalance);

        if (autoCompound && (crvBalance > 0 || cvxBalance > 0 || fxsBalance > 0)) {
            harvested = _compound(crvBalance, cvxBalance, fxsBalance);
        } else {
            // Transfer rewards to vault
            if (crvBalance > 0) {
                IERC20(CRV).safeTransfer(vault, crvBalance);
            }
            if (cvxBalance > 0) {
                if (lockCvx) {
                    ICvxLocker(CVX_LOCKER).lock(address(this), cvxBalance, 0);
                    emit CvxLocked(cvxBalance);
                } else {
                    IERC20(CVX).safeTransfer(vault, cvxBalance);
                }
            }
            if (fxsBalance > 0) {
                IERC20(FXS).safeTransfer(vault, fxsBalance);
            }

            harvested = crvBalance + fxsBalance; // CRV + FXS value
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return totalDeposited;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Frax pools typically have higher APY due to FXS incentives
        uint256 baseAPY = 2000; // 20% default for Frax pools

        if (lockCvx) {
            uint256 lockedBalance = ICvxLocker(CVX_LOCKER).lockedBalanceOf(address(this));
            if (lockedBalance > 0) {
                baseAPY += 400; // +4% for vlCVX
            }
        }

        return baseAPY;
    }

    /// @notice
    function asset() external view returns (address) {
        return lpToken;
    }

    /// @notice
    function isActive() external view returns (bool) {
        (,,,, , bool shutdown) = IConvexBooster(CONVEX_BOOSTER).poolInfo(poolId);
        return active && !shutdown;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Convex Frax Strategy";
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get pending rewards
    function pendingRewards() external view returns (uint256 crv, uint256 fxs) {
        crv = rewardPool.earned(address(this));

        // Check extra rewards for FXS
        uint256 extraCount = rewardPool.extraRewardsLength();
        for (uint256 i = 0; i < extraCount; i++) {
            address extraPool = rewardPool.extraRewards(i);
            if (IConvexRewards(extraPool).rewardToken() == FXS) {
                fxs = IConvexRewards(extraPool).earned(address(this));
                break;
            }
        }
    }

    /// @notice Get staked balance
    function stakedBalance() external view returns (uint256) {
        return rewardPool.balanceOf(address(this));
    }

    // =========================================================================
    // INTERNAL
    // =========================================================================

    function _compound(uint256 crvAmount, uint256 cvxAmount, uint256 fxsAmount) internal returns (uint256) {
        // Simplified: transfer to vault
        if (crvAmount > 0) IERC20(CRV).safeTransfer(vault, crvAmount);
        if (cvxAmount > 0) {
            if (lockCvx) {
                ICvxLocker(CVX_LOCKER).lock(address(this), cvxAmount, 0);
            } else {
                IERC20(CVX).safeTransfer(vault, cvxAmount);
            }
        }
        if (fxsAmount > 0) IERC20(FXS).safeTransfer(vault, fxsAmount);

        emit Compounded(crvAmount, cvxAmount, fxsAmount, 0);
        return 0;
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    function setAutoCompound(bool _enabled) external onlyOwner {
        autoCompound = _enabled;
    }

    function setCvxLock(bool _enabled) external onlyOwner {
        lockCvx = _enabled;
        if (_enabled) {
            IERC20(CVX).approve(CVX_LOCKER, type(uint256).max);
        }
    }

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 staked = rewardPool.balanceOf(address(this));
        if (staked > 0) {
            rewardPool.withdrawAndUnwrap(staked, true);
        }

        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
        if (lpBalance > 0) IERC20(lpToken).safeTransfer(owner(), lpBalance);

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance > 0) IERC20(CRV).safeTransfer(owner(), crvBalance);

        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));
        if (cvxBalance > 0) IERC20(CVX).safeTransfer(owner(), cvxBalance);

        uint256 fxsBalance = IERC20(FXS).balanceOf(address(this));
        if (fxsBalance > 0) IERC20(FXS).safeTransfer(owner(), fxsBalance);

        totalDeposited = 0;
        active = false;
    }

    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != lpToken, "Cannot rescue LP");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// CONCRETE IMPLEMENTATIONS
// =============================================================================

/**
 * @title ConvexTriCryptoStrategy
 * @notice Convex strategy for Curve TriCrypto (USDT/WBTC/WETH)
 * @dev Pool ID 38 on mainnet
 */
contract ConvexTriCryptoStrategy is ConvexCurveStrategy {
    uint256 public constant TRICRYPTO_PID = 38;

    constructor(address _vault)
        ConvexCurveStrategy(_vault, TRICRYPTO_PID, false, true)
    {}
}

/**
 * @title Convex3PoolStrategy
 * @notice Convex strategy for Curve 3Pool (DAI/USDC/USDT)
 * @dev Pool ID 9 on mainnet
 */
contract Convex3PoolStrategy is ConvexCurveStrategy {
    uint256 public constant THREE_POOL_PID = 9;

    constructor(address _vault)
        ConvexCurveStrategy(_vault, THREE_POOL_PID, false, true)
    {}
}

/**
 * @title ConvexStETHStrategy
 * @notice Convex strategy for Curve stETH/ETH pool
 * @dev Pool ID 25 on mainnet
 */
contract ConvexStETHStrategy is ConvexCurveStrategy {
    uint256 public constant STETH_PID = 25;

    constructor(address _vault)
        ConvexCurveStrategy(_vault, STETH_PID, false, true)
    {}
}

/**
 * @title ConvexFraxBPStrategy
 * @notice Convex strategy for Frax Base Pool (FRAX/USDC)
 * @dev Pool ID 100 on mainnet
 */
contract ConvexFraxBPStrategy is ConvexFraxStrategy {
    uint256 public constant FRAXBP_PID = 100;

    constructor(address _vault)
        ConvexFraxStrategy(_vault, FRAXBP_PID, false, true)
    {}
}

// =============================================================================
// FACTORY
// =============================================================================

/**
 * @title ConvexStrategyFactory
 * @notice Factory for deploying Convex strategies
 */
contract ConvexStrategyFactory {
    event StrategyDeployed(address indexed strategy, uint256 indexed poolId, string strategyType);

    /// @notice Deploy a generic Convex Curve strategy
    function deployCurve(
        address vault,
        uint256 poolId,
        bool autoCompound,
        bool lockCvx
    ) external returns (address strategy) {
        strategy = address(new ConvexCurveStrategy(vault, poolId, autoCompound, lockCvx));
        emit StrategyDeployed(strategy, poolId, "ConvexCurve");
    }

    /// @notice Deploy a Convex Frax strategy
    function deployFrax(
        address vault,
        uint256 poolId,
        bool autoCompound,
        bool lockCvx
    ) external returns (address strategy) {
        strategy = address(new ConvexFraxStrategy(vault, poolId, autoCompound, lockCvx));
        emit StrategyDeployed(strategy, poolId, "ConvexFrax");
    }

    /// @notice Deploy TriCrypto strategy
    function deployTriCrypto(address vault) external returns (address) {
        return address(new ConvexTriCryptoStrategy(vault));
    }

    /// @notice Deploy 3Pool strategy
    function deploy3Pool(address vault) external returns (address) {
        return address(new Convex3PoolStrategy(vault));
    }

    /// @notice Deploy stETH strategy
    function deployStETH(address vault) external returns (address) {
        return address(new ConvexStETHStrategy(vault));
    }

    /// @notice Deploy FraxBP strategy
    function deployFraxBP(address vault) external returns (address) {
        return address(new ConvexFraxBPStrategy(vault));
    }
}
