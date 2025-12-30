// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title SparkStrategy
 * @notice Yield strategies for Spark Protocol (MakerDAO's lending arm)
 * @dev Spark is an Aave V3 fork operated by MakerDAO with unique features:
 *      - Native sDAI integration (DSR yield)
 *      - SPK token rewards (planned)
 *      - spTokens for lending positions
 *      - SubDAO governance via SPK
 *
 * Supported Assets:
 *   - sDAI: Earns DSR (~5% APY) + Spark lending yield
 *   - spWETH: WETH lending on Spark
 *   - spUSDC: USDC lending on Spark
 *   - spWBTC: WBTC lending on Spark
 *
 * APY: 3-8% depending on asset and market conditions
 * Risk: Low (MakerDAO-operated, audited Aave V3 codebase)
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// SPARK PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Spark Pool interface (Aave V3 fork)
interface ISparkPool {
    /// @notice Supply asset to Spark lending pool
    /// @param asset The address of the underlying asset
    /// @param amount The amount to supply
    /// @param onBehalfOf The address that will receive the spTokens
    /// @param referralCode Referral code (0 if none)
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw asset from Spark lending pool
    /// @param asset The address of the underlying asset
    /// @param amount The amount to withdraw (type(uint256).max for all)
    /// @param to The address that will receive the underlying asset
    /// @return The final amount withdrawn
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /// @notice Get reserve data for an asset
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address spTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );

    /// @notice Get user account data
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

/// @notice Spark spToken interface (rebasing)
interface ISparkToken {
    function balanceOf(address user) external view returns (uint256);
    function scaledBalanceOf(address user) external view returns (uint256);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function POOL() external view returns (address);
}

/// @notice sDAI interface (ERC4626 vault wrapping DSR)
interface IsDAI {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function asset() external view returns (address);
}

/// @notice MakerDAO Pot interface (for DSR rate)
interface IPot {
    function dsr() external view returns (uint256); // DSR rate in ray (1e27)
    function chi() external view returns (uint256); // Accumulated rate
    function rho() external view returns (uint256); // Last drip timestamp
    function drip() external returns (uint256);     // Update chi
}

/// @notice SPK Rewards Controller (for future SPK token rewards)
interface ISparkRewardsController {
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external returns (uint256);

    function claimAllRewards(
        address[] calldata assets,
        address to
    ) external returns (address[] memory, uint256[] memory);

    function getUserRewards(
        address[] calldata assets,
        address user,
        address reward
    ) external view returns (uint256);

    function getAllUserRewards(
        address[] calldata assets,
        address user
    ) external view returns (address[] memory, uint256[] memory);
}

/// @notice WETH interface
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPARK LENDING STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title SparkLendingStrategy
/// @notice Supplies assets to Spark Protocol for spToken yield
/// @dev Works with any Spark-supported asset (WETH, USDC, WBTC, DAI, sDAI, etc.)
contract SparkLendingStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS (Ethereum Mainnet)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Spark Pool (Ethereum mainnet)
    ISparkPool public constant SPARK_POOL = ISparkPool(0xC13e21B648A5Ee794902342038FF3aDAB66BE987);

    /// @notice Spark Rewards Controller (for SPK rewards when available)
    ISparkRewardsController public constant REWARDS_CONTROLLER = 
        ISparkRewardsController(0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb);

    /// @notice SPK Token (governance token, rewards planned)
    address public constant SPK_TOKEN = 0x4Defa30195094963cfAC7285d8D6E6e523c7e02A;

    /// @notice WETH address (Ethereum mainnet)
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Referral code for Spark
    uint16 public constant REFERRAL_CODE = 0;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Underlying asset address
    address public immutable asset;

    /// @notice spToken address for this asset
    address public immutable spToken;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Whether underlying is native ETH (uses WETH internally)
    bool public immutable isNativeETH;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Track deposited amount for yield calculation
    uint256 public totalDeposited;

    /// @notice Accumulated SPK rewards
    uint256 public accumulatedRewards;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 amount, uint256 spTokensReceived);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 yieldAmount, uint256 spkRewards);
    event RewardsClaimed(uint256 spkAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error OnlyVault();
    error NotActive();
    error ETHAmountMismatch();
    error ETHTransferFailed();
    error InvalidAsset();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deploy SparkLendingStrategy
    /// @param _vault Vault address that controls deposits/withdrawals
    /// @param _asset Underlying asset (address(0) or WETH for native ETH)
    /// @param _isNativeETH True if strategy accepts native ETH
    constructor(
        address _vault,
        address _asset,
        bool _isNativeETH
    ) Ownable(msg.sender) {
        vault = _vault;
        isNativeETH = _isNativeETH;

        // For native ETH, use WETH as the asset in Spark
        asset = _isNativeETH ? WETH : _asset;

        // Get spToken address from Spark
        (,,,,,,,,address _spToken,,,,,,) = SPARK_POOL.getReserveData(asset);
        if (_spToken == address(0)) revert InvalidAsset();
        spToken = _spToken;

        // Approve Spark Pool to spend asset
        IERC20(asset).approve(address(SPARK_POOL), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external nonReentrant onlyVault returns (uint256 shares) {
        if (!active) revert NotActive();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Record spToken balance before
        uint256 spTokenBefore = ISparkToken(spToken).balanceOf(address(this));

        // Supply to Spark
        SPARK_POOL.supply(asset, amount, address(this), REFERRAL_CODE);

        // Calculate spTokens received
        uint256 spTokenAfter = ISparkToken(spToken).balanceOf(address(this));
        shares = spTokenAfter - spTokenBefore;
        totalDeposited += amount;

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external nonReentrant onlyVault returns (uint256 amount) {
        // Withdraw from Spark
        amount = SPARK_POOL.withdraw(asset, shares, address(this));

        IERC20(asset).safeTransfer(vault, amount);

        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(amount);
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        // spTokens are rebasing - yield is automatically added to balance
        uint256 currentBalance = ISparkToken(spToken).balanceOf(address(this));

        if (currentBalance > totalDeposited) {
            harvested = currentBalance - totalDeposited;
            // Update deposited to current balance (yield is now "harvested")
            totalDeposited = currentBalance;
        }

        // Claim SPK rewards if available
        uint256 spkRewards = _claimSPKRewards();

        emit Harvested(harvested, spkRewards);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return ISparkToken(spToken).balanceOf(address(this));
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get current liquidity rate from Spark (in RAY = 1e27)
        (,, uint128 currentLiquidityRate,,,,,,,,,,,,) = SPARK_POOL.getReserveData(asset);

        // Convert RAY to basis points: rate * 10000 / 1e27
        // currentLiquidityRate is annual rate in RAY
        return uint256(currentLiquidityRate) / 1e23; // Approximate conversion to bps
    }

    /// @notice Get the yield token address
    function yieldToken() external view returns (address) {
        return spToken;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external view returns (string memory) {
        if (isNativeETH) {
            return "Spark WETH Strategy";
        }
        return string(abi.encodePacked("Spark ", _getSymbol(asset), " Strategy"));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SPK REWARDS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Claim pending SPK rewards
    function claimRewards() external returns (uint256) {
        return _claimSPKRewards();
    }

    /// @notice Get pending SPK rewards
    function pendingSPKRewards() external view returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = spToken;
        
        try REWARDS_CONTROLLER.getUserRewards(assets, address(this), SPK_TOKEN) returns (uint256 rewards) {
            return rewards;
        } catch {
            return 0;
        }
    }

    function _claimSPKRewards() internal returns (uint256 claimed) {
        address[] memory assets = new address[](1);
        assets[0] = spToken;

        try REWARDS_CONTROLLER.claimAllRewards(assets, address(this)) returns (
            address[] memory,
            uint256[] memory amounts
        ) {
            if (amounts.length > 0) {
                claimed = amounts[0];
                accumulatedRewards += claimed;
                emit RewardsClaimed(claimed);
            }
        } catch {
            // Rewards not enabled yet - this is expected
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Rescue stuck tokens (not spTokens or underlying)
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != spToken && token != asset, "Cannot rescue strategy tokens");
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Emergency withdraw all from Spark
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = ISparkToken(spToken).balanceOf(address(this));
        if (balance > 0) {
            SPARK_POOL.withdraw(asset, type(uint256).max, owner());
        }
        active = false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _getSymbol(address token) internal view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory s) {
            return s;
        } catch {
            return "UNKNOWN";
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPARK sDAI STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title SparkSDAIStrategy
/// @notice Deposits DAI into sDAI for DSR yield, then supplies sDAI to Spark
/// @dev Double yield: DSR (~5%) + Spark lending rate (~1-3%)
///      sDAI is native to MakerDAO and earns the DAI Savings Rate
contract SparkSDAIStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS (Ethereum Mainnet)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice DAI stablecoin
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @notice sDAI (Savings DAI)
    IsDAI public constant SDAI = IsDAI(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

    /// @notice MakerDAO Pot (for DSR rate)
    IPot public constant POT = IPot(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);

    /// @notice Spark Pool
    ISparkPool public constant SPARK_POOL = ISparkPool(0xC13e21B648A5Ee794902342038FF3aDAB66BE987);

    /// @notice spSDAI token (sDAI supplied to Spark)
    address public immutable spSDAI;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    address public vault;
    uint256 public totalShares; // sDAI shares held
    uint256 public totalDeposited; // Track deposits for interface
    bool public active = true;

    /// @notice Whether to also supply sDAI to Spark for extra yield
    bool public supplyToSpark;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 daiAmount, uint256 sDAIShares);
    event Withdrawn(uint256 sDAIShares, uint256 daiAmount);
    event Harvested(uint256 yieldAmount);
    event SupplyToSparkToggled(bool enabled);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error OnlyVault();
    error NotActive();
    error InsufficientShares();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deploy SparkSDAIStrategy
    /// @param _vault Vault address
    /// @param _supplyToSpark Whether to supply sDAI to Spark for extra yield
    constructor(address _vault, bool _supplyToSpark) Ownable(msg.sender) {
        vault = _vault;
        supplyToSpark = _supplyToSpark;

        // Get spSDAI address if supplying to Spark
        (,,,,,,,,address _spSDAI,,,,,,) = SPARK_POOL.getReserveData(address(SDAI));
        spSDAI = _spSDAI;

        // Approve DAI for sDAI deposit
        IERC20(DAI).approve(address(SDAI), type(uint256).max);

        // Approve sDAI for Spark if enabled
        if (_supplyToSpark && _spSDAI != address(0)) {
            IERC20(address(SDAI)).approve(address(SPARK_POOL), type(uint256).max);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount, bytes calldata /* data */) external nonReentrant onlyVault returns (uint256 shares) {
        if (!active) revert NotActive();

        // Transfer DAI from vault
        IERC20(DAI).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit DAI to get sDAI
        shares = SDAI.deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;

        // Optionally supply sDAI to Spark for extra yield
        if (supplyToSpark && spSDAI != address(0)) {
            SPARK_POOL.supply(address(SDAI), shares, address(this), 0);
        }

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external nonReentrant onlyVault returns (uint256 amount) {
        if (shares > totalShares) revert InsufficientShares();

        // If supplied to Spark, withdraw first
        if (supplyToSpark && spSDAI != address(0)) {
            SPARK_POOL.withdraw(address(SDAI), shares, address(this));
        }

        // Redeem sDAI for DAI
        amount = SDAI.redeem(shares, vault, address(this));
        totalShares -= shares;
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        // sDAI yield is embedded in exchange rate
        // If using Spark, spToken yield is also embedded
        uint256 currentValue = _totalAssetsInternal();
        uint256 principal = SDAI.convertToAssets(totalShares);

        if (currentValue > principal) {
            harvested = currentValue - principal;
            emit Harvested(harvested);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return _totalAssetsInternal();
    }

    function _totalAssetsInternal() internal view returns (uint256) {
        if (supplyToSpark && spSDAI != address(0)) {
            // spSDAI balance -> sDAI value -> DAI value
            uint256 spBalance = ISparkToken(spSDAI).balanceOf(address(this));
            return SDAI.convertToAssets(spBalance);
        } else {
            // sDAI balance -> DAI value
            uint256 sDAIBalance = SDAI.balanceOf(address(this));
            return SDAI.convertToAssets(sDAIBalance);
        }
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate DSR APY from pot.dsr()
        // dsr is per-second rate in ray (1e27)
        // APY = (dsr^seconds_per_year) - 1
        uint256 dsr = POT.dsr();

        // Simplified approximation: (dsr - 1e27) * seconds_per_year / 1e27 * 10000
        // For 5% APY: dsr ≈ 1.000000001547125957863212448e27
        uint256 dsrAPY;
        if (dsr > 1e27) {
            // (dsr - 1e27) is per-second rate
            // Multiply by seconds per year (31536000)
            dsrAPY = ((dsr - 1e27) * 31536000 * 10000) / 1e27;
        }

        // Add Spark lending APY if enabled
        if (supplyToSpark && spSDAI != address(0)) {
            (,, uint128 sparkRate,,,,,,,,,,,,) = SPARK_POOL.getReserveData(address(SDAI));
            uint256 sparkAPY = uint256(sparkRate) / 1e23;
            return dsrAPY + sparkAPY;
        }

        return dsrAPY;
    }

    /// @notice
    function asset() external pure returns (address) {
        return DAI;
    }

    /// @notice Get yield token address
    function yieldToken() external view returns (address) {
        return supplyToSpark ? spSDAI : address(SDAI);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external view returns (string memory) {
        if (supplyToSpark) {
            return "Spark sDAI + Lending Strategy";
        }
        return "Spark sDAI (DSR) Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DSR UTILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get current DSR rate (per-second, in ray)
    function getDSR() external view returns (uint256) {
        return POT.dsr();
    }

    /// @notice Get accumulated DSR rate (chi)
    function getChi() external view returns (uint256) {
        return POT.chi();
    }

    /// @notice Trigger DSR accumulation update
    function dripDSR() external returns (uint256) {
        return POT.drip();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Toggle supplying sDAI to Spark
    function setSupplyToSpark(bool _supply) external onlyOwner {
        if (_supply && spSDAI == address(0)) {
            revert("sDAI not supported on Spark");
        }

        if (supplyToSpark && !_supply) {
            // Withdraw from Spark if disabling
            uint256 balance = ISparkToken(spSDAI).balanceOf(address(this));
            if (balance > 0) {
                SPARK_POOL.withdraw(address(SDAI), balance, address(this));
            }
        } else if (!supplyToSpark && _supply) {
            // Supply to Spark if enabling
            uint256 balance = SDAI.balanceOf(address(this));
            if (balance > 0) {
                IERC20(address(SDAI)).approve(address(SPARK_POOL), type(uint256).max);
                SPARK_POOL.supply(address(SDAI), balance, address(this), 0);
            }
        }

        supplyToSpark = _supply;
        emit SupplyToSparkToggled(_supply);
    }

    /// @notice Emergency withdraw
    function emergencyWithdraw() external onlyOwner {
        if (supplyToSpark && spSDAI != address(0)) {
            uint256 spBalance = ISparkToken(spSDAI).balanceOf(address(this));
            if (spBalance > 0) {
                SPARK_POOL.withdraw(address(SDAI), type(uint256).max, address(this));
            }
        }

        uint256 sDAIBalance = SDAI.balanceOf(address(this));
        if (sDAIBalance > 0) {
            SDAI.redeem(sDAIBalance, owner(), address(this));
        }

        active = false;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPARK STRATEGY FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title SparkStrategyFactory
/// @notice Factory for deploying Spark Protocol strategies
contract SparkStrategyFactory {
    event StrategyDeployed(address indexed strategy, string strategyType, address asset);

    /// @notice Deploy a SparkLendingStrategy
    /// @param vault Vault address
    /// @param asset Underlying asset (WETH, USDC, WBTC, etc.)
    /// @param isNativeETH Whether strategy accepts native ETH
    function deployLendingStrategy(
        address vault,
        address asset,
        bool isNativeETH
    ) external returns (address strategy) {
        strategy = address(new SparkLendingStrategy(vault, asset, isNativeETH));
        emit StrategyDeployed(strategy, "SparkLending", asset);
    }

    /// @notice Deploy a SparkSDAIStrategy
    /// @param vault Vault address
    /// @param supplyToSpark Whether to supply sDAI to Spark for extra yield
    function deploySDAIStrategy(
        address vault,
        bool supplyToSpark
    ) external returns (address strategy) {
        strategy = address(new SparkSDAIStrategy(vault, supplyToSpark));
        emit StrategyDeployed(strategy, "SparkSDAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER INTERFACE
// ═══════════════════════════════════════════════════════════════════════════════

interface IERC20Metadata {
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
}
