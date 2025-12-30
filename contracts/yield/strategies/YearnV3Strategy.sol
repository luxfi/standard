// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title YearnV3Strategy
 * @notice Yield strategy for Yearn V3 vaults (ERC-4626 compliant)
 * @dev Supports Yearn V3 multi-strategy vaults with optional gauge staking
 *
 * Yearn V3 improvements over V2:
 * - ERC-4626 standard compliance
 * - Modular strategy system
 * - Native multi-asset support
 * - Gauge staking for boosted yields (veYFI)
 *
 * Yield sources:
 * - Strategy allocations (lending, LPing, leveraging)
 * - YFI gauge rewards (if gauge staked)
 * - Performance fees returned as vault appreciation
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// YEARN V3 INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice ERC-4626 Tokenized Vault Standard (Yearn V3 vaults implement this)
interface IERC4626 {
    /// @notice Deposit assets and receive shares
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Mint exact shares
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Withdraw assets by burning shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Redeem shares for assets
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Get total assets managed by vault
    function totalAssets() external view returns (uint256);

    /// @notice Get total supply of vault shares
    function totalSupply() external view returns (uint256);

    /// @notice Get share balance of account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get underlying asset
    function asset() external view returns (address);

    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Preview deposit
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Preview mint
    function previewMint(uint256 shares) external view returns (uint256);

    /// @notice Preview withdraw
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Preview redeem
    function previewRedeem(uint256 shares) external view returns (uint256);

    /// @notice Max deposit for receiver
    function maxDeposit(address receiver) external view returns (uint256);

    /// @notice Max withdraw for owner
    function maxWithdraw(address owner) external view returns (uint256);

    /// @notice Max redeem for owner
    function maxRedeem(address owner) external view returns (uint256);

    /// @notice Decimals
    function decimals() external view returns (uint8);

    /// @notice Approve spender
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Yearn V3 Vault extended interface
interface IYearnV3Vault is IERC4626 {
    /// @notice Get price per share (scaled by decimals)
    function pricePerShare() external view returns (uint256);

    /// @notice Get vault API version
    function apiVersion() external view returns (string memory);

    /// @notice Get vault name
    function name() external view returns (string memory);

    /// @notice Get vault symbol
    function symbol() external view returns (string memory);

    /// @notice Get management fee (in basis points)
    function managementFee() external view returns (uint256);

    /// @notice Get performance fee (in basis points)
    function performanceFee() external view returns (uint256);

    /// @notice Check if deposits are locked
    function depositLimit() external view returns (uint256);

    /// @notice Process reports and harvest strategies
    function process_report(address strategy) external returns (uint256, uint256);

    /// @notice Get shutdown status
    function isShutdown() external view returns (bool);
}

/// @notice Yearn V3 Gauge interface for veYFI boosted rewards
interface IYearnGauge {
    /// @notice Deposit vault tokens to gauge
    function deposit(uint256 amount) external;

    /// @notice Deposit vault tokens to gauge for another address
    function deposit(uint256 amount, address recipient) external;

    /// @notice Withdraw vault tokens from gauge
    function withdraw(uint256 amount) external;

    /// @notice Withdraw vault tokens from gauge with claim
    function withdraw(uint256 amount, bool claim) external;

    /// @notice Claim YFI rewards
    function getReward() external;

    /// @notice Get pending YFI rewards
    function earned(address account) external view returns (uint256);

    /// @notice Get staked balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get boost multiplier for account
    function boostedBalanceOf(address account) external view returns (uint256);

    /// @notice Total staked in gauge
    function totalSupply() external view returns (uint256);

    /// @notice Reward rate per second
    function rewardRate() external view returns (uint256);
}

/// @notice veYFI interface for gauge boost
interface IVeYFI {
    function balanceOf(address account) external view returns (uint256);
    function locked(address account) external view returns (uint256 amount, uint256 end);
}

/// @notice YFI token interface
interface IYFI is IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}

// ═══════════════════════════════════════════════════════════════════════════════
// YEARN V3 STRATEGY BASE
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title YearnV3Strategy
 * @notice Base strategy for Yearn V3 ERC-4626 vaults
 * @dev Handles vault deposits, gauge staking, and YFI reward claiming
 */
contract YearnV3Strategy is Ownable{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice YFI token (Ethereum mainnet)
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    /// @notice veYFI token (Ethereum mainnet)
    address public constant VE_YFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Yearn V3 vault
    IYearnV3Vault public immutable yearnVault;

    /// @notice Underlying asset (IYieldStrategy.asset() implementation)
    address public immutable asset;

    /// @notice Total deposited assets
    uint256 public totalDeposited;

    /// @notice Gauge for YFI rewards (address(0) if no gauge)
    IYearnGauge public immutable gauge;

    /// @notice Whether gauge staking is enabled
    bool public immutable hasGauge;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total vault shares held (either in vault or gauge)
    uint256 public totalVaultShares;

    /// @notice Accumulated YFI rewards harvested
    uint256 public accumulatedYFI;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Last price per share (for yield tracking)
    uint256 public lastPricePerShare;

    /// @notice Last harvest timestamp
    uint256 public lastHarvest;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 assets, uint256 vaultShares, bool stakedInGauge);
    event Withdrawn(uint256 vaultShares, uint256 assets);
    event YFIHarvested(uint256 amount);
    event YieldHarvested(uint256 yieldAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error NotActive();
    error OnlyVault();
    error InsufficientShares();
    error VaultShutdown();
    error DepositLimitExceeded();
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
     * @notice Construct Yearn V3 strategy
     * @param _vault Vault that controls this strategy
     * @param _yearnVault Yearn V3 vault address
     * @param _gauge Optional gauge for YFI rewards (address(0) to skip)
     */
    constructor(
        address _vault,
        address _yearnVault,
        address _gauge
    ) Ownable(msg.sender) {
        vault = _vault;
        yearnVault = IYearnV3Vault(_yearnVault);
        asset = IYearnV3Vault(_yearnVault).asset();

        gauge = IYearnGauge(_gauge);
        hasGauge = _gauge != address(0);

        // Approve Yearn vault to spend underlying
        IERC20(asset).approve(_yearnVault, type(uint256).max);

        // If gauge exists, approve gauge to spend vault shares
        if (hasGauge) {
            IERC20(_yearnVault).approve(_gauge, type(uint256).max);
        }

        // Initialize price tracking
        lastPricePerShare = yearnVault.pricePerShare();
        lastHarvest = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault whenActive returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        if (yearnVault.isShutdown()) revert VaultShutdown();

        // Check deposit limit
        uint256 maxDeposit = yearnVault.maxDeposit(address(this));
        if (amount > maxDeposit) revert DepositLimitExceeded();

        // Transfer asset from vault
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to Yearn vault
        shares = yearnVault.deposit(amount, address(this));
        totalVaultShares += shares;
        totalDeposited += amount;

        // Stake in gauge if available
        if (hasGauge) {
            gauge.deposit(shares);
        }

        emit Deposited(amount, shares, hasGauge);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares > totalVaultShares) revert InsufficientShares();

        // Withdraw from gauge if staked
        if (hasGauge) {
            gauge.withdraw(shares, true); // true = claim rewards
        }

        totalVaultShares -= shares;

        // Redeem from Yearn vault
        amount = yearnVault.redeem(shares, msg.sender, address(this));

        // Update total deposited
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim YFI from gauge
        if (hasGauge) {
            uint256 yfiBefore = IERC20(YFI).balanceOf(address(this));
            gauge.getReward();
            uint256 yfiEarned = IERC20(YFI).balanceOf(address(this)) - yfiBefore;

            if (yfiEarned > 0) {
                // Transfer YFI to vault (vault can sell or compound)
                IERC20(YFI).safeTransfer(vault, yfiEarned);
                accumulatedYFI += yfiEarned;
                emit YFIHarvested(yfiEarned);
            }
        }

        // Calculate yield from vault appreciation
        uint256 currentPricePerShare = yearnVault.pricePerShare();
        if (currentPricePerShare > lastPricePerShare && totalVaultShares > 0) {
            // Yield = shares * (new_price - old_price) / 1e18
            uint256 decimals = yearnVault.decimals();
            uint256 priceGain = currentPricePerShare - lastPricePerShare;
            harvested = (totalVaultShares * priceGain) / (10 ** decimals);

            emit YieldHarvested(harvested);
        }

        lastPricePerShare = currentPricePerShare;
        lastHarvest = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return yearnVault.convertToAssets(totalVaultShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate APY from price per share growth
        // This is a simplified estimate based on recent vault performance
        // In production, would query historical data or external oracle

        // Base vault yield (typically 5-15% for Yearn)
        uint256 baseAPY = 800; // 8% default estimate

        // Add gauge boost if staked
        if (hasGauge && totalVaultShares > 0) {
            uint256 rewardRate = gauge.rewardRate();
            uint256 totalStaked = gauge.totalSupply();

            if (totalStaked > 0) {
                // APY = (rewardRate * seconds_per_year * YFI_price) / (totalStaked * share_price)
                // Simplified: assume 10% boost on average
                baseAPY += 200; // +2% from gauge
            }
        }

        return baseAPY;
    }

    /// @notice Get yield token (vault shares)
    function yieldToken() external view returns (address) {
        return address(yearnVault);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active && !yearnVault.isShutdown();
    }

    /// @notice
    function name() external view returns (string memory) {
        return string(abi.encodePacked("Yearn V3 ", yearnVault.symbol(), " Strategy"));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get pending YFI rewards
    function pendingYFI() external view returns (uint256) {
        if (!hasGauge) return 0;
        return gauge.earned(address(this));
    }

    /// @notice Get current boost multiplier from veYFI
    function boostMultiplier() external view returns (uint256) {
        if (!hasGauge || totalVaultShares == 0) return BPS;

        uint256 boosted = gauge.boostedBalanceOf(address(this));
        uint256 staked = gauge.balanceOf(address(this));

        if (staked == 0) return BPS;
        return (boosted * BPS) / staked;
    }

    /// @notice Get vault share balance (either in vault or gauge)
    function shareBalance() external view returns (uint256) {
        if (hasGauge) {
            return gauge.balanceOf(address(this));
        }
        return yearnVault.balanceOf(address(this));
    }

    /// @notice Get current price per share
    function pricePerShare() external view returns (uint256) {
        return yearnVault.pricePerShare();
    }

    /// @notice Get vault info
    function vaultInfo() external view returns (
        string memory vaultName,
        string memory vaultSymbol,
        uint256 managementFee,
        uint256 performanceFee,
        uint256 depositLimit,
        bool isShutdown
    ) {
        return (
            yearnVault.name(),
            yearnVault.symbol(),
            yearnVault.managementFee(),
            yearnVault.performanceFee(),
            yearnVault.depositLimit(),
            yearnVault.isShutdown()
        );
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
        // Withdraw from gauge if staked
        if (hasGauge) {
            uint256 gaugeBalance = gauge.balanceOf(address(this));
            if (gaugeBalance > 0) {
                gauge.withdraw(gaugeBalance, true);
            }
        }

        // Redeem all vault shares
        uint256 vaultBalance = yearnVault.balanceOf(address(this));
        if (vaultBalance > 0) {
            yearnVault.redeem(vaultBalance, owner(), address(this));
        }

        // Transfer any remaining YFI
        uint256 yfiBalance = IERC20(YFI).balanceOf(address(this));
        if (yfiBalance > 0) {
            IERC20(YFI).safeTransfer(owner(), yfiBalance);
        }

        // Transfer any remaining underlying
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        if (assetBalance > 0) {
            IERC20(asset).safeTransfer(owner(), assetBalance);
        }

        totalVaultShares = 0;
        active = false;
    }

    /// @notice Rescue stuck tokens
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(yearnVault), "Cannot rescue vault shares");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title YearnV3USDCStrategy
 * @notice Yearn V3 USDC vault strategy
 * @dev Uses yvUSDC-1 vault with optional gauge staking
 *
 * Yearn V3 USDC vaults typically allocate to:
 * - Aave V3 USDC lending
 * - Compound V3 USDC lending
 * - Morpho Blue USDC markets
 * - Maker DAI Savings Rate via PSM
 */
contract YearnV3USDCStrategy is YearnV3Strategy {
    // Ethereum Mainnet Addresses
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant YV_USDC = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE; // yvUSDC-1 V3
    address public constant YV_USDC_GAUGE = 0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3; // USDC gauge

    constructor(address _vault) YearnV3Strategy(
        _vault,
        YV_USDC,
        YV_USDC_GAUGE
    ) {}
}

/**
 * @title YearnV3WETHStrategy
 * @notice Yearn V3 WETH vault strategy
 * @dev Uses yvWETH-1 vault with optional gauge staking
 *
 * Yearn V3 WETH vaults typically allocate to:
 * - Aave V3 WETH lending
 * - Compound V3 WETH lending
 * - Morpho Blue WETH markets
 * - Lido stETH staking (via wrapper)
 */
contract YearnV3WETHStrategy is YearnV3Strategy {
    // Ethereum Mainnet Addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant YV_WETH = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c; // yvWETH-1 V3
    address public constant YV_WETH_GAUGE = 0x81d93531720d86f0491DeE7D03f30b3b5aC24e59; // WETH gauge

    constructor(address _vault) YearnV3Strategy(
        _vault,
        YV_WETH,
        YV_WETH_GAUGE
    ) {}
}

/**
 * @title YearnV3DAIStrategy
 * @notice Yearn V3 DAI vault strategy
 * @dev Uses yvDAI-1 vault with optional gauge staking
 *
 * Yearn V3 DAI vaults typically allocate to:
 * - Maker DAI Savings Rate (sDAI)
 * - Aave V3 DAI lending
 * - Compound V3 DAI lending
 * - Morpho Blue DAI markets
 */
contract YearnV3DAIStrategy is YearnV3Strategy {
    // Ethereum Mainnet Addresses
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant YV_DAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95; // yvDAI-1 V3
    address public constant YV_DAI_GAUGE = 0x16df8A95c3A2b8b67CF70A6D4c8B7D33f8B3D6f7; // DAI gauge

    constructor(address _vault) YearnV3Strategy(
        _vault,
        YV_DAI,
        YV_DAI_GAUGE
    ) {}
}

/**
 * @title YearnV3WBTCStrategy
 * @notice Yearn V3 WBTC vault strategy
 * @dev Uses yvWBTC-1 vault with optional gauge staking
 *
 * Yearn V3 WBTC vaults typically allocate to:
 * - Aave V3 WBTC lending
 * - Compound V3 WBTC lending
 * - Morpho Blue WBTC markets
 */
contract YearnV3WBTCStrategy is YearnV3Strategy {
    // Ethereum Mainnet Addresses
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant YV_WBTC = 0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E; // yvWBTC-1 V3
    address public constant YV_WBTC_GAUGE = 0x0000000000000000000000000000000000000000; // No gauge yet

    constructor(address _vault) YearnV3Strategy(
        _vault,
        YV_WBTC,
        YV_WBTC_GAUGE
    ) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title YearnV3StrategyFactory
 * @notice Factory for deploying Yearn V3 strategies
 */
contract YearnV3StrategyFactory {
    event StrategyDeployed(address indexed strategy, address indexed vault, address indexed yearnVault);

    /// @notice Deploy a generic Yearn V3 strategy
    function deploy(
        address vault,
        address yearnVault,
        address gauge
    ) external returns (address strategy) {
        strategy = address(new YearnV3Strategy(vault, yearnVault, gauge));
        emit StrategyDeployed(strategy, vault, yearnVault);
    }

    /// @notice Deploy USDC strategy
    function deployUSDC(address vault) external returns (address) {
        return address(new YearnV3USDCStrategy(vault));
    }

    /// @notice Deploy WETH strategy
    function deployWETH(address vault) external returns (address) {
        return address(new YearnV3WETHStrategy(vault));
    }

    /// @notice Deploy DAI strategy
    function deployDAI(address vault) external returns (address) {
        return address(new YearnV3DAIStrategy(vault));
    }

    /// @notice Deploy WBTC strategy
    function deployWBTC(address vault) external returns (address) {
        return address(new YearnV3WBTCStrategy(vault));
    }
}
