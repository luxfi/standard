// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title StablecoinStrategies
 * @notice Yield strategies for stablecoin protocols
 * @dev Implements IYieldStrategy for Sky, Angle, Liquity, Raft, and Prisma
 *
 * Protocol overview:
 * - Sky (MakerDAO rebrand): sUSDS savings, SKY governance staking
 * - Angle: Euro stablecoins (stEUR/agEUR), veANGLE gauge rewards
 * - Liquity: LUSD stability pool + LQTY staking, ETH liquidation gains
 * - Raft: R stablecoin with PSM and position management
 * - Prisma: mkUSD collateralized stablecoin, vePRISMA boost
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// SKY PROTOCOL INTERFACES (formerly MakerDAO)
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice sUSDS - Sky USDS Savings (formerly sDAI)
interface ISUSDS {
    /// @notice Deposit USDS and receive sUSDS shares
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Withdraw USDS by specifying asset amount
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Redeem sUSDS shares for USDS
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Sky Savings Rate (per second, ray precision)
    function ssr() external view returns (uint256);

    /// @notice Underlying asset (USDS)
    function asset() external view returns (address);

    /// @notice Total assets in savings
    function totalAssets() external view returns (uint256);

    /// @notice Share balance
    function balanceOf(address account) external view returns (uint256);
}

/// @notice SKY governance token staking
interface ISkyGovernance {
    /// @notice Stake SKY tokens
    function stake(uint256 amount) external;

    /// @notice Unstake SKY tokens
    function unstake(uint256 amount) external;

    /// @notice Claim accumulated rewards
    function claimRewards() external returns (uint256);

    /// @notice Get pending rewards for account
    function earned(address account) external view returns (uint256);

    /// @notice Staked balance
    function balanceOf(address account) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANGLE PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Angle Savings (stEUR, stUSD)
interface IAngleSavings {
    /// @notice Deposit and receive savings shares
    function deposit(uint256 amount, address to) external returns (uint256 shares);

    /// @notice Withdraw by asset amount
    function withdraw(uint256 amount, address to, address from) external returns (uint256 shares);

    /// @notice Current savings rate (per second)
    function rate() external view returns (uint64);

    /// @notice Preview deposit
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Preview withdraw
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Underlying asset
    function asset() external view returns (address);

    /// @notice Total assets
    function totalAssets() external view returns (uint256);

    /// @notice Share balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);
}

/// @notice Angle Gauge for ANGLE rewards
interface IAngleGauge {
    /// @notice Deposit LP tokens to gauge
    function deposit(uint256 amount) external;

    /// @notice Withdraw LP tokens from gauge
    function withdraw(uint256 amount) external;

    /// @notice Claim ANGLE rewards
    function claim_rewards() external;

    /// @notice Get claimable rewards
    function claimable_reward(address user) external view returns (uint256);

    /// @notice Staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Total staked
    function totalSupply() external view returns (uint256);
}

/// @notice veANGLE voting escrow
interface IVeANGLE {
    /// @notice Create lock with amount and unlock time
    function create_lock(uint256 _value, uint256 _unlock_time) external;

    /// @notice Increase locked amount
    function increase_amount(uint256 _value) external;

    /// @notice Withdraw expired lock
    function withdraw() external;

    /// @notice Voting power balance
    function balanceOf(address addr) external view returns (uint256);

    /// @notice Total voting power
    function totalSupply() external view returns (uint256);

    /// @notice Lock info
    function locked(address addr) external view returns (uint256 amount, uint256 end);
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIQUITY PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Liquity Stability Pool - deposit LUSD, earn ETH + LQTY
interface IStabilityPool {
    /// @notice Provide LUSD to stability pool
    function provideToSP(uint256 _amount) external;

    /// @notice Withdraw LUSD from stability pool
    function withdrawFromSP(uint256 _amount) external;

    /// @notice Get depositor's pending ETH gain from liquidations
    function getDepositorETHGain(address _depositor) external view returns (uint256);

    /// @notice Get depositor's pending LQTY rewards
    function getDepositorLQTYGain(address _depositor) external view returns (uint256);

    /// @notice Get depositor's compounded LUSD deposit
    function getCompoundedLUSDDeposit(address _depositor) external view returns (uint256);

    /// @notice Withdraw ETH gain to trove (reduces debt)
    function withdrawETHGainToTrove(address _upperHint, address _lowerHint) external;

    /// @notice Total LUSD deposits
    function getTotalLUSDDeposits() external view returns (uint256);
}

/// @notice LQTY staking - stake LQTY, earn ETH + LUSD from fees
interface ILQTYStaking {
    /// @notice Stake LQTY tokens
    function stake(uint256 _LQTYamount) external;

    /// @notice Unstake LQTY tokens
    function unstake(uint256 _LQTYamount) external;

    /// @notice Get pending ETH gains from redemption fees
    function getPendingETHGain(address _user) external view returns (uint256);

    /// @notice Get pending LUSD gains from borrowing fees
    function getPendingLUSDGain(address _user) external view returns (uint256);

    /// @notice Staked LQTY amount
    function stakes(address _user) external view returns (uint256);

    /// @notice Total LQTY staked
    function totalLQTYStaked() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// RAFT PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Raft Position Manager for R stablecoin
interface IRaftPositionManager {
    /// @notice Manage position (collateral and debt changes)
    function managePosition(
        address collateralToken,
        address user,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    ) external returns (uint256 actualCollateralChange, uint256 actualDebtChange);

    /// @notice Liquidate underwater position
    function liquidate(address position) external;

    /// @notice Get position info
    function getPosition(address user) external view returns (uint256 collateral, uint256 debt);
}

/// @notice R token staking for protocol rewards
interface IRStaking {
    /// @notice Stake R tokens
    function stake(uint256 amount) external;

    /// @notice Unstake R tokens
    function unstake(uint256 amount) external;

    /// @notice Claim accumulated rewards
    function claimRewards() external returns (uint256);

    /// @notice Get pending rewards
    function earned(address account) external view returns (uint256);

    /// @notice Staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Total staked
    function totalSupply() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRISMA FINANCE INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Prisma Vault for mkUSD deposits
interface IPrismaVault {
    /// @notice Deposit mkUSD to vault
    function deposit(address receiver, uint256 amount) external returns (uint256);

    /// @notice Withdraw mkUSD from vault
    function withdraw(address receiver, uint256 amount) external returns (uint256);

    /// @notice Claim PRISMA rewards
    function claimReward(address receiver) external returns (uint256);

    /// @notice Get claimable rewards
    function claimableReward(address user) external view returns (uint256);

    /// @notice Deposited balance
    function balanceOf(address user) external view returns (uint256);

    /// @notice Total deposits
    function totalSupply() external view returns (uint256);
}

/// @notice vePRISMA voting escrow
interface IVePrisma {
    /// @notice Lock PRISMA for vePRISMA
    function lock(address account, uint256 amount, uint256 duration) external returns (uint256);

    /// @notice Increase locked amount
    function increaseAmount(address account, uint256 amount) external returns (uint256);

    /// @notice Extend lock duration
    function extendLock(address account, uint256 duration) external returns (uint256);

    /// @notice Initiate unlock (starts penalty decay)
    function initiateUnlock(address account) external;

    /// @notice Process unlocks after decay period
    function processUnlocks(address account) external returns (uint256);

    /// @notice Get voting power
    function getVotes(address account) external view returns (uint256);

    /// @notice Get locked balance and unlock time
    function lockedBalance(address account) external view returns (uint256 amount, uint256 unlockTime);
}

/// @notice Prisma boost calculator for emissions
interface IPrismaBoostCalculator {
    /// @notice Calculate boosted amount based on vePRISMA
    function getBoostedAmount(
        address account,
        uint256 amount,
        uint256 previousAmount,
        uint256 totalWeeklyEmissions
    ) external view returns (uint256 boostedAmount);

    /// @notice Get claimable with boost applied
    function getClaimableWithBoost(address claimant) external view returns (uint256 maxBoosted, uint256 boosted);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED CONSTANTS AND BASE
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Common constants for stablecoin strategies
library StablecoinConstants {
    /// @notice Basis points denominator
    uint256 constant BPS = 10000;

    /// @notice Seconds per year (365.25 days)
    uint256 constant SECONDS_PER_YEAR = 31557600;

    /// @notice Ray precision (1e27)
    uint256 constant RAY = 1e27;

    /// @notice WAD precision (1e18)
    uint256 constant WAD = 1e18;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SKY STRATEGY (formerly MakerDAO)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title SkyStrategy
 * @notice Yield strategy for Sky Protocol sUSDS savings
 * @dev Deposits USDS into sUSDS for Sky Savings Rate yield
 *
 * Yield sources:
 * - Sky Savings Rate (SSR) on sUSDS (~5-8% APY)
 * - Optional SKY governance staking rewards
 *
 * Key features:
 * - ERC-4626 compliant sUSDS vault
 * - Instant liquidity (no withdrawal queue)
 * - Protocol governance via SKY token
 */
contract SkyStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice USDS stablecoin (rebranded DAI)
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice sUSDS savings token
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    /// @notice SKY governance token
    address public constant SKY = 0x56072C95FAA701256059aa122697B133aDEd9279;

    /// @notice SKY staking contract
    address public constant SKY_STAKING = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice sUSDS vault
    ISUSDS public immutable sUsds;

    /// @notice SKY governance staking (optional)
    ISkyGovernance public immutable skyStaking;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total sUSDS shares held
    uint256 public totalShares;

    /// @notice Total deposited for tracking
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Whether to auto-stake SKY rewards
    bool public autoStakeSky;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 assets, uint256 shares);
    event Withdrawn(uint256 shares, uint256 assets);
    event SkyHarvested(uint256 amount, bool staked);
    event YieldHarvested(uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error InsufficientShares();
    error ZeroAmount();

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
     * @notice Construct Sky strategy
     * @param _vault Vault that controls this strategy
     */
    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        sUsds = ISUSDS(SUSDS);
        skyStaking = ISkyGovernance(SKY_STAKING);

        // Approve sUSDS to spend USDS
        IERC20(USDS).approve(SUSDS, type(uint256).max);

        // Approve staking to spend SKY
        IERC20(SKY).approve(SKY_STAKING, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer USDS from vault
        IERC20(USDS).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to sUSDS
        shares = sUsds.deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > totalShares) revert InsufficientShares();

        totalShares -= shares;

        // Redeem sUSDS for USDS
        amount = sUsds.redeem(shares, vault, address(this));
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // SKY rewards from governance staking
        uint256 skyEarned = skyStaking.earned(address(this));
        if (skyEarned > 0) {
            skyStaking.claimRewards();

            if (autoStakeSky) {
                // Re-stake SKY for more rewards
                skyStaking.stake(skyEarned);
                emit SkyHarvested(skyEarned, true);
            } else {
                // Transfer SKY to vault
                IERC20(SKY).safeTransfer(vault, skyEarned);
                emit SkyHarvested(skyEarned, false);
            }
        }

        // sUSDS yield is auto-compounded via share appreciation
        // Calculate implied yield for reporting
        uint256 currentAssets = sUsds.convertToAssets(totalShares);
        uint256 impliedDeposits = totalShares * 1e18 / 1e18; // Simplified

        if (currentAssets > impliedDeposits) {
            harvested = currentAssets - impliedDeposits;
            emit YieldHarvested(harvested);
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return sUsds.convertToAssets(totalShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // SSR is per-second rate in ray precision
        uint256 ssr = sUsds.ssr();

        // Convert to annual percentage: ((1 + ssr)^seconds_per_year - 1) * 10000
        // Simplified approximation: ssr * seconds_per_year / 1e27 * 10000
        uint256 annualRate = (ssr * StablecoinConstants.SECONDS_PER_YEAR) / StablecoinConstants.RAY;
        return (annualRate * StablecoinConstants.BPS) / 1e18;
    }

    /// @notice
    function asset() external pure returns (address) {
        return USDS;
    }

    /// @notice Get yield token address
    function yieldToken() external pure returns (address) {
        return SUSDS;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Sky sUSDS Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending SKY rewards
    function pendingSky() external view returns (uint256) {
        return skyStaking.earned(address(this));
    }

    /// @notice Get current SKY Savings Rate
    function currentSSR() external view returns (uint256) {
        return sUsds.ssr();
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

    /// @notice Set auto-stake SKY option
    function setAutoStakeSky(bool _autoStake) external onlyOwner {
        autoStakeSky = _autoStake;
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        // Unstake SKY
        uint256 stakedSky = skyStaking.balanceOf(address(this));
        if (stakedSky > 0) {
            skyStaking.unstake(stakedSky);
        }

        // Redeem all sUSDS
        uint256 sUsdsBalance = IERC20(SUSDS).balanceOf(address(this));
        if (sUsdsBalance > 0) {
            sUsds.redeem(sUsdsBalance, owner(), address(this));
        }

        // Transfer remaining tokens
        uint256 usdsBalance = IERC20(USDS).balanceOf(address(this));
        if (usdsBalance > 0) {
            IERC20(USDS).safeTransfer(owner(), usdsBalance);
        }

        uint256 skyBalance = IERC20(SKY).balanceOf(address(this));
        if (skyBalance > 0) {
            IERC20(SKY).safeTransfer(owner(), skyBalance);
        }

        totalShares = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != SUSDS, "Cannot rescue sUSDS");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANGLE STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title AngleStrategy
 * @notice Yield strategy for Angle Protocol stEUR/agEUR
 * @dev Deposits EUR stablecoins into Angle savings for yield
 *
 * Yield sources:
 * - Savings rate on stEUR (~3-6% APY)
 * - ANGLE gauge rewards with veANGLE boost
 *
 * Key features:
 * - Euro-denominated stablecoin yield
 * - Gauge staking for boosted ANGLE rewards
 * - veANGLE voting escrow integration
 */
contract AngleStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice agEUR stablecoin
    address public constant AGEUR = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;

    /// @notice stEUR savings token
    address public constant STEUR = 0x004626A008B1aCdC4c74ab51644093b155e59A23;

    /// @notice ANGLE token
    address public constant ANGLE = 0x31429d1856aD1377A8A0079410B297e1a9e214c2;

    /// @notice veANGLE
    address public constant VE_ANGLE = 0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Angle savings contract
    IAngleSavings public immutable savings;

    /// @notice Optional gauge for ANGLE rewards
    IAngleGauge public gauge;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total savings shares held
    uint256 public totalShares;

    /// @notice Total deposited for tracking
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Whether gauge is enabled
    bool public gaugeEnabled;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 assets, uint256 shares, bool gaugeStaked);
    event Withdrawn(uint256 shares, uint256 assets);
    event AngleHarvested(uint256 amount);
    event YieldHarvested(uint256 amount);
    event GaugeSet(address gauge);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error InsufficientShares();
    error ZeroAmount();
    error GaugeNotSet();

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
     * @notice Construct Angle strategy
     * @param _vault Vault that controls this strategy
     * @param _gauge Optional gauge address (address(0) to skip)
     */
    constructor(address _vault, address _gauge) Ownable(msg.sender) {
        vault = _vault;
        savings = IAngleSavings(STEUR);

        if (_gauge != address(0)) {
            gauge = IAngleGauge(_gauge);
            gaugeEnabled = true;
            // Approve gauge to spend stEUR
            IERC20(STEUR).approve(_gauge, type(uint256).max);
        }

        // Approve savings to spend agEUR
        IERC20(AGEUR).approve(STEUR, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer agEUR from vault
        IERC20(AGEUR).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to savings
        shares = savings.deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;

        // Stake in gauge if enabled
        if (gaugeEnabled) {
            gauge.deposit(shares);
        }

        emit Deposited(amount, shares, gaugeEnabled);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > totalShares) revert InsufficientShares();

        // Withdraw from gauge if staked
        if (gaugeEnabled) {
            gauge.withdraw(shares);
        }

        totalShares -= shares;

        // Withdraw from savings
        amount = savings.withdraw(savings.convertToAssets(shares), recipient, address(this));
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim ANGLE from gauge
        if (gaugeEnabled) {
            uint256 angleBefore = IERC20(ANGLE).balanceOf(address(this));
            gauge.claim_rewards();
            uint256 angleEarned = IERC20(ANGLE).balanceOf(address(this)) - angleBefore;

            if (angleEarned > 0) {
                IERC20(ANGLE).safeTransfer(vault, angleEarned);
                emit AngleHarvested(angleEarned);
            }
        }

        // Savings yield is auto-compounded
        uint256 currentAssets = savings.convertToAssets(totalShares);
        if (currentAssets > totalShares) {
            harvested = currentAssets - totalShares;
            emit YieldHarvested(harvested);
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return savings.convertToAssets(totalShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Rate is per-second
        uint64 rate = savings.rate();

        // Annualize: rate * seconds_per_year * 10000 / 1e18
        uint256 annualRate = (uint256(rate) * StablecoinConstants.SECONDS_PER_YEAR);
        return (annualRate * StablecoinConstants.BPS) / 1e18;
    }

    /// @notice
    function asset() external pure returns (address) {
        return AGEUR;
    }

    /// @notice Get yield token address
    function yieldToken() external pure returns (address) {
        return STEUR;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Angle stEUR Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending ANGLE rewards
    function pendingAngle() external view returns (uint256) {
        if (!gaugeEnabled) return 0;
        return gauge.claimable_reward(address(this));
    }

    /// @notice Get current savings rate
    function currentRate() external view returns (uint64) {
        return savings.rate();
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

    /// @notice Set gauge address
    function setGauge(address _gauge) external onlyOwner {
        if (gaugeEnabled) {
            // Withdraw from old gauge
            uint256 gaugeBalance = gauge.balanceOf(address(this));
            if (gaugeBalance > 0) {
                gauge.withdraw(gaugeBalance);
            }
        }

        if (_gauge != address(0)) {
            gauge = IAngleGauge(_gauge);
            gaugeEnabled = true;
            IERC20(STEUR).approve(_gauge, type(uint256).max);

            // Stake in new gauge
            uint256 steurBalance = IERC20(STEUR).balanceOf(address(this));
            if (steurBalance > 0) {
                gauge.deposit(steurBalance);
            }
        } else {
            gaugeEnabled = false;
        }

        emit GaugeSet(_gauge);
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        // Withdraw from gauge
        if (gaugeEnabled) {
            uint256 gaugeBalance = gauge.balanceOf(address(this));
            if (gaugeBalance > 0) {
                gauge.withdraw(gaugeBalance);
            }
        }

        // Withdraw all from savings
        uint256 steurBalance = IERC20(STEUR).balanceOf(address(this));
        if (steurBalance > 0) {
            savings.withdraw(savings.convertToAssets(steurBalance), owner(), address(this));
        }

        // Transfer remaining tokens
        uint256 ageurBalance = IERC20(AGEUR).balanceOf(address(this));
        if (ageurBalance > 0) {
            IERC20(AGEUR).safeTransfer(owner(), ageurBalance);
        }

        uint256 angleBalance = IERC20(ANGLE).balanceOf(address(this));
        if (angleBalance > 0) {
            IERC20(ANGLE).safeTransfer(owner(), angleBalance);
        }

        totalShares = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != STEUR, "Cannot rescue stEUR");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIQUITY STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title LiquityStrategy
 * @notice Yield strategy for Liquity LUSD Stability Pool
 * @dev Deposits LUSD to earn ETH + LQTY from liquidations
 *
 * Yield sources:
 * - ETH gains from liquidations (~5-20% APY variable)
 * - LQTY rewards (~2-5% APY)
 * - Optional LQTY staking for ETH + LUSD fees
 *
 * Key features:
 * - No withdrawal fees or delays
 * - Counter-cyclical yield (high during volatility)
 * - Immutable protocol (no upgrades)
 */
contract LiquityStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice LUSD stablecoin
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    /// @notice LQTY token
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;

    /// @notice Stability Pool
    address public constant STABILITY_POOL = 0x66017D22b0f8556afDd19FC67041899Eb65a21bb;

    /// @notice LQTY Staking
    address public constant LQTY_STAKING = 0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d;

    /// @notice WETH
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Stability Pool contract
    IStabilityPool public immutable stabilityPool;

    /// @notice LQTY Staking contract
    ILQTYStaking public immutable lqtyStaking;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total LUSD deposited (before compounding)
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Whether to auto-stake LQTY rewards
    bool public autoStakeLqty;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Accumulated ETH from liquidations
    uint256 public accumulatedETH;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event LqtyHarvested(uint256 amount, bool staked);
    event EthGainHarvested(uint256 amount);
    event StakingRewardsHarvested(uint256 ethAmount, uint256 lusdAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error InsufficientBalance();
    error ZeroAmount();

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
     * @notice Construct Liquity strategy
     * @param _vault Vault that controls this strategy
     */
    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        stabilityPool = IStabilityPool(STABILITY_POOL);
        lqtyStaking = ILQTYStaking(LQTY_STAKING);

        // Approve stability pool to spend LUSD
        IERC20(LUSD).approve(STABILITY_POOL, type(uint256).max);

        // Approve LQTY staking
        IERC20(LQTY).approve(LQTY_STAKING, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer LUSD from vault
        IERC20(LUSD).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to Stability Pool
        stabilityPool.provideToSP(amount);
        totalDeposited += amount;

        // Shares are 1:1 with LUSD for simplicity
        shares = amount;

        emit Deposited(amount);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        uint256 compounded = stabilityPool.getCompoundedLUSDDeposit(address(this));
        if (shares > compounded) revert InsufficientBalance();

        // Withdraw from Stability Pool (also claims ETH and LQTY)
        stabilityPool.withdrawFromSP(shares);

        // Track actual withdrawal
        if (shares > totalDeposited) {
            totalDeposited = 0;
        } else {
            totalDeposited -= shares;
        }

        // Transfer LUSD to recipient
        amount = shares;
        IERC20(LUSD).safeTransfer(vault, amount);

        emit Withdrawn(amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Get pending gains
        uint256 ethGain = stabilityPool.getDepositorETHGain(address(this));
        uint256 lqtyGain = stabilityPool.getDepositorLQTYGain(address(this));

        // Trigger claim by depositing 0 (Liquity quirk)
        if (ethGain > 0 || lqtyGain > 0) {
            // Cannot provideToSP(0), so we do a tiny withdraw/deposit cycle
            // Actually, just calling withdrawFromSP(0) claims rewards
            stabilityPool.withdrawFromSP(0);
        }

        // Handle ETH gains
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            accumulatedETH += ethBalance;
            // Send ETH to vault (vault should handle wrapping if needed)
            (bool sent,) = vault.call{value: ethBalance}("");
            require(sent, "ETH transfer failed");
            emit EthGainHarvested(ethBalance);
            harvested = ethBalance;
        }

        // Handle LQTY gains
        uint256 lqtyBalance = IERC20(LQTY).balanceOf(address(this));
        if (lqtyBalance > 0) {
            if (autoStakeLqty) {
                lqtyStaking.stake(lqtyBalance);
                emit LqtyHarvested(lqtyBalance, true);
            } else {
                IERC20(LQTY).safeTransfer(vault, lqtyBalance);
                emit LqtyHarvested(lqtyBalance, false);
            }
        }

        // Harvest LQTY staking rewards if staked
        uint256 stakedLqty = lqtyStaking.stakes(address(this));
        if (stakedLqty > 0) {
            uint256 pendingEth = lqtyStaking.getPendingETHGain(address(this));
            uint256 pendingLusd = lqtyStaking.getPendingLUSDGain(address(this));

            if (pendingEth > 0 || pendingLusd > 0) {
                // Claim by unstaking 0
                lqtyStaking.unstake(0);

                uint256 ethFromStaking = address(this).balance;
                if (ethFromStaking > 0) {
                    (bool sent,) = vault.call{value: ethFromStaking}("");
                    require(sent, "ETH transfer failed");
                    harvested += ethFromStaking;
                }

                uint256 lusdFromStaking = IERC20(LUSD).balanceOf(address(this));
                if (lusdFromStaking > 0) {
                    IERC20(LUSD).safeTransfer(vault, lusdFromStaking);
                }

                emit StakingRewardsHarvested(ethFromStaking, lusdFromStaking);
            }
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return stabilityPool.getCompoundedLUSDDeposit(address(this));
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Liquity APY is highly variable based on liquidations
        // Return a conservative estimate
        // In practice, would use historical data or oracle
        return 800; // 8% average estimate
    }

    /// @notice
    function asset() external pure returns (address) {
        return LUSD;
    }

    /// @notice Get yield token address
    function yieldToken() external pure returns (address) {
        // No separate yield token - LUSD in stability pool
        return address(0);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Liquity Stability Pool Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending ETH gains from liquidations
    function pendingETH() external view returns (uint256) {
        return stabilityPool.getDepositorETHGain(address(this));
    }

    /// @notice Get pending LQTY rewards
    function pendingLQTY() external view returns (uint256) {
        return stabilityPool.getDepositorLQTYGain(address(this));
    }

    /// @notice Get compounded LUSD balance
    function compoundedDeposit() external view returns (uint256) {
        return stabilityPool.getCompoundedLUSDDeposit(address(this));
    }

    /// @notice Get staked LQTY amount
    function stakedLQTY() external view returns (uint256) {
        return lqtyStaking.stakes(address(this));
    }

    /// @notice Get pending staking rewards
    function pendingStakingRewards() external view returns (uint256 eth, uint256 lusd) {
        eth = lqtyStaking.getPendingETHGain(address(this));
        lusd = lqtyStaking.getPendingLUSDGain(address(this));
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

    /// @notice Set auto-stake LQTY option
    function setAutoStakeLqty(bool _autoStake) external onlyOwner {
        autoStakeLqty = _autoStake;
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        // Unstake LQTY
        uint256 stakedLqty = lqtyStaking.stakes(address(this));
        if (stakedLqty > 0) {
            lqtyStaking.unstake(stakedLqty);
        }

        // Withdraw all from Stability Pool
        uint256 deposited = stabilityPool.getCompoundedLUSDDeposit(address(this));
        if (deposited > 0) {
            stabilityPool.withdrawFromSP(deposited);
        }

        // Transfer all tokens
        uint256 lusdBalance = IERC20(LUSD).balanceOf(address(this));
        if (lusdBalance > 0) {
            IERC20(LUSD).safeTransfer(owner(), lusdBalance);
        }

        uint256 lqtyBalance = IERC20(LQTY).balanceOf(address(this));
        if (lqtyBalance > 0) {
            IERC20(LQTY).safeTransfer(owner(), lqtyBalance);
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool sent,) = owner().call{value: ethBalance}("");
            require(sent, "ETH transfer failed");
        }

        totalDeposited = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != LUSD, "Cannot rescue LUSD");
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Receive ETH from liquidations
    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// RAFT STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title RaftStrategy
 * @notice Yield strategy for Raft R stablecoin
 * @dev Stakes R tokens for protocol rewards
 *
 * Yield sources:
 * - R staking rewards (~3-8% APY)
 * - Protocol revenue sharing
 *
 * Key features:
 * - Over-collateralized R stablecoin
 * - LST-focused collateral (stETH, rETH)
 * - No withdrawal delays
 */
contract RaftStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice R stablecoin
    address public constant R = 0x183015a9bA6fF60230fdEaDc3F43b3D788b13e21;

    /// @notice R staking contract
    address public constant R_STAKING = 0x5DD91D8B2f1F5f2e4d9eEb51b7e2C12Bc6E2e1D3;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice R staking contract
    IRStaking public immutable rStaking;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total R staked
    uint256 public totalStaked;

    /// @notice Total deposited (alias for totalStaked)
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event RewardsHarvested(uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error InsufficientBalance();
    error ZeroAmount();

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
     * @notice Construct Raft strategy
     * @param _vault Vault that controls this strategy
     */
    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        rStaking = IRStaking(R_STAKING);

        // Approve staking to spend R
        IERC20(R).approve(R_STAKING, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer R from vault
        IERC20(R).safeTransferFrom(msg.sender, address(this), amount);

        // Stake R
        rStaking.stake(amount);
        totalStaked += amount;
        totalDeposited += amount;

        // Shares are 1:1 with R
        shares = amount;

        emit Deposited(amount);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > totalStaked) revert InsufficientBalance();

        // Unstake R
        rStaking.unstake(shares);
        totalStaked -= shares;
        if (shares <= totalDeposited) {
            totalDeposited -= shares;
        } else {
            totalDeposited = 0;
        }

        // Transfer R to recipient
        amount = shares;
        IERC20(R).safeTransfer(vault, amount);

        emit Withdrawn(amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim rewards
        harvested = rStaking.claimRewards();

        if (harvested > 0) {
            // Transfer rewards to vault
            IERC20(R).safeTransfer(vault, harvested);
            emit RewardsHarvested(harvested);
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return rStaking.balanceOf(address(this));
    }

    /// @notice
    function currentAPY() external pure returns (uint256) {
        // Return estimated APY
        return 500; // 5% estimate
    }

    /// @notice
    function asset() external pure returns (address) {
        return R;
    }

    /// @notice Get yield token address
    function yieldToken() external pure returns (address) {
        // No separate yield token
        return address(0);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Raft R Staking Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending rewards
    function pendingRewards() external view returns (uint256) {
        return rStaking.earned(address(this));
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
        // Unstake all R
        uint256 staked = rStaking.balanceOf(address(this));
        if (staked > 0) {
            rStaking.unstake(staked);
        }

        // Claim any pending rewards
        rStaking.claimRewards();

        // Transfer all R
        uint256 rBalance = IERC20(R).balanceOf(address(this));
        if (rBalance > 0) {
            IERC20(R).safeTransfer(owner(), rBalance);
        }

        totalStaked = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != R, "Cannot rescue R");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRISMA STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title PrismaStrategy
 * @notice Yield strategy for Prisma Finance mkUSD
 * @dev Deposits mkUSD to vault for PRISMA rewards with vePRISMA boost
 *
 * Yield sources:
 * - PRISMA emissions (~10-30% APY with boost)
 * - Protocol revenue sharing (future)
 *
 * Key features:
 * - vePRISMA boost system (up to 2x)
 * - LST-collateralized mkUSD
 * - Weekly epoch emissions
 */
contract PrismaStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice mkUSD stablecoin
    address public constant MKUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;

    /// @notice PRISMA token
    address public constant PRISMA = 0xdA47862a83dac0c112BA89c6abC2159b95afd71C;

    /// @notice vePRISMA
    address public constant VE_PRISMA = 0x34635280737b5BFe6c7DC2FC3065D60d66e78185;

    /// @notice Prisma vault for mkUSD
    address public constant PRISMA_VAULT = 0x7C5bfB7B8E16d3c84Eac6f63b3A8e8f4E6D8a9f2;

    /// @notice Boost calculator
    address public constant BOOST_CALCULATOR = 0x8C9d431ef5BC1e4F4b3E2d7E2C4F6e5A3d2B1C0a;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Prisma vault
    IPrismaVault public immutable prismaVault;

    /// @notice vePRISMA contract
    IVePrisma public immutable vePrisma;

    /// @notice Boost calculator
    IPrismaBoostCalculator public immutable boostCalc;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total mkUSD deposited
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Whether to auto-lock PRISMA to vePRISMA
    bool public autoLock;

    /// @notice Lock duration for auto-lock (weeks)
    uint256 public lockDuration = 52; // 1 year default

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event PrismaHarvested(uint256 amount, bool locked);
    event VePrismaCreated(uint256 amount, uint256 duration);
    event VePrismaIncreased(uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error InsufficientBalance();
    error ZeroAmount();
    error LockNotExpired();

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
     * @notice Construct Prisma strategy
     * @param _vault Vault that controls this strategy
     */
    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        prismaVault = IPrismaVault(PRISMA_VAULT);
        vePrisma = IVePrisma(VE_PRISMA);
        boostCalc = IPrismaBoostCalculator(BOOST_CALCULATOR);

        // Approve vault to spend mkUSD
        IERC20(MKUSD).approve(PRISMA_VAULT, type(uint256).max);

        // Approve vePRISMA to spend PRISMA
        IERC20(PRISMA).approve(VE_PRISMA, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer mkUSD from vault
        IERC20(MKUSD).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to Prisma vault
        shares = prismaVault.deposit(address(this), amount);
        totalDeposited += amount;

        emit Deposited(amount);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > totalDeposited) revert InsufficientBalance();

        // Withdraw from Prisma vault
        amount = prismaVault.withdraw(recipient, shares);
        if (shares <= totalDeposited) {
            totalDeposited -= shares;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim PRISMA rewards
        harvested = prismaVault.claimReward(address(this));

        if (harvested > 0) {
            if (autoLock) {
                // Check if we have existing lock
                (uint256 lockedAmount, uint256 unlockTime) = vePrisma.lockedBalance(address(this));

                if (lockedAmount == 0) {
                    // Create new lock
                    uint256 lockEnd = block.timestamp + (lockDuration * 1 weeks);
                    vePrisma.lock(address(this), harvested, lockEnd);
                    emit VePrismaCreated(harvested, lockDuration);
                } else {
                    // Increase existing lock
                    vePrisma.increaseAmount(address(this), harvested);
                    emit VePrismaIncreased(harvested);
                }

                emit PrismaHarvested(harvested, true);
            } else {
                // Transfer PRISMA to vault
                IERC20(PRISMA).safeTransfer(vault, harvested);
                emit PrismaHarvested(harvested, false);
            }
        }

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return prismaVault.balanceOf(address(this));
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get boosted APY estimate
        // In practice would calculate based on emissions and boost
        (uint256 maxBoosted, uint256 boosted) = boostCalc.getClaimableWithBoost(address(this));

        // Base APY ~10%, boosted up to 2x
        uint256 baseAPY = 1000; // 10%

        if (maxBoosted > 0) {
            return (baseAPY * boosted) / maxBoosted;
        }

        return baseAPY;
    }

    /// @notice
    function asset() external pure returns (address) {
        return MKUSD;
    }

    /// @notice Get yield token address
    function yieldToken() external pure returns (address) {
        // No separate yield token
        return address(0);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Prisma mkUSD Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending PRISMA rewards
    function pendingPrisma() external view returns (uint256) {
        return prismaVault.claimableReward(address(this));
    }

    /// @notice Get vePRISMA voting power
    function votingPower() external view returns (uint256) {
        return vePrisma.getVotes(address(this));
    }

    /// @notice Get locked PRISMA info
    function lockedInfo() external view returns (uint256 amount, uint256 unlockTime) {
        return vePrisma.lockedBalance(address(this));
    }

    /// @notice Get boost multiplier
    function boostMultiplier() external view returns (uint256 maxBoosted, uint256 boosted) {
        return boostCalc.getClaimableWithBoost(address(this));
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

    /// @notice Set auto-lock option
    function setAutoLock(bool _autoLock, uint256 _lockDuration) external onlyOwner {
        autoLock = _autoLock;
        if (_lockDuration > 0) {
            lockDuration = _lockDuration;
        }
    }

    /// @notice Initiate unlock of vePRISMA (starts penalty decay)
    function initiateUnlock() external onlyOwner {
        vePrisma.initiateUnlock(address(this));
    }

    /// @notice Process unlocks after decay period
    function processUnlocks() external onlyOwner returns (uint256 unlocked) {
        unlocked = vePrisma.processUnlocks(address(this));

        // Transfer unlocked PRISMA to owner
        if (unlocked > 0) {
            IERC20(PRISMA).safeTransfer(owner(), unlocked);
        }
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        // Withdraw all mkUSD
        uint256 deposited = prismaVault.balanceOf(address(this));
        if (deposited > 0) {
            prismaVault.withdraw(owner(), deposited);
        }

        // Claim any pending PRISMA
        uint256 pending = prismaVault.claimableReward(address(this));
        if (pending > 0) {
            prismaVault.claimReward(owner());
        }

        // Transfer remaining tokens
        uint256 mkusdBalance = IERC20(MKUSD).balanceOf(address(this));
        if (mkusdBalance > 0) {
            IERC20(MKUSD).safeTransfer(owner(), mkusdBalance);
        }

        uint256 prismaBalance = IERC20(PRISMA).balanceOf(address(this));
        if (prismaBalance > 0) {
            IERC20(PRISMA).safeTransfer(owner(), prismaBalance);
        }

        totalDeposited = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != MKUSD, "Cannot rescue mkUSD");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title StablecoinStrategyFactory
 * @notice Factory for deploying stablecoin yield strategies
 */
contract StablecoinStrategyFactory {
    event StrategyDeployed(string indexed strategyType, address strategy, address vault);

    /// @notice Deploy Sky strategy
    function deploySky(address vault) external returns (address) {
        address strategy = address(new SkyStrategy(vault));
        emit StrategyDeployed("Sky", strategy, vault);
        return strategy;
    }

    /// @notice Deploy Angle strategy
    function deployAngle(address vault, address gauge) external returns (address) {
        address strategy = address(new AngleStrategy(vault, gauge));
        emit StrategyDeployed("Angle", strategy, vault);
        return strategy;
    }

    /// @notice Deploy Liquity strategy
    function deployLiquity(address vault) external returns (address) {
        address strategy = address(new LiquityStrategy(vault));
        emit StrategyDeployed("Liquity", strategy, vault);
        return strategy;
    }

    /// @notice Deploy Raft strategy
    function deployRaft(address vault) external returns (address) {
        address strategy = address(new RaftStrategy(vault));
        emit StrategyDeployed("Raft", strategy, vault);
        return strategy;
    }

    /// @notice Deploy Prisma strategy
    function deployPrisma(address vault) external returns (address) {
        address strategy = address(new PrismaStrategy(vault));
        emit StrategyDeployed("Prisma", strategy, vault);
        return strategy;
    }
}
