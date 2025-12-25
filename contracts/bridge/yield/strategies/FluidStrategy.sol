// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Fluid (Instadapp) Yield Strategies
/// @notice Yield strategies for Fluid Protocol's lending and DEX platforms
/// @dev Fluid is Instadapp's next-gen DeFi protocol featuring:
///      - Lending vaults with ERC4626-like interface (fUSDC, fUSDT, fWETH)
///      - DEX with concentrated liquidity and smart order routing
///      - Unified liquidity layer across lending and DEX
///      - Multi-token reward distribution
///
/// Key Features:
/// - ERC4626-compatible lending vaults
/// - Integrated DEX for efficient swaps
/// - Reward compounding via RewardsController
/// - Multi-vault management for diversification
///
/// Mainnet Addresses:
/// - Lending Factory: 0x54B91A0D94cb471F37f949c60F7Fa7935b551D03
/// - DEX Factory: 0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085
/// - Rewards Controller: 0x2F3e9e6D1C4f10B9f5D1D1F7D1F9F6E6E1E6D1C4

// =============================================================================
// FLUID INTERFACES
// =============================================================================

/// @notice Fluid Lending Factory - discovers and manages lending vaults
interface IFluidLendingFactory {
    /// @notice Get all deployed lending vaults
    function getAllVaults() external view returns (address[] memory);

    /// @notice Get vault for a specific underlying token
    function getVaultByToken(address token) external view returns (address);

    /// @notice Check if an address is a valid vault
    function isVault(address vault) external view returns (bool);

    /// @notice Create a new lending vault for a token
    function createVault(address token) external returns (address);
}

/// @notice Fluid Lending Vault - ERC4626-like yield-bearing vault
interface IFluidLendingVault {
    // ==========================================================================
    // ERC4626-LIKE INTERFACE
    // ==========================================================================

    /// @notice Deposit assets and receive vault shares
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Mint exact shares by depositing assets
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Withdraw assets by burning shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Redeem shares for assets
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Convert shares to asset amount
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Convert assets to share amount
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Maximum deposit for receiver
    function maxDeposit(address receiver) external view returns (uint256);

    /// @notice Maximum withdraw for owner
    function maxWithdraw(address owner) external view returns (uint256);

    /// @notice Preview deposit result
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Preview withdraw result
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Total assets in vault
    function totalAssets() external view returns (uint256);

    /// @notice Underlying asset address
    function asset() external view returns (address);

    /// @notice Vault share balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Total supply of vault shares
    function totalSupply() external view returns (uint256);

    // ==========================================================================
    // FLUID-SPECIFIC
    // ==========================================================================

    /// @notice Current liquidity (supply) rate in ray (1e27)
    function getLiquidityRate() external view returns (uint256);

    /// @notice Current borrow rate in ray (1e27)
    function getBorrowRate() external view returns (uint256);

    /// @notice Current utilization ratio (1e18 = 100%)
    function getUtilization() external view returns (uint256);

    /// @notice Address of rewards controller for this vault
    function rewardsController() external view returns (address);

    /// @notice Total borrowed from this vault
    function totalBorrows() external view returns (uint256);

    /// @notice Available liquidity for borrowing
    function availableLiquidity() external view returns (uint256);

    /// @notice Vault name
    function name() external view virtual returns (string memory);

    /// @notice Vault symbol
    function symbol() external view returns (string memory);

    /// @notice Decimals
    function decimals() external view returns (uint8);
}

/// @notice Fluid DEX Factory - discovers and creates liquidity pools
interface IFluidDexFactory {
    /// @notice Get all deployed DEX pools
    function getAllPools() external view returns (address[] memory);

    /// @notice Get pool for a token pair
    function getPool(address token0, address token1) external view returns (address);

    /// @notice Check if pool exists
    function poolExists(address token0, address token1) external view returns (bool);

    /// @notice Create a new pool
    function createPool(address token0, address token1, uint24 fee) external returns (address);
}

/// @notice Fluid DEX Pool - AMM liquidity pool
interface IFluidDexPool {
    /// @notice Add liquidity to the pool
    /// @param amount0 Amount of token0 to add
    /// @param amount1 Amount of token1 to add
    /// @param minLpAmount Minimum LP tokens to receive
    /// @param recipient Address to receive LP tokens
    /// @param deadline Transaction deadline
    /// @return lpAmount LP tokens minted
    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 minLpAmount,
        address recipient,
        uint256 deadline
    ) external returns (uint256 lpAmount);

    /// @notice Remove liquidity from the pool
    /// @param lpAmount LP tokens to burn
    /// @param minAmount0 Minimum token0 to receive
    /// @param minAmount1 Minimum token1 to receive
    /// @param recipient Address to receive tokens
    /// @param deadline Transaction deadline
    /// @return amount0 Token0 received
    /// @return amount1 Token1 received
    function removeLiquidity(
        uint256 lpAmount,
        uint256 minAmount0,
        uint256 minAmount1,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swap tokens
    /// @param tokenIn Input token address
    /// @param amountIn Amount to swap
    /// @param minAmountOut Minimum output amount
    /// @param recipient Address to receive output
    /// @param deadline Transaction deadline
    /// @return amountOut Output amount
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /// @notice Get pool reserves
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

    /// @notice Token0 address
    function token0() external view returns (address);

    /// @notice Token1 address
    function token1() external view returns (address);

    /// @notice Total LP token supply
    function totalSupply() external view returns (uint256);

    /// @notice LP token balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Pool fee in basis points
    function fee() external view returns (uint24);

    /// @notice Get price of token0 in terms of token1
    function getPrice() external view returns (uint256);
}

/// @notice Fluid Rewards Controller - manages reward distribution
interface IFluidRewardsController {
    /// @notice Claim pending rewards from multiple vaults
    /// @param vaults Array of vault addresses to claim from
    /// @param to Address to receive rewards
    /// @return totalRewards Total rewards claimed
    function claimRewards(address[] calldata vaults, address to) external returns (uint256 totalRewards);

    /// @notice Get pending rewards for a user across vaults
    /// @param vaults Array of vault addresses
    /// @param user User address
    /// @return pendingRewards Total pending rewards
    function getUserRewards(address[] calldata vaults, address user) external view returns (uint256 pendingRewards);

    /// @notice Get all reward token addresses
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Get reward rate for a specific vault
    function getRewardRate(address vault) external view returns (uint256);

    /// @notice Check if rewards are active for a vault
    function isRewardActive(address vault) external view returns (bool);
}

/// @notice Fluid Oracle - price feeds for assets
interface IFluidOracle {
    /// @notice Get price of a token in USD (18 decimals)
    function getPrice(address token) external view returns (uint256);

    /// @notice Get exchange rate for a lending vault (shares to assets)
    function getExchangeRate(address vault) external view returns (uint256);

    /// @notice Get TWAP price for a token
    function getTwapPrice(address token, uint32 period) external view returns (uint256);
}

/// @notice Wrapped ETH interface
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

// =============================================================================
// FLUID LENDING STRATEGY
// =============================================================================

/// @title Fluid Lending Base Strategy
/// @notice Abstract base for Fluid lending vault strategies
/// @dev Implements common lending vault integration logic
abstract contract FluidLendingBaseStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Fluid Lending Factory (Mainnet)
    address public constant LENDING_FACTORY = 0x54B91A0D94cb471F37f949c60F7Fa7935b551D03;

    /// @notice Seconds per year for APY calculation
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    /// @notice RAY (1e27) for rate scaling
    uint256 internal constant RAY = 1e27;

    /// @notice Basis points denominator
    uint256 internal constant BPS = 10000;

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Fluid lending vault
    IFluidLendingVault public immutable lendingVault;

    /// @notice Underlying asset
    IERC20 public immutable underlyingAsset;

    /// @notice Rewards controller (if available)
    address public rewardsController;

    /// @notice Controller that can deposit/withdraw
    address public controller;

    /// @notice Strategy shares held in vault
    uint256 public vaultShares;

    /// @notice Total deposited for yield tracking
    uint256 public totalDeposited;

    /// @notice Is strategy paused
    bool public isPaused;

    /// @notice Auto-compound rewards
    bool public autoCompound;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event Deposited(address indexed depositor, uint256 assets, uint256 shares);
    event Withdrawn(address indexed recipient, uint256 assets, uint256 shares);
    event Harvested(uint256 yield);
    event RewardsClaimed(uint256 amount);
    event RewardsCompounded(uint256 amount, uint256 newShares);
    event ControllerUpdated(address indexed oldController, address indexed newController);
    event AutoCompoundUpdated(bool enabled);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error InsufficientShares();
    error ZeroAmount();
    error InvalidVault();
    error DepositFailed();
    error WithdrawFailed();
    error NoRewardsController();

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyController() {
        if (msg.sender != controller && msg.sender != owner()) revert OnlyController();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert StrategyPaused();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(
        address _vault,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_vault == address(0)) revert InvalidVault();

        lendingVault = IFluidLendingVault(_vault);
        underlyingAsset = IERC20(lendingVault.asset());
        controller = _controller;
        autoCompound = true;

        // Try to get rewards controller
        try lendingVault.rewardsController() returns (address rc) {
            rewardsController = rc;
        } catch {
            // Vault may not have rewards
        }

        // Approve vault to spend underlying
        underlyingAsset.approve(_vault, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    function deposit(uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer assets from controller
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to Fluid vault
        shares = lendingVault.deposit(amount, address(this));

        vaultShares += shares;
        totalDeposited += amount;

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice
    function withdraw(uint256 amount) external onlyController nonReentrant returns (uint256 assets) {
        if (amount == 0) revert ZeroAmount();
        if (amount > vaultShares) revert InsufficientShares();

        // Redeem from Fluid vault
        assets = lendingVault.redeem(amount, controller, address(this));

        vaultShares -= amount;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(controller, assets, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Calculate yield from vault appreciation
        uint256 currentValue = lendingVault.convertToAssets(vaultShares);

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
            totalDeposited = currentValue;
            emit Harvested(harvested);
        }

        // Claim and optionally compound rewards
        if (rewardsController != address(0)) {
            _claimAndCompoundRewards();
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return lendingVault.convertToAssets(vaultShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Get liquidity rate (per second, scaled by 1e27)
        uint256 liquidityRate = lendingVault.getLiquidityRate();

        if (liquidityRate == 0) return 0;

        // Annualize and convert to basis points
        // APY = rate * seconds_per_year / RAY * BPS
        uint256 apy = (liquidityRate * SECONDS_PER_YEAR * BPS) / RAY;

        return apy;
    }

    /// @notice
    function asset() external view returns (address) {
        return address(underlyingAsset);
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && vaultShares > 0;
    }

    /// @notice
    function name() external view virtual returns (string memory);

    // =========================================================================
    // REWARDS
    // =========================================================================

    /// @notice Claim rewards from the rewards controller
    function claimRewards() external returns (uint256 claimed) {
        if (rewardsController == address(0)) revert NoRewardsController();

        address[] memory vaults = new address[](1);
        vaults[0] = address(lendingVault);

        claimed = IFluidRewardsController(rewardsController).claimRewards(vaults, address(this));

        emit RewardsClaimed(claimed);
    }

    /// @notice Get pending rewards
    function pendingRewards() external view returns (uint256) {
        if (rewardsController == address(0)) return 0;

        address[] memory vaults = new address[](1);
        vaults[0] = address(lendingVault);

        return IFluidRewardsController(rewardsController).getUserRewards(vaults, address(this));
    }

    /// @notice Internal function to claim and compound rewards
    function _claimAndCompoundRewards() internal {
        address[] memory vaults = new address[](1);
        vaults[0] = address(lendingVault);

        uint256 claimed = IFluidRewardsController(rewardsController).claimRewards(vaults, address(this));

        if (claimed > 0) {
            emit RewardsClaimed(claimed);

            if (autoCompound) {
                // Get reward tokens and compound if it matches underlying
                address[] memory rewardTokens = IFluidRewardsController(rewardsController).getRewardTokens();

                for (uint256 i = 0; i < rewardTokens.length; i++) {
                    if (rewardTokens[i] == address(underlyingAsset)) {
                        uint256 balance = underlyingAsset.balanceOf(address(this));
                        if (balance > 0) {
                            uint256 newShares = lendingVault.deposit(balance, address(this));
                            vaultShares += newShares;
                            totalDeposited += balance;
                            emit RewardsCompounded(balance, newShares);
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get current utilization rate
    function getUtilization() external view returns (uint256) {
        return lendingVault.getUtilization();
    }

    /// @notice Get max withdrawable amount
    function maxWithdrawable() external view returns (uint256) {
        return lendingVault.maxWithdraw(address(this));
    }

    /// @notice Get vault metrics
    function getVaultMetrics() external view returns (
        uint256 totalSupply,
        uint256 totalBorrows,
        uint256 liquidityRate,
        uint256 borrowRate,
        uint256 utilization
    ) {
        totalSupply = lendingVault.totalAssets();
        totalBorrows = lendingVault.totalBorrows();
        liquidityRate = lendingVault.getLiquidityRate();
        borrowRate = lendingVault.getBorrowRate();
        utilization = lendingVault.getUtilization();
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Set auto-compound flag
    function setAutoCompound(bool _autoCompound) external onlyOwner {
        autoCompound = _autoCompound;
        emit AutoCompoundUpdated(_autoCompound);
    }

    /// @notice Update rewards controller
    function setRewardsController(address _rewardsController) external onlyOwner {
        rewardsController = _rewardsController;
    }

    /// @notice Pause/unpause strategy
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Emergency withdraw all assets
    function emergencyWithdraw() external onlyOwner {
        if (vaultShares > 0) {
            uint256 assets = lendingVault.redeem(vaultShares, owner(), address(this));
            vaultShares = 0;
            totalDeposited = 0;
            emit Withdrawn(owner(), assets, vaultShares);
        }
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(underlyingAsset), "Cannot rescue underlying");
        require(token != address(lendingVault), "Cannot rescue vault shares");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// CONCRETE LENDING STRATEGIES
// =============================================================================

/// @title Fluid USDC Lending Strategy
/// @notice Supplies USDC to Fluid for yield
contract FluidLendingUSDCStrategy is FluidLendingBaseStrategy {
    /// @notice USDC address (Ethereum mainnet)
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Fluid USDC vault (fUSDC)
    address public constant FUSDC = 0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33;

    constructor(address _controller, address _owner)
        FluidLendingBaseStrategy(FUSDC, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Fluid Lending USDC";
    }
}

/// @title Fluid USDT Lending Strategy
/// @notice Supplies USDT to Fluid for yield
contract FluidLendingUSDTStrategy is FluidLendingBaseStrategy {
    /// @notice USDT address (Ethereum mainnet)
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @notice Fluid USDT vault (fUSDT)
    address public constant FUSDT = 0x5C20B550819128074FD538Edf79791733ccEdd18;

    constructor(address _controller, address _owner)
        FluidLendingBaseStrategy(FUSDT, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Fluid Lending USDT";
    }
}

/// @title Fluid WETH Lending Strategy
/// @notice Supplies WETH to Fluid for yield with native ETH support
contract FluidLendingWETHStrategy is FluidLendingBaseStrategy {
    using SafeERC20 for IERC20;

    /// @notice WETH address (Ethereum mainnet)
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Fluid WETH vault (fWETH)
    address public constant FWETH = 0x90551c1795392094FE6D29B758EcCD233cFAa260;

    constructor(address _controller, address _owner)
        FluidLendingBaseStrategy(FWETH, _controller, _owner)
    {}

    /// @notice
    function name() external pure override returns (string memory) {
        return "Fluid Lending WETH";
    }

    /// @notice Deposit native ETH (wraps to WETH first)
    function depositETH() external payable onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: msg.value}();

        // Deposit to Fluid vault
        shares = lendingVault.deposit(msg.value, address(this));

        vaultShares += shares;
        totalDeposited += msg.value;

        emit Deposited(msg.sender, msg.value, shares);
    }

    /// @notice Withdraw as native ETH
    function withdrawETH(uint256 shares) external onlyController nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (shares > vaultShares) revert InsufficientShares();

        // Redeem from Fluid vault
        assets = lendingVault.redeem(shares, address(this), address(this));

        // Unwrap WETH to ETH
        IWETH(WETH).withdraw(assets);

        // Send ETH to controller
        (bool success, ) = msg.sender.call{value: assets}("");
        require(success, "ETH transfer failed");

        vaultShares -= shares;
        if (assets <= totalDeposited) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }

        emit Withdrawn(msg.sender, assets, shares);
    }

    receive() external payable {}
}

// =============================================================================
// FLUID DEX STRATEGY
// =============================================================================

/// @title Fluid DEX Strategy
/// @notice Provides liquidity to Fluid DEX pools for trading fees
/// @dev Manages LP positions across multiple Fluid DEX pools
contract FluidDexStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @notice Fluid DEX Factory (Mainnet)
    address public constant DEX_FACTORY = 0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085;

    /// @notice Basis points denominator
    uint256 internal constant BPS = 10000;

    // =========================================================================
    // STRUCTS
    // =========================================================================

    /// @notice LP position in a pool
    struct LPPosition {
        address pool;
        address token0;
        address token1;
        uint256 lpBalance;
        uint256 deposit0;
        uint256 deposit1;
        bool active;
    }

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Controller that can deposit/withdraw
    address public controller;

    /// @notice Primary underlying token (for IYieldStrategy interface)
    address public primaryToken;

    /// @notice Secondary token in the pool
    address public secondaryToken;

    /// @notice Primary DEX pool
    IFluidDexPool public pool;

    /// @notice LP position data
    LPPosition public position;

    /// @notice Is strategy paused
    bool public isPaused;

    /// @notice Slippage tolerance in basis points (default 50 = 0.5%)
    uint256 public slippageTolerance;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event LiquidityAdded(uint256 amount0, uint256 amount1, uint256 lpTokens);
    event LiquidityRemoved(uint256 amount0, uint256 amount1, uint256 lpTokens);
    event Harvested(uint256 fees0, uint256 fees1);
    event ControllerUpdated(address indexed oldController, address indexed newController);
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error StrategyPaused();
    error OnlyController();
    error ZeroAmount();
    error InvalidPool();
    error InsufficientLiquidity();
    error SlippageExceeded();
    error DeadlineExpired();

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyController() {
        if (msg.sender != controller && msg.sender != owner()) revert OnlyController();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert StrategyPaused();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(
        address _pool,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        if (_pool == address(0)) revert InvalidPool();

        pool = IFluidDexPool(_pool);
        primaryToken = pool.token0();
        secondaryToken = pool.token1();
        controller = _controller;
        slippageTolerance = 50; // 0.5% default

        position.pool = _pool;
        position.token0 = primaryToken;
        position.token1 = secondaryToken;
        position.active = true;

        // Approve pool to spend tokens
        IERC20(primaryToken).approve(_pool, type(uint256).max);
        IERC20(secondaryToken).approve(_pool, type(uint256).max);
    }

    // =========================================================================
    // YIELD STRATEGY INTERFACE
    // =========================================================================

    /// @notice
    /// @dev For DEX strategy, deposits single-sided and pairs with optimal ratio
    function deposit(uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        // Transfer primary token from controller
        IERC20(primaryToken).safeTransferFrom(msg.sender, address(this), amount);

        // Get optimal amounts for liquidity
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 amount1 = (amount * reserve1) / reserve0;

        // Try to get secondary token from controller
        uint256 secondaryBalance = IERC20(secondaryToken).balanceOf(msg.sender);
        if (secondaryBalance >= amount1) {
            IERC20(secondaryToken).safeTransferFrom(msg.sender, address(this), amount1);
        } else {
            // Single-sided deposit - swap half
            uint256 swapAmount = amount / 2;
            amount1 = pool.swap(primaryToken, swapAmount, 0, address(this), block.timestamp + 300);
            amount = amount - swapAmount;
        }

        // Calculate minimum LP with slippage
        uint256 expectedLp = _estimateLpTokens(amount, amount1);
        uint256 minLp = (expectedLp * (BPS - slippageTolerance)) / BPS;

        // Add liquidity
        shares = pool.addLiquidity(
            amount,
            amount1,
            minLp,
            address(this),
            block.timestamp + 300
        );

        position.lpBalance += shares;
        position.deposit0 += amount;
        position.deposit1 += amount1;

        emit LiquidityAdded(amount, amount1, shares);
    }

    /// @notice
    function withdraw(uint256 amount) external onlyController nonReentrant returns (uint256 assets) {
        if (amount == 0) revert ZeroAmount();
        if (amount > position.lpBalance) revert InsufficientLiquidity();

        // Calculate proportional amounts
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 totalLp = pool.totalSupply();

        uint256 expectedAmount0 = (amount * reserve0) / totalLp;
        uint256 expectedAmount1 = (amount * reserve1) / totalLp;

        uint256 minAmount0 = (expectedAmount0 * (BPS - slippageTolerance)) / BPS;
        uint256 minAmount1 = (expectedAmount1 * (BPS - slippageTolerance)) / BPS;

        // Remove liquidity
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(
            amount,
            minAmount0,
            minAmount1,
            controller,
            block.timestamp + 300
        );

        position.lpBalance -= amount;
        if (amount0 <= position.deposit0) {
            position.deposit0 -= amount0;
        } else {
            position.deposit0 = 0;
        }
        if (amount1 <= position.deposit1) {
            position.deposit1 -= amount1;
        } else {
            position.deposit1 = 0;
        }

        // Return primary token amount
        assets = amount0;

        emit LiquidityRemoved(amount0, amount1, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // DEX fees are automatically compounded into LP position
        // Calculate yield from position growth

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 totalLp = pool.totalSupply();

        uint256 currentValue0 = (position.lpBalance * reserve0) / totalLp;
        uint256 currentValue1 = (position.lpBalance * reserve1) / totalLp;

        uint256 fees0 = 0;
        uint256 fees1 = 0;

        if (currentValue0 > position.deposit0) {
            fees0 = currentValue0 - position.deposit0;
            harvested += fees0;
        }

        if (currentValue1 > position.deposit1) {
            fees1 = currentValue1 - position.deposit1;
            harvested += fees1;
        }

        // Update deposits to current value (fees harvested)
        position.deposit0 = currentValue0;
        position.deposit1 = currentValue1;

        emit Harvested(fees0, fees1);
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        if (position.lpBalance == 0) return 0;

        (uint256 reserve0, ) = pool.getReserves();
        uint256 totalLp = pool.totalSupply();

        // Return value in primary token terms
        return (position.lpBalance * reserve0) / totalLp;
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Estimate APY from trading fees
        // This would need historical data or oracle integration for accuracy
        // Return a placeholder based on fee tier
        uint24 feeRate = pool.fee();
        // Assume 100% volume turnover per day, very rough estimate
        // Real implementation would query historical volume
        return uint256(feeRate) * 365 / 10; // Simplified estimation
    }

    /// @notice
    function asset() external view returns (address) {
        return primaryToken;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return !isPaused && position.lpBalance > 0;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Fluid DEX LP";
    }

    /// @notice
    function totalDeposited() external view returns (uint256) {
        return position.deposit0;
    }

    // =========================================================================
    // DEX-SPECIFIC FUNCTIONS
    // =========================================================================

    /// @notice Add liquidity with both tokens
    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint256 minLp,
        uint256 deadline
    ) external onlyController whenNotPaused nonReentrant returns (uint256 lpTokens) {
        if (block.timestamp > deadline) revert DeadlineExpired();

        IERC20(primaryToken).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(secondaryToken).safeTransferFrom(msg.sender, address(this), amount1);

        lpTokens = pool.addLiquidity(amount0, amount1, minLp, address(this), deadline);

        position.lpBalance += lpTokens;
        position.deposit0 += amount0;
        position.deposit1 += amount1;

        emit LiquidityAdded(amount0, amount1, lpTokens);
    }

    /// @notice Remove all liquidity
    function removeAllLiquidity(uint256 minAmount0, uint256 minAmount1)
        external
        onlyController
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (position.lpBalance == 0) revert InsufficientLiquidity();

        (amount0, amount1) = pool.removeLiquidity(
            position.lpBalance,
            minAmount0,
            minAmount1,
            msg.sender,
            block.timestamp + 300
        );

        emit LiquidityRemoved(amount0, amount1, position.lpBalance);

        position.lpBalance = 0;
        position.deposit0 = 0;
        position.deposit1 = 0;
    }

    /// @notice Get current position value
    function getPositionValue() external view returns (uint256 value0, uint256 value1) {
        if (position.lpBalance == 0) return (0, 0);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 totalLp = pool.totalSupply();

        value0 = (position.lpBalance * reserve0) / totalLp;
        value1 = (position.lpBalance * reserve1) / totalLp;
    }

    /// @notice Get pool metrics
    function getPoolMetrics() external view returns (
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalLp,
        uint24 feeRate
    ) {
        (reserve0, reserve1) = pool.getReserves();
        totalLp = pool.totalSupply();
        feeRate = pool.fee();
    }

    // =========================================================================
    // INTERNAL FUNCTIONS
    // =========================================================================

    /// @notice Estimate LP tokens for given amounts
    function _estimateLpTokens(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 totalLp = pool.totalSupply();

        if (totalLp == 0) {
            // First deposit
            return _sqrt(amount0 * amount1);
        }

        // Use the minimum ratio to avoid losing value
        uint256 lpFromAmount0 = (amount0 * totalLp) / reserve0;
        uint256 lpFromAmount1 = (amount1 * totalLp) / reserve1;

        return lpFromAmount0 < lpFromAmount1 ? lpFromAmount0 : lpFromAmount1;
    }

    /// @notice Square root using Babylonian method
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // =========================================================================
    // ADMIN FUNCTIONS
    // =========================================================================

    /// @notice Set controller address
    function setController(address _controller) external onlyOwner {
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Set slippage tolerance
    function setSlippageTolerance(uint256 _slippage) external onlyOwner {
        require(_slippage <= 1000, "Max 10% slippage");
        emit SlippageUpdated(slippageTolerance, _slippage);
        slippageTolerance = _slippage;
    }

    /// @notice Pause/unpause strategy
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Emergency withdraw all liquidity
    function emergencyWithdraw() external onlyOwner {
        if (position.lpBalance > 0) {
            (uint256 amount0, uint256 amount1) = pool.removeLiquidity(
                position.lpBalance,
                0,
                0,
                owner(),
                block.timestamp + 300
            );

            emit LiquidityRemoved(amount0, amount1, position.lpBalance);

            position.lpBalance = 0;
            position.deposit0 = 0;
            position.deposit1 = 0;
        }
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != primaryToken || position.lpBalance == 0, "Cannot rescue position tokens");
        require(token != secondaryToken || position.lpBalance == 0, "Cannot rescue position tokens");
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// MULTI-VAULT MANAGER
// =============================================================================

/// @title Fluid Multi-Vault Manager
/// @notice Manages positions across multiple Fluid lending vaults
/// @dev Enables diversification and optimal yield allocation
contract FluidMultiVaultManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // STRUCTS
    // =========================================================================

    /// @notice Vault allocation
    struct VaultAllocation {
        address vault;
        address underlying;
        uint256 shares;
        uint256 deposited;
        uint256 targetWeight; // in BPS (10000 = 100%)
        bool active;
    }

    // =========================================================================
    // STATE
    // =========================================================================

    /// @notice Lending factory
    IFluidLendingFactory public immutable factory;

    /// @notice Rewards controller
    IFluidRewardsController public rewardsController;

    /// @notice Controller that can manage positions
    address public controller;

    /// @notice All vault allocations
    VaultAllocation[] public allocations;

    /// @notice Vault index by address
    mapping(address => uint256) public vaultIndex;

    /// @notice Total target weight (should equal BPS)
    uint256 public totalWeight;

    /// @notice Is manager paused
    bool public isPaused;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event VaultAdded(address indexed vault, address indexed underlying, uint256 weight);
    event VaultRemoved(address indexed vault);
    event WeightsUpdated(address[] vaults, uint256[] weights);
    event Deposited(address indexed vault, uint256 amount, uint256 shares);
    event Withdrawn(address indexed vault, uint256 amount, uint256 shares);
    event RewardsClaimed(uint256 totalRewards);
    event Rebalanced(uint256 totalValue);

    // =========================================================================
    // ERRORS
    // =========================================================================

    error ManagerPaused();
    error OnlyController();
    error VaultAlreadyExists();
    error VaultNotFound();
    error InvalidWeight();
    error WeightMismatch();
    error InsufficientBalance();

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyController() {
        if (msg.sender != controller && msg.sender != owner()) revert OnlyController();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert ManagerPaused();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(
        address _factory,
        address _rewardsController,
        address _controller,
        address _owner
    ) Ownable(_owner) {
        factory = IFluidLendingFactory(_factory);
        rewardsController = IFluidRewardsController(_rewardsController);
        controller = _controller;
    }

    // =========================================================================
    // VAULT MANAGEMENT
    // =========================================================================

    /// @notice Add a new vault to manage
    function addVault(address vault, uint256 weight) external onlyOwner {
        if (!factory.isVault(vault)) revert VaultNotFound();
        if (vaultIndex[vault] != 0 || (allocations.length > 0 && allocations[0].vault == vault)) {
            revert VaultAlreadyExists();
        }

        address underlying = IFluidLendingVault(vault).asset();

        allocations.push(VaultAllocation({
            vault: vault,
            underlying: underlying,
            shares: 0,
            deposited: 0,
            targetWeight: weight,
            active: true
        }));

        vaultIndex[vault] = allocations.length - 1;
        totalWeight += weight;

        // Approve vault
        IERC20(underlying).approve(vault, type(uint256).max);

        emit VaultAdded(vault, underlying, weight);
    }

    /// @notice Remove a vault (must withdraw first)
    function removeVault(address vault) external onlyOwner {
        uint256 index = vaultIndex[vault];
        if (allocations[index].vault != vault) revert VaultNotFound();
        if (allocations[index].shares > 0) revert InsufficientBalance();

        totalWeight -= allocations[index].targetWeight;
        allocations[index].active = false;

        emit VaultRemoved(vault);
    }

    /// @notice Update vault weights
    function updateWeights(address[] calldata vaults, uint256[] calldata weights) external onlyOwner {
        if (vaults.length != weights.length) revert WeightMismatch();

        uint256 newTotal = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 index = vaultIndex[vaults[i]];
            if (allocations[index].vault != vaults[i]) revert VaultNotFound();

            allocations[index].targetWeight = weights[i];
            newTotal += weights[i];
        }

        // Validate total weight
        if (newTotal > 10000) revert InvalidWeight();
        totalWeight = newTotal;

        emit WeightsUpdated(vaults, weights);
    }

    // =========================================================================
    // DEPOSIT/WITHDRAW
    // =========================================================================

    /// @notice Deposit to a specific vault
    function depositToVault(address vault, uint256 amount) external onlyController whenNotPaused nonReentrant returns (uint256 shares) {
        uint256 index = vaultIndex[vault];
        if (allocations[index].vault != vault) revert VaultNotFound();

        IERC20(allocations[index].underlying).safeTransferFrom(msg.sender, address(this), amount);

        shares = IFluidLendingVault(vault).deposit(amount, address(this));

        allocations[index].shares += shares;
        allocations[index].deposited += amount;

        emit Deposited(vault, amount, shares);
    }

    /// @notice Withdraw from a specific vault
    function withdrawFromVault(address vault, uint256 shares) external onlyController nonReentrant returns (uint256 amount) {
        uint256 index = vaultIndex[vault];
        if (allocations[index].vault != vault) revert VaultNotFound();
        if (shares > allocations[index].shares) revert InsufficientBalance();

        amount = IFluidLendingVault(vault).redeem(shares, msg.sender, address(this));

        allocations[index].shares -= shares;
        if (amount <= allocations[index].deposited) {
            allocations[index].deposited -= amount;
        } else {
            allocations[index].deposited = 0;
        }

        emit Withdrawn(vault, amount, shares);
    }

    /// @notice Deposit according to target weights
    function depositWeighted(address token, uint256 amount) external onlyController whenNotPaused nonReentrant {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < allocations.length; i++) {
            if (!allocations[i].active) continue;
            if (allocations[i].underlying != token) continue;

            uint256 depositAmount = (amount * allocations[i].targetWeight) / totalWeight;
            if (depositAmount > 0) {
                uint256 shares = IFluidLendingVault(allocations[i].vault).deposit(depositAmount, address(this));
                allocations[i].shares += shares;
                allocations[i].deposited += depositAmount;

                emit Deposited(allocations[i].vault, depositAmount, shares);
            }
        }
    }

    // =========================================================================
    // REWARDS
    // =========================================================================

    /// @notice Claim all rewards
    function claimAllRewards() external returns (uint256 totalRewards) {
        address[] memory vaults = new address[](allocations.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].active && allocations[i].shares > 0) {
                vaults[count] = allocations[i].vault;
                count++;
            }
        }

        // Resize array
        assembly {
            mstore(vaults, count)
        }

        totalRewards = rewardsController.claimRewards(vaults, address(this));

        emit RewardsClaimed(totalRewards);
    }

    /// @notice Get total pending rewards
    function pendingRewards() external view returns (uint256) {
        address[] memory vaults = new address[](allocations.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].active) {
                vaults[count] = allocations[i].vault;
                count++;
            }
        }

        // Resize array
        assembly {
            mstore(vaults, count)
        }

        return rewardsController.getUserRewards(vaults, address(this));
    }

    // =========================================================================
    // VIEW FUNCTIONS
    // =========================================================================

    /// @notice Get total value across all vaults
    function totalValue() external view returns (uint256 total) {
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].shares > 0) {
                total += IFluidLendingVault(allocations[i].vault).convertToAssets(allocations[i].shares);
            }
        }
    }

    /// @notice Get vault count
    function vaultCount() external view returns (uint256) {
        return allocations.length;
    }

    /// @notice Get all allocations
    function getAllocations() external view returns (VaultAllocation[] memory) {
        return allocations;
    }

    /// @notice Get weighted average APY
    function averageAPY() external view returns (uint256) {
        uint256 weightedSum = 0;

        for (uint256 i = 0; i < allocations.length; i++) {
            if (!allocations[i].active) continue;

            uint256 rate = IFluidLendingVault(allocations[i].vault).getLiquidityRate();
            // Convert to APY in BPS
            uint256 apy = (rate * 365.25 days * 10000) / 1e27;
            weightedSum += apy * allocations[i].targetWeight;
        }

        if (totalWeight == 0) return 0;
        return weightedSum / totalWeight;
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    /// @notice Set controller
    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }

    /// @notice Set rewards controller
    function setRewardsController(address _rewardsController) external onlyOwner {
        rewardsController = IFluidRewardsController(_rewardsController);
    }

    /// @notice Pause/unpause
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /// @notice Emergency withdraw from all vaults
    function emergencyWithdrawAll() external onlyOwner {
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].shares > 0) {
                IFluidLendingVault(allocations[i].vault).redeem(
                    allocations[i].shares,
                    owner(),
                    address(this)
                );
                allocations[i].shares = 0;
                allocations[i].deposited = 0;
            }
        }
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}

// =============================================================================
// FACTORY
// =============================================================================

/// @title Fluid Strategy Factory
/// @notice Factory for deploying Fluid yield strategies
contract FluidStrategyFactory is Ownable {
    // =========================================================================
    // EVENTS
    // =========================================================================

    event LendingStrategyDeployed(address indexed strategy, address indexed vault, string strategyType);
    event DexStrategyDeployed(address indexed strategy, address indexed pool);
    event MultiVaultManagerDeployed(address indexed manager);

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor() Ownable(msg.sender) {}

    // =========================================================================
    // DEPLOYMENT FUNCTIONS
    // =========================================================================

    /// @notice Deploy USDC lending strategy
    function deployUSDCLendingStrategy(address controller) external onlyOwner returns (address) {
        FluidLendingUSDCStrategy strategy = new FluidLendingUSDCStrategy(controller, msg.sender);
        emit LendingStrategyDeployed(address(strategy), address(strategy.lendingVault()), "USDC");
        return address(strategy);
    }

    /// @notice Deploy USDT lending strategy
    function deployUSDTLendingStrategy(address controller) external onlyOwner returns (address) {
        FluidLendingUSDTStrategy strategy = new FluidLendingUSDTStrategy(controller, msg.sender);
        emit LendingStrategyDeployed(address(strategy), address(strategy.lendingVault()), "USDT");
        return address(strategy);
    }

    /// @notice Deploy WETH lending strategy
    function deployWETHLendingStrategy(address controller) external onlyOwner returns (address) {
        FluidLendingWETHStrategy strategy = new FluidLendingWETHStrategy(controller, msg.sender);
        emit LendingStrategyDeployed(address(strategy), address(strategy.lendingVault()), "WETH");
        return address(strategy);
    }

    /// @notice Deploy DEX liquidity strategy
    function deployDexStrategy(address pool, address controller) external onlyOwner returns (address) {
        FluidDexStrategy strategy = new FluidDexStrategy(pool, controller, msg.sender);
        emit DexStrategyDeployed(address(strategy), pool);
        return address(strategy);
    }

    /// @notice Deploy multi-vault manager
    function deployMultiVaultManager(
        address factory,
        address rewardsController,
        address controller
    ) external onlyOwner returns (address) {
        FluidMultiVaultManager manager = new FluidMultiVaultManager(
            factory,
            rewardsController,
            controller,
            msg.sender
        );
        emit MultiVaultManagerDeployed(address(manager));
        return address(manager);
    }

    /// @notice Deploy custom lending strategy for any Fluid vault
    function deployCustomLendingStrategy(
        address vault,
        address controller,
        string calldata strategyName
    ) external onlyOwner returns (address) {
        CustomFluidLendingStrategy strategy = new CustomFluidLendingStrategy(
            vault,
            controller,
            strategyName,
            msg.sender
        );
        emit LendingStrategyDeployed(address(strategy), vault, strategyName);
        return address(strategy);
    }
}

/// @title Custom Fluid Lending Strategy
/// @notice Generic lending strategy for any Fluid vault
contract CustomFluidLendingStrategy is FluidLendingBaseStrategy {
    string private _name;

    constructor(
        address _vault,
        address _controller,
        string memory strategyName,
        address _owner
    ) FluidLendingBaseStrategy(_vault, _controller, _owner) {
        _name = strategyName;
    }

    /// @notice
    function name() external view virtual override returns (string memory) {
        return _name;
    }
}
