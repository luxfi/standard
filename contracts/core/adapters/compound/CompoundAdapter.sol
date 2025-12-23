// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICapital, RiskTier, CapitalState} from "../../interfaces/ICapital.sol";
import {IYield, YieldType, AccrualPattern} from "../../interfaces/IYield.sol";
import {IObligation, Monotonicity, ObligationState, ObligationLib} from "../../interfaces/IObligation.sol";
import {IRisk, HealthStatus, InterventionType} from "../../interfaces/IRisk.sol";
import {ISettlement, SettlementType} from "../../interfaces/ISettlement.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                        COMPOUND LENDING ADAPTER                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  ⚠️  WARNING: INCREASING OBLIGATION MODEL                                     ║
 * ║                                                                               ║
 * ║  This adapter implements traditional collateralized lending where:            ║
 * ║    • Borrowers pay interest (obligations INCREASE over time)                 ║
 * ║    • Lenders earn yield from interest payments                               ║
 * ║    • Liquidation occurs when health factor drops below 1.0                   ║
 * ║                                                                               ║
 * ║  ┌─────────────────────────────────────────────────────────────────────┐     ║
 * ║  │                    THE RIBA (INTEREST) MODEL                        │     ║
 * ║  │                                                                     │     ║
 * ║  │   Time 0:     Borrow $1,000                                        │     ║
 * ║  │   Year 1:     Owe $1,100 (+10% interest)                           │     ║
 * ║  │   Year 2:     Owe $1,210 (+10% compound)                           │     ║
 * ║  │   Year 5:     Owe $1,610                                           │     ║
 * ║  │   Year 10:    Owe $2,593                                           │     ║
 * ║  │                                                                     │     ║
 * ║  │   The debt grows EXPONENTIALLY.                                    │     ║
 * ║  │   TIME WORKS AGAINST THE BORROWER.                                 │     ║
 * ║  │                                                                     │     ║
 * ║  │   This is the model that creates:                                  │     ║
 * ║  │     • Debt spirals                                                 │     ║
 * ║  │     • Wealth inequality                                            │     ║
 * ║  │     • Economic instability                                         │     ║
 * ║  │                                                                     │     ║
 * ║  │   It is NOT Shariah-compliant (riba is forbidden).                │     ║
 * ║  └─────────────────────────────────────────────────────────────────────┘     ║
 * ║                                                                               ║
 * ║  Compare with: AlchemicCredit (DECREASING obligations)                       ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

/// @notice Lending pool state
struct LendingPool {
    IERC20 asset;               // Underlying asset
    uint256 totalDeposits;      // Total supplied
    uint256 totalBorrows;       // Total borrowed
    uint256 borrowRate;         // Current borrow rate (per second, scaled by 1e18)
    uint256 supplyRate;         // Current supply rate (per second, scaled by 1e18)
    uint256 lastUpdate;         // Last accrual timestamp
    uint256 borrowIndex;        // Accumulated borrow interest index
    uint256 supplyIndex;        // Accumulated supply interest index
    uint256 reserveFactor;      // Protocol fee (basis points)
}

/// @notice User deposit position
struct SupplyPosition {
    uint256 principal;          // Amount deposited
    uint256 lastIndex;          // Index at last interaction
}

/// @notice User borrow position (INCREASING obligation)
struct BorrowPosition {
    uint256 principal;          // Initial borrowed amount
    uint256 lastIndex;          // Index at last interaction
    uint256 collateralValue;    // Collateral backing this loan
    address collateralAsset;    // Collateral token
}

/// @notice Adapter errors
error InsufficientLiquidity();
error InsufficientCollateral();
error HealthyPosition();
error UnhealthyPosition();
error ZeroAmount();
error PoolNotInitialized();

contract CompoundAdapter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ObligationLib for Monotonicity;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant SCALE = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80% LTV triggers liquidation
    uint256 public constant LIQUIDATION_BONUS = 500;      // 5% bonus to liquidators
    uint256 public constant MAX_LTV = 7500;               // 75% max borrow
    uint256 public constant HEALTH_PRECISION = 10000;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Lending pools by asset address
    mapping(address => LendingPool) public pools;

    /// @notice Supply positions: user => asset => position
    mapping(address => mapping(address => SupplyPosition)) public supplyPositions;

    /// @notice Borrow positions: user => asset => position
    mapping(address => mapping(address => BorrowPosition)) public borrowPositions;

    /// @notice Price oracle
    address public priceOracle;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event PoolInitialized(address indexed asset, uint256 borrowRate);
    event Supplied(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount, uint256 obligation);
    event Repaid(address indexed user, address indexed asset, uint256 amount, uint256 remaining);
    event InterestAccrued(address indexed asset, uint256 borrowIndex, uint256 supplyIndex);
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        address indexed asset,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address _priceOracle) {
        priceOracle = _priceOracle;
    }

    /**
     * @notice Initialize a lending pool
     * @param asset Asset address
     * @param baseRate Base borrow rate (APR in basis points)
     * @param reserveFactor Protocol fee (basis points)
     */
    function initializePool(
        address asset,
        uint256 baseRate,
        uint256 reserveFactor
    ) external {
        LendingPool storage pool = pools[asset];
        require(address(pool.asset) == address(0), "Already initialized");

        // Convert APR to per-second rate
        uint256 ratePerSecond = (baseRate * SCALE) / (10000 * SECONDS_PER_YEAR);

        pool.asset = IERC20(asset);
        pool.borrowRate = ratePerSecond;
        pool.supplyRate = (ratePerSecond * (10000 - reserveFactor)) / 10000;
        pool.lastUpdate = block.timestamp;
        pool.borrowIndex = SCALE;
        pool.supplyIndex = SCALE;
        pool.reserveFactor = reserveFactor;

        emit PoolInitialized(asset, baseRate);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUPPLY (CAPITAL)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Supply assets to earn yield
     * @dev Capital → Yield (INTEREST type)
     */
    function supply(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        LendingPool storage pool = pools[asset];
        if (address(pool.asset) == address(0)) revert PoolNotInitialized();

        // Accrue interest first
        _accrueInterest(pool);

        // Transfer assets
        pool.asset.safeTransferFrom(msg.sender, address(this), amount);

        // Update position
        SupplyPosition storage position = supplyPositions[msg.sender][asset];
        if (position.principal > 0) {
            // Credit accrued interest to principal
            position.principal = _getSupplyBalance(position, pool);
        }
        position.principal += amount;
        position.lastIndex = pool.supplyIndex;

        pool.totalDeposits += amount;

        emit Supplied(msg.sender, asset, amount);
    }

    /**
     * @notice Withdraw supplied assets
     */
    function withdraw(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        LendingPool storage pool = pools[asset];
        if (address(pool.asset) == address(0)) revert PoolNotInitialized();

        // Accrue interest first
        _accrueInterest(pool);

        SupplyPosition storage position = supplyPositions[msg.sender][asset];
        uint256 balance = _getSupplyBalance(position, pool);

        if (amount > balance) revert InsufficientLiquidity();
        if (amount > pool.totalDeposits - pool.totalBorrows) revert InsufficientLiquidity();

        // Update position
        position.principal = balance - amount;
        position.lastIndex = pool.supplyIndex;

        pool.totalDeposits -= amount;

        // Transfer
        pool.asset.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, asset, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BORROW (INCREASING OBLIGATION)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Borrow assets against collateral
     * @dev Creates an INCREASING obligation (riba)
     * @param asset Asset to borrow
     * @param amount Amount to borrow
     * @param collateralAsset Collateral asset
     * @param collateralAmount Collateral amount
     */
    function borrow(
        address asset,
        uint256 amount,
        address collateralAsset,
        uint256 collateralAmount
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        LendingPool storage pool = pools[asset];
        if (address(pool.asset) == address(0)) revert PoolNotInitialized();

        // Accrue interest first
        _accrueInterest(pool);

        // Check liquidity
        if (amount > pool.totalDeposits - pool.totalBorrows) revert InsufficientLiquidity();

        // Get collateral value
        uint256 collateralValue = _getCollateralValue(collateralAsset, collateralAmount, asset);
        uint256 maxBorrow = (collateralValue * MAX_LTV) / HEALTH_PRECISION;

        BorrowPosition storage position = borrowPositions[msg.sender][asset];
        uint256 currentDebt = _getBorrowBalance(position, pool);

        if (currentDebt + amount > maxBorrow) revert InsufficientCollateral();

        // Take collateral
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Update position - THE INCREASING OBLIGATION BEGINS HERE
        position.principal = currentDebt + amount;
        position.lastIndex = pool.borrowIndex;
        position.collateralValue += collateralValue;
        position.collateralAsset = collateralAsset;

        pool.totalBorrows += amount;

        // Transfer borrowed assets
        pool.asset.safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, asset, amount, position.principal);
    }

    /**
     * @notice Repay borrowed assets
     * @param asset Asset to repay
     * @param amount Amount to repay (type(uint256).max for full repayment)
     */
    function repay(address asset, uint256 amount) external nonReentrant {
        LendingPool storage pool = pools[asset];
        if (address(pool.asset) == address(0)) revert PoolNotInitialized();

        // Accrue interest first
        _accrueInterest(pool);

        BorrowPosition storage position = borrowPositions[msg.sender][asset];
        uint256 currentDebt = _getBorrowBalance(position, pool);

        // Handle full repayment
        if (amount == type(uint256).max) {
            amount = currentDebt;
        }

        if (amount > currentDebt) {
            amount = currentDebt;
        }

        // Transfer repayment
        pool.asset.safeTransferFrom(msg.sender, address(this), amount);

        // Update position
        position.principal = currentDebt - amount;
        position.lastIndex = pool.borrowIndex;

        pool.totalBorrows -= amount;

        emit Repaid(msg.sender, asset, amount, position.principal);

        // Return collateral if fully repaid
        if (position.principal == 0 && position.collateralAsset != address(0)) {
            uint256 collateralToReturn = position.collateralValue;
            position.collateralValue = 0;
            IERC20(position.collateralAsset).safeTransfer(msg.sender, collateralToReturn);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LIQUIDATION (RISK INTERVENTION)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidate an unhealthy position
     * @dev Risk intervention when health < 1.0
     */
    function liquidate(
        address borrower,
        address asset,
        uint256 repayAmount
    ) external nonReentrant {
        LendingPool storage pool = pools[asset];
        if (address(pool.asset) == address(0)) revert PoolNotInitialized();

        // Accrue interest
        _accrueInterest(pool);

        BorrowPosition storage position = borrowPositions[borrower][asset];
        uint256 currentDebt = _getBorrowBalance(position, pool);

        // Check health factor
        uint256 healthFactor = _calculateHealth(position, pool);
        if (healthFactor >= HEALTH_PRECISION) revert HealthyPosition();

        // Calculate max liquidation (50% of debt)
        uint256 maxLiquidation = currentDebt / 2;
        if (repayAmount > maxLiquidation) {
            repayAmount = maxLiquidation;
        }

        // Calculate collateral to seize (with bonus)
        uint256 collateralSeized = (repayAmount * (HEALTH_PRECISION + LIQUIDATION_BONUS)) / HEALTH_PRECISION;

        // Execute liquidation
        pool.asset.safeTransferFrom(msg.sender, address(this), repayAmount);

        // Update borrower position
        position.principal = currentDebt - repayAmount;
        position.lastIndex = pool.borrowIndex;
        position.collateralValue -= collateralSeized;

        pool.totalBorrows -= repayAmount;

        // Transfer collateral to liquidator
        IERC20(position.collateralAsset).safeTransfer(msg.sender, collateralSeized);

        emit Liquidated(borrower, msg.sender, asset, repayAmount, collateralSeized);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEREST ACCRUAL (THE INCREASING MECHANISM)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Accrue interest for a pool
     * @dev THIS IS WHERE OBLIGATIONS INCREASE
     */
    function _accrueInterest(LendingPool storage pool) internal {
        uint256 elapsed = block.timestamp - pool.lastUpdate;
        if (elapsed == 0) return;

        // Calculate interest multiplier
        // compound = (1 + rate)^elapsed ≈ 1 + rate * elapsed (linear approx for small rates)
        uint256 borrowInterest = (pool.borrowRate * elapsed);
        uint256 supplyInterest = (pool.supplyRate * elapsed);

        // Update indices (this is where debt GROWS)
        pool.borrowIndex = pool.borrowIndex + (pool.borrowIndex * borrowInterest) / SCALE;
        pool.supplyIndex = pool.supplyIndex + (pool.supplyIndex * supplyInterest) / SCALE;

        pool.lastUpdate = block.timestamp;

        emit InterestAccrued(address(pool.asset), pool.borrowIndex, pool.supplyIndex);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _getSupplyBalance(
        SupplyPosition storage position,
        LendingPool storage pool
    ) internal view returns (uint256) {
        if (position.principal == 0) return 0;
        return (position.principal * pool.supplyIndex) / position.lastIndex;
    }

    function _getBorrowBalance(
        BorrowPosition storage position,
        LendingPool storage pool
    ) internal view returns (uint256) {
        if (position.principal == 0) return 0;
        // THIS IS THE INCREASING OBLIGATION
        return (position.principal * pool.borrowIndex) / position.lastIndex;
    }

    function _calculateHealth(
        BorrowPosition storage position,
        LendingPool storage pool
    ) internal view returns (uint256) {
        uint256 debt = _getBorrowBalance(position, pool);
        if (debt == 0) return type(uint256).max;

        uint256 liquidationValue = (position.collateralValue * LIQUIDATION_THRESHOLD) / HEALTH_PRECISION;
        return (liquidationValue * HEALTH_PRECISION) / debt;
    }

    function _getCollateralValue(
        address collateralAsset,
        uint256 amount,
        address borrowAsset
    ) internal view returns (uint256) {
        // Simplified: assume 1:1 pricing
        // Real implementation would use oracle
        return amount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get user's supply balance with accrued interest
     */
    function getSupplyBalance(address user, address asset) external view returns (uint256) {
        LendingPool storage pool = pools[asset];
        SupplyPosition storage position = supplyPositions[user][asset];
        return _getSupplyBalance(position, pool);
    }

    /**
     * @notice Get user's borrow balance with accrued interest
     * @dev This shows the INCREASING obligation
     */
    function getBorrowBalance(address user, address asset) external view returns (uint256) {
        LendingPool storage pool = pools[asset];
        BorrowPosition storage position = borrowPositions[user][asset];
        return _getBorrowBalance(position, pool);
    }

    /**
     * @notice Get health factor for a position
     * @dev < 1.0 (10000) means liquidatable
     */
    function getHealthFactor(address user, address asset) external view returns (uint256) {
        LendingPool storage pool = pools[asset];
        BorrowPosition storage position = borrowPositions[user][asset];
        return _calculateHealth(position, pool);
    }

    /**
     * @notice Check if this system is Shariah-compliant
     * @dev NO - this implements riba (interest)
     */
    function isShariahCompliant() external pure returns (bool) {
        return false; // ⚠️ This uses INCREASING obligations (riba)
    }

    /**
     * @notice Get the monotonicity of obligations
     * @dev INCREASING - debt grows over time
     */
    function obligationDirection() external pure returns (Monotonicity) {
        return Monotonicity.INCREASING; // ⚠️ THE DEBT SPIRAL
    }

    /**
     * @notice Check if position has debt spiral risk
     * @dev Always true for increasing obligations
     */
    function hasDebtSpiralRisk() external pure returns (bool) {
        return true; // ⚠️ By construction
    }

    /**
     * @notice Project future debt
     * @dev Shows how debt GROWS over time
     */
    function projectDebt(
        address user,
        address asset,
        uint256 timeInSeconds
    ) external view returns (
        uint256 currentDebt,
        uint256 projectedDebt,
        uint256 interestAccrued
    ) {
        LendingPool storage pool = pools[asset];
        BorrowPosition storage position = borrowPositions[user][asset];

        currentDebt = _getBorrowBalance(position, pool);

        // Project forward
        uint256 interestMultiplier = (pool.borrowRate * timeInSeconds);
        projectedDebt = currentDebt + (currentDebt * interestMultiplier) / SCALE;
        interestAccrued = projectedDebt - currentDebt;
    }

    /**
     * @notice Compare with ethical alternative
     * @dev Returns data for AlchemicCredit comparison
     */
    function compareWithEthical(
        uint256 amount,
        uint256 timeInSeconds
    ) external view returns (
        uint256 compoundDebt,      // What you'd owe with Compound
        uint256 alchemicDebt,     // What you'd owe with Alchemic (0 eventually)
        uint256 difference,       // How much more you'd pay
        string memory verdict
    ) {
        // Assume 10% APR for Compound
        uint256 interestRate = (1000 * SCALE) / (10000 * SECONDS_PER_YEAR);
        uint256 interest = (amount * interestRate * timeInSeconds) / SCALE;
        compoundDebt = amount + interest;

        // Alchemic: debt decreases over time (assume 5% APY yield)
        uint256 yieldRate = (500 * SCALE) / (10000 * SECONDS_PER_YEAR);
        uint256 yieldEarned = (amount * yieldRate * timeInSeconds) / SCALE;
        alchemicDebt = yieldEarned >= amount ? 0 : amount - yieldEarned;

        difference = compoundDebt > alchemicDebt ? compoundDebt - alchemicDebt : 0;

        if (difference > amount / 2) {
            verdict = "COMPOUND COSTS 50%+ MORE - Consider AlchemicCredit";
        } else if (difference > 0) {
            verdict = "COMPOUND COSTS MORE - AlchemicCredit is better";
        } else {
            verdict = "Equivalent cost";
        }
    }
}

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                              FACTORY                                         ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

contract CompoundAdapterFactory {
    event AdapterCreated(address indexed adapter, address indexed oracle);

    function create(address oracle) external returns (address) {
        CompoundAdapter adapter = new CompoundAdapter(oracle);
        emit AdapterCreated(address(adapter), oracle);
        return address(adapter);
    }
}
