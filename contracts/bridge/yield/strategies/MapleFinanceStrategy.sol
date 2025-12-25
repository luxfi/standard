// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Maple Finance Lending Strategy
/// @notice Institutional-grade undercollateralized lending for higher yields
/// @dev Maple Finance provides lending to vetted institutional borrowers
///      Higher yields (8-15% APY) but with credit risk
///      Suitable for treasury management with diversified exposure
///
/// Key Features:
/// - Undercollateralized loans to institutions (market makers, trading firms)
/// - Pool delegates perform credit assessment
/// - Higher yields than overcollateralized protocols
/// - Lock-up periods for liquidity
/// - Cover mechanisms for defaults

// ═══════════════════════════════════════════════════════════════════════════════
// MAPLE INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

interface IMaplePool {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function requestRedeem(uint256 shares, address owner) external returns (uint256 escrowedShares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function asset() external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function unrealizedLosses() external view returns (uint256);
}

interface IMaplePoolManager {
    function pool() external view returns (address);
    function poolDelegate() external view returns (address);
    function hasSufficientCover() external view returns (bool);
    function totalAssets() external view returns (uint256);
}

interface IWithdrawalManager {
    struct CycleConfig {
        uint64 initialCycleId;
        uint64 initialCycleTime;
        uint64 cycleDuration;
        uint64 windowDuration;
    }
    
    function addShares(uint256 shares, address owner) external;
    function removeShares(uint256 shares, address owner) external returns (uint256);
    function lockedShares(address owner) external view returns (uint256);
    function exitCycleId(address owner) external view returns (uint256);
    function getWindowStart(uint256 cycleId) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAPLE STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Maple Finance Pool Strategy
/// @notice Deposits into Maple lending pools for institutional yields
/// @dev Supports USDC, WETH pools with different pool delegates
contract MapleFinanceStrategy is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    string public constant name = "Maple Finance";
    string public constant protocol = "Maple";
    string public constant version = "1.0.0";
    
    // Maple V2 Mainnet Addresses
    address public constant MAPLE_GLOBALS = 0x804a6F5F667170F545Bf14e5DDB48C70B788390C;
    
    /// @notice Maple pool contract
    IMaplePool public immutable maplePool;
    
    /// @notice Pool manager
    IMaplePoolManager public immutable poolManager;
    
    /// @notice Withdrawal manager for redemption queue
    IWithdrawalManager public immutable withdrawalManager;
    
    /// @notice Underlying asset (USDC, WETH, etc.)
    IERC20 public immutable underlyingAsset;
    
    /// @notice Pool shares held
    uint256 public poolShares;
    
    /// @notice Total assets deposited (in underlying)
    uint256 public totalDeposited;
    
    /// @notice Shares pending withdrawal
    uint256 public pendingWithdrawShares;
    
    /// @notice Whether new deposits are accepted
    bool public depositsEnabled = true;
    
    bool public isPaused;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Deposited(uint256 assets, uint256 shares);
    event RedemptionRequested(uint256 shares, uint256 cycleId);
    event Redeemed(uint256 shares, uint256 assets);
    event DepositsToggled(bool enabled);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error DepositsDisabled();
    error InsufficientShares();
    error WithdrawalNotReady();
    error InsufficientCover();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        address _maplePool,
        address _poolManager,
        address _withdrawalManager,
        address _owner
    ) Ownable(_owner) {
        maplePool = IMaplePool(_maplePool);
        poolManager = IMaplePoolManager(_poolManager);
        withdrawalManager = IWithdrawalManager(_withdrawalManager);
        underlyingAsset = IERC20(maplePool.asset());
        
        // Approve pool
        underlyingAsset.approve(_maplePool, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    function asset() external view returns (address) {
        return address(underlyingAsset);
    }

    function deposit(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (!depositsEnabled) revert DepositsDisabled();
        
        // Check pool has sufficient first-loss cover
        if (!poolManager.hasSufficientCover()) revert InsufficientCover();
        
        underlyingAsset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Deposit into Maple pool
        shares = maplePool.deposit(amount, address(this));
        
        poolShares += shares;
        totalDeposited += amount;
        
        emit Deposited(amount, shares);
    }

    function withdraw(uint256 amount) 
        external 
        nonReentrant 
        returns (uint256 assets) 
    {
        // Calculate shares needed
        uint256 sharesToRedeem = (amount * poolShares) / totalDeposited;
        if (sharesToRedeem > poolShares - pendingWithdrawShares) revert InsufficientShares();
        
        // Maple uses a withdrawal queue system
        // First, request redemption (locks shares)
        uint256 escrowedShares = maplePool.requestRedeem(sharesToRedeem, address(this));
        pendingWithdrawShares += escrowedShares;
        
        // Actual withdrawal happens in separate transaction after cycle
        // For now, record the request
        uint256 cycleId = withdrawalManager.exitCycleId(address(this));
        
        emit RedemptionRequested(escrowedShares, cycleId);
        
        // Note: Caller must call `completeWithdrawal` after cycle window opens
        return 0; // Assets received later
    }

    /// @notice Complete pending withdrawal after cycle window opens
    function completeWithdrawal(address recipient) external nonReentrant returns (uint256 assets) {
        uint256 sharesToRedeem = pendingWithdrawShares;
        if (sharesToRedeem == 0) revert InsufficientShares();
        
        // Check if withdrawal window is open
        uint256 cycleId = withdrawalManager.exitCycleId(address(this));
        uint256 windowStart = withdrawalManager.getWindowStart(cycleId);
        if (block.timestamp < windowStart) revert WithdrawalNotReady();
        
        // Execute redemption
        assets = maplePool.redeem(sharesToRedeem, msg.sender, address(this));
        
        poolShares -= sharesToRedeem;
        pendingWithdrawShares = 0;
        totalDeposited -= assets;
        
        emit Redeemed(sharesToRedeem, assets);
    }

    function harvest() external returns (uint256 yield) {
        // Maple pools accrue yield in share price
        uint256 currentValue = maplePool.convertToAssets(poolShares);
        
        if (currentValue > totalDeposited) {
            yield = currentValue - totalDeposited;
            // Yield is embedded in share value, no need to claim
        }
        
        return yield;
    }

    function totalAssets() external view returns (uint256) {
        // Current value minus any unrealized losses
        uint256 currentValue = maplePool.convertToAssets(poolShares);
        uint256 losses = maplePool.unrealizedLosses();
        return currentValue > losses ? currentValue - losses : 0;
    }

    function currentAPY() external pure returns (uint256) {
        // Maple yields vary by pool, typically 8-15%
        return 1000; // ~10% APY baseline
    }

    function isActive() external view returns (bool) {
        return !isPaused && poolShares > 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get pool delegate (credit assessor)
    function getPoolDelegate() external view returns (address) {
        return poolManager.poolDelegate();
    }

    /// @notice Check if pool has sufficient first-loss cover
    function hasSufficientCover() external view returns (bool) {
        return poolManager.hasSufficientCover();
    }

    /// @notice Get pending withdrawal info
    function getPendingWithdrawal() external view returns (
        uint256 shares,
        uint256 cycleId,
        uint256 windowStart
    ) {
        shares = pendingWithdrawShares;
        cycleId = withdrawalManager.exitCycleId(address(this));
        windowStart = withdrawalManager.getWindowStart(cycleId);
    }

    /// @notice Get current share price
    function getSharePrice() external view returns (uint256) {
        if (poolShares == 0) return 1e18;
        return (maplePool.convertToAssets(1e18));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════════

    function setDepositsEnabled(bool enabled) external onlyOwner {
        depositsEnabled = enabled;
        emit DepositsToggled(enabled);
    }

    function setPaused(bool paused) external onlyOwner {
        isPaused = paused;
    }

    function emergencyWithdraw() external onlyOwner {
        // Request all shares for withdrawal
        if (poolShares > pendingWithdrawShares) {
            uint256 sharesToRequest = poolShares - pendingWithdrawShares;
            maplePool.requestRedeem(sharesToRequest, address(this));
            pendingWithdrawShares = poolShares;
        }
    }

    error StrategyPaused();
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAPLE POOL FACTORIES
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Maple USDC Pool Strategy
/// @notice Lends USDC to institutional borrowers
contract MapleUSDCStrategy is MapleFinanceStrategy {
    // Maple USDC Pool (Mainnet) - specific pool address TBD
    address public constant MAPLE_USDC_POOL = address(0);
    address public constant MAPLE_USDC_MANAGER = address(0);
    address public constant MAPLE_USDC_WITHDRAWAL = address(0);
    
    constructor(address _owner) 
        MapleFinanceStrategy(
            MAPLE_USDC_POOL,
            MAPLE_USDC_MANAGER,
            MAPLE_USDC_WITHDRAWAL,
            _owner
        ) 
    {}
}

/// @title Maple WETH Pool Strategy
/// @notice Lends WETH to institutional borrowers
contract MapleWETHStrategy is MapleFinanceStrategy {
    // Maple WETH Pool (Mainnet) - specific pool address TBD
    address public constant MAPLE_WETH_POOL = address(0);
    address public constant MAPLE_WETH_MANAGER = address(0);
    address public constant MAPLE_WETH_WITHDRAWAL = address(0);
    
    constructor(address _owner) 
        MapleFinanceStrategy(
            MAPLE_WETH_POOL,
            MAPLE_WETH_MANAGER,
            MAPLE_WETH_WITHDRAWAL,
            _owner
        ) 
    {}
}
