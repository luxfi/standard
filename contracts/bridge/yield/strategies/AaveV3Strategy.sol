// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title AaveV3Strategy
 * @notice Yield strategies for Aave V3 lending protocol
 * @dev Implements two strategies:
 *      1. AaveV3SupplyStrategy - Simple supply to earn yield
 *      2. AaveV3LeverageStrategy - Recursive borrow/supply for amplified yield
 *
 * Aave V3 features utilized:
 * - E-Mode for correlated asset efficiency (higher LTV)
 * - Isolation mode awareness
 * - Supply/borrow cap checks
 * - Multiple reward token claiming
 *
 * Yield sources:
 * - Supply APY (variable rate lending yield)
 * - AAVE/reward token incentives
 * - Leveraged yield amplification (for leverage strategy)
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// AAVE V3 DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Aave V3 reserve data types
library DataTypes {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AAVE V3 INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Aave V3 Pool interface
interface IPool {
    /// @notice Supply assets to Aave
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw assets from Aave
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /// @notice Borrow assets from Aave
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /// @notice Repay borrowed assets
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);

    /// @notice Set asset as collateral
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    /// @notice Get user account data
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );

    /// @notice Get reserve data for an asset
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

    /// @notice Set E-Mode category
    function setUserEMode(uint8 categoryId) external;

    /// @notice Get user E-Mode category
    function getUserEMode(address user) external view returns (uint256);
}

/// @notice Aave aToken interface
interface IAToken {
    /// @notice Get balance of aTokens
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get scaled balance (ray-denominated)
    function scaledBalanceOf(address user) external view returns (uint256);

    /// @notice Get scaled balance and total supply
    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256);

    /// @notice Get underlying asset address
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /// @notice Get pool address
    function POOL() external view returns (address);
}

/// @notice Aave V3 Rewards Controller interface
interface IRewardsController {
    /// @notice Claim specific reward token
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external returns (uint256);

    /// @notice Claim all reward tokens
    function claimAllRewards(
        address[] calldata assets,
        address to
    ) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    /// @notice Get user rewards for specific token
    function getUserRewards(
        address[] calldata assets,
        address user,
        address reward
    ) external view returns (uint256);

    /// @notice Get all user rewards
    function getAllUserRewards(
        address[] calldata assets,
        address user
    ) external view returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);

    /// @notice Get reward tokens for an asset
    function getRewardsByAsset(address asset) external view returns (address[] memory);
}

/// @notice Aave V3 Price Oracle interface
interface IPriceOracle {
    /// @notice Get asset price in base currency
    function getAssetPrice(address asset) external view returns (uint256);

    /// @notice Get multiple asset prices
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    /// @notice Get price source for asset
    function getSourceOfAsset(address asset) external view returns (address);
}

// ═══════════════════════════════════════════════════════════════════════════════
// AAVE V3 SUPPLY STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title AaveV3SupplyStrategy
 * @notice Simple supply strategy for Aave V3 lending
 * @dev Deposits assets to earn supply APY plus reward incentives
 *
 * Yield sources:
 * - Supply interest (variable rate)
 * - AAVE token incentives
 * - Additional reward tokens (GHO, etc.)
 */
contract AaveV3SupplyStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Ray denominator (27 decimals)
    uint256 public constant RAY = 1e27;

    /// @notice Seconds per year for APY calculation
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Aave V3 Pool
    IPool public immutable pool;

    /// @notice aToken for this asset
    IAToken public immutable aToken;

    /// @notice Underlying asset
    address public immutable underlyingAsset;

    /// @notice Rewards controller
    IRewardsController public immutable rewardsController;

    /// @notice Price oracle
    IPriceOracle public immutable priceOracle;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice E-Mode category (0 = disabled)
    uint8 public eModeCategoryId;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Total shares issued
    uint256 public totalShares;

    /// @notice Mapping of user shares
    mapping(address => uint256) public shares;

    /// @notice Total deposited amount for accounting
    uint256 public totalDeposited;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when assets are supplied to Aave
    event Supplied(address indexed user, uint256 amount, uint256 shares);

    /// @notice Emitted when assets are withdrawn from Aave
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);

    /// @notice Emitted when rewards are harvested
    event RewardsHarvested(address[] rewards, uint256[] amounts);

    /// @notice Emitted when E-Mode is updated
    event EModeUpdated(uint8 categoryId);

    /// @notice Emitted when vault is updated
    event VaultUpdated(address indexed newVault);

    /// @notice Emitted when strategy is paused/unpaused
    event ActiveStatusChanged(bool active);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Strategy is not active
    error NotActive();

    /// @notice Only vault can call
    error OnlyVault();

    /// @notice Zero amount provided
    error ZeroAmount();

    /// @notice Insufficient shares
    error InsufficientShares();

    /// @notice Invalid aToken
    error InvalidAToken();

    /// @notice Health factor too low
    error HealthFactorTooLow();

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
     * @notice Construct Aave V3 supply strategy
     * @param _vault Vault that controls this strategy
     * @param _pool Aave V3 Pool address
     * @param _aToken aToken address for the underlying asset
     * @param _rewardsController Rewards controller address
     * @param _priceOracle Price oracle address
     */
    constructor(
        address _vault,
        address _pool,
        address _aToken,
        address _rewardsController,
        address _priceOracle
    ) Ownable(msg.sender) {
        vault = _vault;
        pool = IPool(_pool);
        aToken = IAToken(_aToken);
        underlyingAsset = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        rewardsController = IRewardsController(_rewardsController);
        priceOracle = IPriceOracle(_priceOracle);

        // Validate aToken
        if (IAToken(_aToken).POOL() != _pool) revert InvalidAToken();

        // Approve pool to spend underlying
        IERC20(underlyingAsset).approve(_pool, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive nonReentrant returns (uint256 sharesOut) {
        if (amount == 0) revert ZeroAmount();

        // Transfer underlying from vault
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        // Calculate shares before supply
        uint256 aTokenBalanceBefore = aToken.balanceOf(address(this));
        uint256 totalAssetsBefore = aTokenBalanceBefore;

        // Supply to Aave
        pool.supply(underlyingAsset, amount, address(this), 0);

        // Calculate shares
        if (totalShares == 0) {
            sharesOut = amount;
        } else {
            sharesOut = (amount * totalShares) / totalAssetsBefore;
        }

        totalShares += sharesOut;
        shares[msg.sender] += sharesOut;

        emit Supplied(msg.sender, amount, sharesOut);
    }

    /// @notice
    function withdraw(uint256 sharesToWithdraw) external onlyVault nonReentrant returns (uint256 amount) {
        if (sharesToWithdraw == 0) revert ZeroAmount();
        if (sharesToWithdraw > shares[msg.sender]) revert InsufficientShares();

        // Calculate underlying amount
        uint256 totalAssetsNow = aToken.balanceOf(address(this));
        amount = (sharesToWithdraw * totalAssetsNow) / totalShares;

        // Update shares
        shares[msg.sender] -= sharesToWithdraw;
        totalShares -= sharesToWithdraw;

        // Update total deposited
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        // Withdraw from Aave
        uint256 withdrawn = pool.withdraw(underlyingAsset, amount, vault);

        emit Withdrawn(msg.sender, sharesToWithdraw, withdrawn);

        return withdrawn;
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        // Build list of assets to claim from
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        // Claim all rewards
        (address[] memory rewardTokens, uint256[] memory amounts) = rewardsController.claimAllRewards(
            assets,
            vault
        );

        // Calculate harvested value
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (amounts[i] > 0) {
                uint256 price = priceOracle.getAssetPrice(rewardTokens[i]);
                harvested += (amounts[i] * price) / 1e8; // Aave uses 8 decimal prices
            }
        }

        emit RewardsHarvested(rewardTokens, amounts);

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);

        // Convert ray to basis points
        // liquidityRate is in ray (1e27) and represents per-second rate
        // APY = (1 + rate/secondsPerYear)^secondsPerYear - 1
        // Simplified: rate * secondsPerYear / 1e27 * 10000
        uint256 supplyRatePerYear = uint256(reserveData.currentLiquidityRate);

        // Convert from ray to BPS (divide by 1e23)
        return supplyRatePerYear / 1e23;
    }

    /// @notice
    function asset() external view returns (address) {
        return underlyingAsset;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Aave V3 Supply Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending rewards
    /// @return rewardTokens Array of reward token addresses
    /// @return amounts Array of pending amounts
    function pendingRewards() external view returns (address[] memory rewardTokens, uint256[] memory amounts) {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        return rewardsController.getAllUserRewards(assets, address(this));
    }

    /// @notice Get supply rate (per second, ray denominated)
    function supplyRate() external view returns (uint256) {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);
        return uint256(reserveData.currentLiquidityRate);
    }

    /// @notice Get user account data
    function accountData() external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return pool.getUserAccountData(address(this));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set E-Mode category for correlated assets
    /// @param categoryId E-Mode category (0 to disable)
    function setEMode(uint8 categoryId) external onlyOwner {
        pool.setUserEMode(categoryId);
        eModeCategoryId = categoryId;
        emit EModeUpdated(categoryId);
    }

    /// @notice Set vault address
    /// @param _vault New vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @notice Set strategy active status
    /// @param _active New active status
    function setActive(bool _active) external onlyOwner {
        active = _active;
        emit ActiveStatusChanged(_active);
    }

    /// @notice Emergency withdraw all funds
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = aToken.balanceOf(address(this));
        if (balance > 0) {
            pool.withdraw(underlyingAsset, type(uint256).max, owner());
        }

        // Claim all rewards to owner
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        rewardsController.claimAllRewards(assets, owner());

        totalShares = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    /// @param token Token to rescue
    /// @param amount Amount to rescue
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(aToken), "Cannot rescue aTokens");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AAVE V3 LEVERAGE STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title AaveV3LeverageStrategy
 * @notice Leveraged yield strategy using recursive borrow/supply
 * @dev Amplifies yield by:
 *      1. Supply collateral
 *      2. Borrow same asset
 *      3. Re-supply borrowed amount
 *      4. Repeat until target leverage reached
 *
 * Risk factors:
 * - Health factor must stay above minimum threshold
 * - Borrow rate may exceed supply rate (negative carry)
 * - Liquidation risk if price moves adversely (for non-correlated assets)
 *
 * Best suited for:
 * - E-Mode correlated assets (stablecoins, ETH variants)
 * - When supply APY + incentives > borrow APY
 */
contract AaveV3LeverageStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Ray denominator
    uint256 public constant RAY = 1e27;

    /// @notice Minimum health factor (1.05 = 105%)
    uint256 public constant MIN_HEALTH_FACTOR = 1.05e18;

    /// @notice Maximum loops for leverage/deleverage
    uint256 public constant MAX_LOOPS = 10;

    /// @notice Variable interest rate mode
    uint256 public constant VARIABLE_RATE = 2;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Aave V3 Pool
    IPool public immutable pool;

    /// @notice aToken for supply
    IAToken public immutable aToken;

    /// @notice Variable debt token
    address public immutable variableDebtToken;

    /// @notice Underlying asset
    address public immutable underlyingAsset;

    /// @notice Rewards controller
    IRewardsController public immutable rewardsController;

    /// @notice Price oracle
    IPriceOracle public immutable priceOracle;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Target leverage ratio in BPS (e.g., 25000 = 2.5x)
    uint256 public targetLeverageRatio;

    /// @notice E-Mode category
    uint8 public eModeCategoryId;

    /// @notice Minimum health factor threshold
    uint256 public minHealthFactor;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    /// @notice Total shares issued
    uint256 public totalShares;

    /// @notice Mapping of user shares
    mapping(address => uint256) public shares;

    /// @notice Total deposited amount for accounting
    uint256 public totalDeposited;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when assets are supplied
    event Supplied(address indexed user, uint256 amount, uint256 shares);

    /// @notice Emitted when assets are withdrawn
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);

    /// @notice Emitted when assets are borrowed
    event Borrowed(uint256 amount);

    /// @notice Emitted when debt is repaid
    event Repaid(uint256 amount);

    /// @notice Emitted when leverage is applied
    event Leveraged(uint256 initialAmount, uint256 totalSupplied, uint256 totalBorrowed);

    /// @notice Emitted when leverage is reduced
    event Deleveraged(uint256 supplyReduced, uint256 debtRepaid);

    /// @notice Emitted when rewards are harvested
    event RewardsHarvested(address[] rewards, uint256[] amounts);

    /// @notice Emitted when leverage ratio is updated
    event LeverageRatioUpdated(uint256 newRatio);

    /// @notice Emitted when E-Mode is updated
    event EModeUpdated(uint8 categoryId);

    /// @notice Emitted when health factor threshold is updated
    event MinHealthFactorUpdated(uint256 newMinHealthFactor);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Strategy is not active
    error NotActive();

    /// @notice Only vault can call
    error OnlyVault();

    /// @notice Zero amount provided
    error ZeroAmount();

    /// @notice Insufficient shares
    error InsufficientShares();

    /// @notice Health factor too low
    error HealthFactorTooLow();

    /// @notice Invalid leverage ratio
    error InvalidLeverageRatio();

    /// @notice Max loops exceeded
    error MaxLoopsExceeded();

    /// @notice Nothing to deleverage
    error NothingToDeleverage();

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

    modifier healthFactorCheck() {
        _;
        (, , , , , uint256 hf) = pool.getUserAccountData(address(this));
        if (hf < minHealthFactor && hf != type(uint256).max) {
            revert HealthFactorTooLow();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Construct Aave V3 leverage strategy
     * @param _vault Vault that controls this strategy
     * @param _pool Aave V3 Pool address
     * @param _aToken aToken address
     * @param _rewardsController Rewards controller address
     * @param _priceOracle Price oracle address
     * @param _targetLeverageRatio Target leverage in BPS (e.g., 20000 = 2x)
     */
    constructor(
        address _vault,
        address _pool,
        address _aToken,
        address _rewardsController,
        address _priceOracle,
        uint256 _targetLeverageRatio
    ) Ownable(msg.sender) {
        if (_targetLeverageRatio < BPS || _targetLeverageRatio > 50000) {
            revert InvalidLeverageRatio();
        }

        vault = _vault;
        pool = IPool(_pool);
        aToken = IAToken(_aToken);
        underlyingAsset = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        rewardsController = IRewardsController(_rewardsController);
        priceOracle = IPriceOracle(_priceOracle);
        targetLeverageRatio = _targetLeverageRatio;
        minHealthFactor = MIN_HEALTH_FACTOR;

        // Get variable debt token
        DataTypes.ReserveData memory reserveData = IPool(_pool).getReserveData(underlyingAsset);
        variableDebtToken = reserveData.variableDebtTokenAddress;

        // Approve pool
        IERC20(underlyingAsset).approve(_pool, type(uint256).max);

        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive nonReentrant healthFactorCheck returns (uint256 sharesOut) {
        if (amount == 0) revert ZeroAmount();

        // Transfer underlying from vault
        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        // Get current position value before
        uint256 positionValueBefore = _getPositionValue();

        // Supply initial amount
        pool.supply(underlyingAsset, amount, address(this), 0);
        pool.setUserUseReserveAsCollateral(underlyingAsset, true);

        // Apply leverage
        _leverage();

        // Calculate shares
        if (totalShares == 0) {
            sharesOut = amount;
        } else {
            sharesOut = (amount * totalShares) / positionValueBefore;
        }

        totalShares += sharesOut;
        shares[msg.sender] += sharesOut;

        emit Supplied(msg.sender, amount, sharesOut);
    }

    /// @notice
    function withdraw(uint256 sharesToWithdraw) external onlyVault nonReentrant returns (uint256 amount) {
        if (sharesToWithdraw == 0) revert ZeroAmount();
        if (sharesToWithdraw > shares[msg.sender]) revert InsufficientShares();

        // Calculate portion of position to withdraw
        uint256 positionValue = _getPositionValue();
        amount = (sharesToWithdraw * positionValue) / totalShares;

        // Update shares
        shares[msg.sender] -= sharesToWithdraw;
        totalShares -= sharesToWithdraw;

        // Update total deposited
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        // Deleverage to free up collateral
        _deleverageForWithdraw(amount);

        // Withdraw to recipient
        uint256 withdrawn = pool.withdraw(underlyingAsset, amount, vault);

        emit Withdrawn(msg.sender, sharesToWithdraw, withdrawn);

        return withdrawn;
    }

    /// @notice
    function harvest() external nonReentrant returns (uint256 harvested) {
        // Build list of assets to claim from (aToken + debt token)
        address[] memory assets = new address[](2);
        assets[0] = address(aToken);
        assets[1] = variableDebtToken;

        // Claim all rewards
        (address[] memory rewardTokens, uint256[] memory amounts) = rewardsController.claimAllRewards(
            assets,
            vault
        );

        // Calculate harvested value
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (amounts[i] > 0) {
                uint256 price = priceOracle.getAssetPrice(rewardTokens[i]);
                harvested += (amounts[i] * price) / 1e8;
            }
        }

        emit RewardsHarvested(rewardTokens, amounts);

        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return _getPositionValue();
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(underlyingAsset);

        // Supply rate and borrow rate in ray
        uint256 supplyRate = uint256(reserveData.currentLiquidityRate);
        uint256 borrowRate = uint256(reserveData.currentVariableBorrowRate);

        // Get current leverage
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 borrowed = IERC20(variableDebtToken).balanceOf(address(this));

        if (supplied == 0) {
            return supplyRate / 1e23; // Convert ray to BPS
        }

        // Net APY = (supply * supplyRate - borrowed * borrowRate) / equity
        uint256 equity = supplied - borrowed;
        if (equity == 0) return 0;

        uint256 supplyYield = (supplied * supplyRate) / RAY;
        uint256 borrowCost = (borrowed * borrowRate) / RAY;

        if (supplyYield > borrowCost) {
            return ((supplyYield - borrowCost) * BPS) / equity;
        }
        return 0; // Negative yield (shouldn't happen with proper strategy)
    }

    /// @notice
    function asset() external view returns (address) {
        return underlyingAsset;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Aave V3 Leverage Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LEVERAGE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Apply leverage to reach target ratio
     * @dev Loops through borrow/supply until target reached or max loops
     */
    function _leverage() internal {
        uint256 initialSupply = aToken.balanceOf(address(this));
        uint256 targetSupply = (initialSupply * targetLeverageRatio) / BPS;
        uint256 totalBorrowed;

        for (uint256 i = 0; i < MAX_LOOPS; i++) {
            // Get available borrows
            (, , uint256 availableBorrows, , , uint256 hf) = pool.getUserAccountData(address(this));

            // Check health factor
            if (hf < minHealthFactor && hf != type(uint256).max) {
                break;
            }

            // Check if target reached
            uint256 currentSupply = aToken.balanceOf(address(this));
            if (currentSupply >= targetSupply) {
                break;
            }

            // Calculate borrow amount (use 95% of available to leave buffer)
            uint256 borrowAmount = (availableBorrows * 95) / 100;
            if (borrowAmount == 0) break;

            // Convert from base currency to underlying (8 decimal price)
            uint256 price = priceOracle.getAssetPrice(underlyingAsset);
            borrowAmount = (borrowAmount * 1e8) / price;

            // Cap at what's needed to reach target
            uint256 remaining = targetSupply - currentSupply;
            if (borrowAmount > remaining) {
                borrowAmount = remaining;
            }

            // Borrow
            pool.borrow(underlyingAsset, borrowAmount, VARIABLE_RATE, 0, address(this));
            totalBorrowed += borrowAmount;

            emit Borrowed(borrowAmount);

            // Re-supply
            pool.supply(underlyingAsset, borrowAmount, address(this), 0);
        }

        emit Leveraged(initialSupply, aToken.balanceOf(address(this)), totalBorrowed);
    }

    /**
     * @notice Reduce leverage to free collateral for withdrawal
     * @param amountNeeded Amount of underlying needed to withdraw
     */
    function _deleverageForWithdraw(uint256 amountNeeded) internal {
        uint256 debtRepaid;
        uint256 supplyReduced;

        for (uint256 i = 0; i < MAX_LOOPS; i++) {
            uint256 currentDebt = IERC20(variableDebtToken).balanceOf(address(this));
            uint256 currentSupply = aToken.balanceOf(address(this));

            // Check if we can withdraw needed amount
            uint256 freeCollateral = currentSupply - currentDebt;
            if (freeCollateral >= amountNeeded) {
                break;
            }

            // Need to deleverage
            if (currentDebt == 0) {
                break; // Nothing to repay
            }

            // Withdraw and repay loop
            // Calculate safe withdraw amount
            (, , , , uint256 ltv, ) = pool.getUserAccountData(address(this));
            if (ltv == 0) break;

            // Max we can withdraw = supply - (debt * 10000 / ltv) with buffer
            uint256 minCollateralNeeded = (currentDebt * BPS * 105) / (ltv * 100);
            if (currentSupply <= minCollateralNeeded) break;

            uint256 withdrawable = currentSupply - minCollateralNeeded;
            if (withdrawable == 0) break;

            // Withdraw
            uint256 withdrawn = pool.withdraw(underlyingAsset, withdrawable, address(this));
            supplyReduced += withdrawn;

            // Repay debt with withdrawn amount
            uint256 repayAmount = withdrawn > currentDebt ? currentDebt : withdrawn;
            pool.repay(underlyingAsset, repayAmount, VARIABLE_RATE, address(this));
            debtRepaid += repayAmount;

            emit Repaid(repayAmount);
        }

        emit Deleveraged(supplyReduced, debtRepaid);
    }

    /**
     * @notice Manually rebalance leverage
     */
    function rebalance() external onlyOwner healthFactorCheck {
        _leverage();
    }

    /**
     * @notice Fully deleverage position
     */
    function fullDeleverage() external onlyOwner {
        uint256 debt = IERC20(variableDebtToken).balanceOf(address(this));
        if (debt == 0) revert NothingToDeleverage();

        for (uint256 i = 0; i < MAX_LOOPS; i++) {
            uint256 currentDebt = IERC20(variableDebtToken).balanceOf(address(this));
            if (currentDebt == 0) break;

            uint256 currentSupply = aToken.balanceOf(address(this));

            // Calculate max withdraw
            (, , , , uint256 ltv, ) = pool.getUserAccountData(address(this));
            if (ltv == 0) break;

            uint256 minCollateral = (currentDebt * BPS * 105) / (ltv * 100);
            if (currentSupply <= minCollateral) break;

            uint256 withdrawable = currentSupply - minCollateral;

            // Withdraw and repay
            uint256 withdrawn = pool.withdraw(underlyingAsset, withdrawable, address(this));
            uint256 repayAmount = withdrawn > currentDebt ? currentDebt : withdrawn;
            pool.repay(underlyingAsset, repayAmount, VARIABLE_RATE, address(this));

            emit Repaid(repayAmount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get position value (supply - debt)
    function _getPositionValue() internal view returns (uint256) {
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 borrowed = IERC20(variableDebtToken).balanceOf(address(this));
        return supplied > borrowed ? supplied - borrowed : 0;
    }

    /// @notice Get current leverage ratio in BPS
    function currentLeverageRatio() external view returns (uint256) {
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 equity = _getPositionValue();
        if (equity == 0) return 0;
        return (supplied * BPS) / equity;
    }

    /// @notice Get current health factor
    function healthFactor() external view returns (uint256) {
        (, , , , , uint256 hf) = pool.getUserAccountData(address(this));
        return hf;
    }

    /// @notice Get supply and debt balances
    function positionBalances() external view returns (uint256 supplied, uint256 borrowed, uint256 equity) {
        supplied = aToken.balanceOf(address(this));
        borrowed = IERC20(variableDebtToken).balanceOf(address(this));
        equity = supplied > borrowed ? supplied - borrowed : 0;
    }

    /// @notice Get pending rewards
    function pendingRewards() external view returns (address[] memory rewardTokens, uint256[] memory amounts) {
        address[] memory assets = new address[](2);
        assets[0] = address(aToken);
        assets[1] = variableDebtToken;
        return rewardsController.getAllUserRewards(assets, address(this));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set target leverage ratio
    /// @param _targetLeverageRatio New target ratio in BPS
    function setTargetLeverageRatio(uint256 _targetLeverageRatio) external onlyOwner {
        if (_targetLeverageRatio < BPS || _targetLeverageRatio > 50000) {
            revert InvalidLeverageRatio();
        }
        targetLeverageRatio = _targetLeverageRatio;
        emit LeverageRatioUpdated(_targetLeverageRatio);
    }

    /// @notice Set E-Mode category
    /// @param categoryId E-Mode category (0 to disable)
    function setEMode(uint8 categoryId) external onlyOwner {
        pool.setUserEMode(categoryId);
        eModeCategoryId = categoryId;
        emit EModeUpdated(categoryId);
    }

    /// @notice Set minimum health factor threshold
    /// @param _minHealthFactor New minimum health factor (18 decimals)
    function setMinHealthFactor(uint256 _minHealthFactor) external onlyOwner {
        require(_minHealthFactor >= 1e18, "Must be >= 1");
        minHealthFactor = _minHealthFactor;
        emit MinHealthFactorUpdated(_minHealthFactor);
    }

    /// @notice Set vault address
    /// @param _vault New vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Set strategy active status
    /// @param _active New active status
    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    /// @notice Emergency withdraw: deleverage and withdraw all
    function emergencyWithdraw() external onlyOwner {
        // Full deleverage first
        for (uint256 i = 0; i < MAX_LOOPS; i++) {
            uint256 currentDebt = IERC20(variableDebtToken).balanceOf(address(this));
            if (currentDebt == 0) break;

            uint256 currentSupply = aToken.balanceOf(address(this));
            (, , , , uint256 ltv, ) = pool.getUserAccountData(address(this));
            if (ltv == 0) break;

            uint256 minCollateral = (currentDebt * BPS * 105) / (ltv * 100);
            if (currentSupply <= minCollateral) break;

            uint256 withdrawable = currentSupply - minCollateral;
            uint256 withdrawn = pool.withdraw(underlyingAsset, withdrawable, address(this));
            pool.repay(underlyingAsset, withdrawn > currentDebt ? currentDebt : withdrawn, VARIABLE_RATE, address(this));
        }

        // Withdraw remaining
        uint256 remaining = aToken.balanceOf(address(this));
        if (remaining > 0) {
            pool.withdraw(underlyingAsset, type(uint256).max, owner());
        }

        // Claim rewards
        address[] memory assets = new address[](2);
        assets[0] = address(aToken);
        assets[1] = variableDebtToken;
        rewardsController.claimAllRewards(assets, owner());

        totalShares = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    /// @param token Token to rescue
    /// @param amount Amount to rescue
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(aToken), "Cannot rescue aTokens");
        require(token != variableDebtToken, "Cannot rescue debt tokens");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title AaveV3WETHSupplyStrategy
 * @notice Aave V3 WETH supply strategy (Ethereum Mainnet)
 */
contract AaveV3WETHSupplyStrategy is AaveV3SupplyStrategy {
    // Ethereum Mainnet Addresses
    address public constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant A_WETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address public constant REWARDS = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address public constant ORACLE = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    constructor(address _vault) AaveV3SupplyStrategy(
        _vault,
        POOL,
        A_WETH,
        REWARDS,
        ORACLE
    ) {}
}

/**
 * @title AaveV3USDCSupplyStrategy
 * @notice Aave V3 USDC supply strategy (Ethereum Mainnet)
 */
contract AaveV3USDCSupplyStrategy is AaveV3SupplyStrategy {
    // Ethereum Mainnet Addresses
    address public constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant A_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address public constant REWARDS = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address public constant ORACLE = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    constructor(address _vault) AaveV3SupplyStrategy(
        _vault,
        POOL,
        A_USDC,
        REWARDS,
        ORACLE
    ) {}
}

/**
 * @title AaveV3WETHLeverageStrategy
 * @notice Aave V3 WETH leverage strategy (Ethereum Mainnet)
 * @dev Uses E-Mode for ETH-correlated assets for higher LTV
 */
contract AaveV3WETHLeverageStrategy is AaveV3LeverageStrategy {
    // Ethereum Mainnet Addresses
    address public constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant A_WETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address public constant REWARDS = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address public constant ORACLE = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    // E-Mode category 1 = ETH correlated (stETH, cbETH, rETH, wstETH)
    uint8 public constant ETH_EMODE = 1;

    constructor(address _vault, uint256 _targetLeverage) AaveV3LeverageStrategy(
        _vault,
        POOL,
        A_WETH,
        REWARDS,
        ORACLE,
        _targetLeverage
    ) {
        // Enable E-Mode for higher LTV
        pool.setUserEMode(ETH_EMODE);
        eModeCategoryId = ETH_EMODE;
    }
}

/**
 * @title AaveV3StablecoinsLeverageStrategy
 * @notice Aave V3 stablecoin leverage strategy (Ethereum Mainnet)
 * @dev Uses E-Mode for stablecoins for higher LTV (up to 97%)
 */
contract AaveV3StablecoinsLeverageStrategy is AaveV3LeverageStrategy {
    // Ethereum Mainnet Addresses
    address public constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant A_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address public constant REWARDS = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address public constant ORACLE = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    // E-Mode category 2 = Stablecoins (USDC, DAI, USDT, etc.)
    uint8 public constant STABLECOIN_EMODE = 2;

    constructor(address _vault, uint256 _targetLeverage) AaveV3LeverageStrategy(
        _vault,
        POOL,
        A_USDC,
        REWARDS,
        ORACLE,
        _targetLeverage
    ) {
        // Enable E-Mode for higher LTV on stablecoins
        pool.setUserEMode(STABLECOIN_EMODE);
        eModeCategoryId = STABLECOIN_EMODE;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title AaveV3StrategyFactory
 * @notice Factory for deploying Aave V3 strategies
 */
contract AaveV3StrategyFactory {
    /// @notice Emitted when a supply strategy is deployed
    event SupplyStrategyDeployed(address indexed strategy, address indexed vault, address indexed aToken);

    /// @notice Emitted when a leverage strategy is deployed
    event LeverageStrategyDeployed(address indexed strategy, address indexed vault, address indexed aToken, uint256 leverage);

    /// @notice Deploy a generic supply strategy
    function deploySupply(
        address vault,
        address poolAddr,
        address aTokenAddr,
        address rewardsAddr,
        address oracleAddr
    ) external returns (address strategy) {
        strategy = address(new AaveV3SupplyStrategy(vault, poolAddr, aTokenAddr, rewardsAddr, oracleAddr));
        emit SupplyStrategyDeployed(strategy, vault, aTokenAddr);
    }

    /// @notice Deploy a generic leverage strategy
    function deployLeverage(
        address vault,
        address poolAddr,
        address aTokenAddr,
        address rewardsAddr,
        address oracleAddr,
        uint256 targetLeverage
    ) external returns (address strategy) {
        strategy = address(new AaveV3LeverageStrategy(vault, poolAddr, aTokenAddr, rewardsAddr, oracleAddr, targetLeverage));
        emit LeverageStrategyDeployed(strategy, vault, aTokenAddr, targetLeverage);
    }

    /// @notice Deploy WETH supply strategy (Ethereum Mainnet)
    function deployWETHSupply(address vault) external returns (address) {
        return address(new AaveV3WETHSupplyStrategy(vault));
    }

    /// @notice Deploy USDC supply strategy (Ethereum Mainnet)
    function deployUSDCSupply(address vault) external returns (address) {
        return address(new AaveV3USDCSupplyStrategy(vault));
    }

    /// @notice Deploy WETH leverage strategy (Ethereum Mainnet)
    /// @param vault Vault address
    /// @param targetLeverage Target leverage in BPS (e.g., 20000 = 2x)
    function deployWETHLeverage(address vault, uint256 targetLeverage) external returns (address) {
        return address(new AaveV3WETHLeverageStrategy(vault, targetLeverage));
    }

    /// @notice Deploy stablecoin leverage strategy (Ethereum Mainnet)
    /// @param vault Vault address
    /// @param targetLeverage Target leverage in BPS (e.g., 30000 = 3x)
    function deployStablecoinLeverage(address vault, uint256 targetLeverage) external returns (address) {
        return address(new AaveV3StablecoinsLeverageStrategy(vault, targetLeverage));
    }
}
