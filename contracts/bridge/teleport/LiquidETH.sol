// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBridgedToken} from "../../bridge/IBridgedToken.sol";

/**
 * @title LiquidETH
 * @author Lux Industries
 * @notice Liquid Vault for ETH with self-repaying LETH debt
 * @dev Part of the Liquid Protocol for self-repaying bridged asset loans
 *
 * Token Model:
 * - ETH: Bridged collateral token (minted by Teleporter)
 * - LETH: Liquid token (minted by this vault)
 *
 * Flow:
 * 1. User bridges ETH via Teleporter → receives ETH (collateral)
 * 2. User deposits ETH into this vault
 * 3. User borrows LETH against ETH collateral (up to 90% LTV)
 * 4. Yield from source chain auto-repays LETH debt
 *
 * E-Mode Parameters (highly correlated assets):
 * - LTV: 90% (can borrow 90% of collateral value)
 * - Liquidation Threshold: 94%
 * - Liquidation Bonus: 1%
 *
 * Invariants:
 * - Collateral: ETH (bridged)
 * - Debt: LETH (liquid token, minted by vault)
 * - Self-repaying: yield burns debt pro-rata
 * - Min backing: total ETH collateral >= total LETH debt
 */
contract LiquidETH is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // ROLES
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant LIQUID_YIELD_ROLE = keccak256("LIQUID_YIELD_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct Position {
        uint256 collateral;      // ETH deposited as collateral
        uint256 debt;            // LETH debt (borrowed liquid token)
        uint256 lastUpdate;      // Last position update timestamp
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - E-Mode Parameters
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice E-Mode LTV: 90% (9000 bps)
    uint256 public constant E_MODE_LTV = 9000;

    /// @notice Liquidation threshold: 94% (9400 bps)
    uint256 public constant LIQUIDATION_THRESHOLD = 9400;

    /// @notice Liquidation bonus: 1% (100 bps)
    uint256 public constant LIQUIDATION_BONUS = 100;

    /// @notice Minimum position size to prevent dust
    uint256 public constant MIN_POSITION_SIZE = 0.001 ether;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Collateral token (bridged ETH)
    IERC20 public immutable collateral;

    /// @notice Liquid token (LETH - minted by this vault)
    IBridgedToken public immutable liquidToken;

    /// @notice LiquidYield contract for yield notifications
    address public liquidYield;

    /// @notice User positions
    mapping(address => Position) public positions;

    /// @notice Total ETH collateral deposited
    uint256 public totalCollateral;

    /// @notice Total LETH debt outstanding
    uint256 public totalDebt;

    /// @notice Accumulated yield distributed (from LiquidYield)
    uint256 public accumulatedYield;

    /// @notice Yield index for pro-rata distribution
    uint256 public yieldIndex = 1e18; // Start at 1.0

    /// @notice User's yield index at last update
    mapping(address => uint256) public userYieldIndex;

    /// @notice Paused state
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, uint256 amount, uint256 newCollateral);
    event Borrowed(address indexed user, uint256 amount, uint256 newDebt);
    event Repaid(address indexed user, uint256 amount, uint256 newDebt);
    event Withdrawn(address indexed user, uint256 amount, uint256 newCollateral);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event YieldReceived(uint256 amount, uint256 newYieldIndex);
    event DebtRepaidByYield(address indexed user, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientCollateral();
    error InsufficientDebt();
    error ExceedsLTV();
    error NotLiquidatable();
    error VaultPaused();
    error PositionTooSmall();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenNotPaused() {
        if (paused) revert VaultPaused();
        _;
    }

    modifier updateYield(address user) {
        _updateUserYield(user);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize Liquid ETH vault
     * @param _collateral Bridged ETH token address
     * @param _liquidToken LETH liquid token address (must be mintable by this vault)
     */
    constructor(address _collateral, address _liquidToken) Ownable(msg.sender) {
        if (_collateral == address(0)) revert ZeroAddress();
        if (_liquidToken == address(0)) revert ZeroAddress();

        collateral = IERC20(_collateral);
        liquidToken = IBridgedToken(_liquidToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPOSIT / WITHDRAW (ETH Collateral)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit ETH as collateral
     * @param amount Amount of ETH to deposit
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused updateYield(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        // Transfer ETH collateral from user
        collateral.safeTransferFrom(msg.sender, address(this), amount);

        // Update position
        positions[msg.sender].collateral += amount;
        positions[msg.sender].lastUpdate = block.timestamp;
        totalCollateral += amount;

        emit Deposited(msg.sender, amount, positions[msg.sender].collateral);
    }

    /**
     * @notice Withdraw ETH collateral
     * @param amount Amount of ETH to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant whenNotPaused updateYield(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        Position storage position = positions[msg.sender];
        if (position.collateral < amount) revert InsufficientCollateral();

        // Check LTV after withdrawal
        uint256 newCollateral = position.collateral - amount;
        if (position.debt > 0) {
            uint256 maxDebt = newCollateral * E_MODE_LTV / BASIS_POINTS;
            if (position.debt > maxDebt) revert ExceedsLTV();
        }

        // Check minimum position size
        if (newCollateral > 0 && newCollateral < MIN_POSITION_SIZE) {
            revert PositionTooSmall();
        }

        // Update position
        position.collateral = newCollateral;
        position.lastUpdate = block.timestamp;
        totalCollateral -= amount;

        // Transfer ETH collateral to user
        collateral.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, position.collateral);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BORROW / REPAY (LETH Liquid Token)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Borrow LETH against ETH collateral
     * @param amount Amount of LETH to borrow (liquid token minted to user)
     */
    function borrow(uint256 amount) external nonReentrant whenNotPaused updateYield(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        Position storage position = positions[msg.sender];

        // Check LTV (ETH collateral vs LETH debt)
        uint256 maxDebt = position.collateral * E_MODE_LTV / BASIS_POINTS;
        uint256 newDebt = position.debt + amount;
        if (newDebt > maxDebt) revert ExceedsLTV();

        // Update position
        position.debt = newDebt;
        position.lastUpdate = block.timestamp;
        totalDebt += amount;

        // Mint LETH to user
        liquidToken.mint(msg.sender, amount);

        emit Borrowed(msg.sender, amount, position.debt);
    }

    /**
     * @notice Repay LETH debt
     * @param amount Amount of LETH to repay
     */
    function repay(uint256 amount) external nonReentrant whenNotPaused updateYield(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        Position storage position = positions[msg.sender];

        // Cap at actual debt
        uint256 repayAmount = amount > position.debt ? position.debt : amount;
        if (repayAmount == 0) revert InsufficientDebt();

        // Transfer LETH from user and burn it
        IERC20(address(liquidToken)).safeTransferFrom(msg.sender, address(this), repayAmount);
        liquidToken.burn(address(this), repayAmount);

        // Update position
        position.debt -= repayAmount;
        position.lastUpdate = block.timestamp;
        totalDebt -= repayAmount;

        emit Repaid(msg.sender, repayAmount, position.debt);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD NOTIFICATION (from LiquidYield / Teleporter)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive yield from Teleporter to reduce debt pro-rata
     * @param amount Amount of LETH received as yield
     * @param srcChainId Source chain ID (for tracking)
     * @dev Called by Teleporter's mintYield() or LiquidYield
     */
    function onYieldReceived(uint256 amount, uint256 srcChainId) external onlyRole(LIQUID_YIELD_ROLE) {
        if (amount == 0) return;
        if (totalDebt == 0) {
            // No debt to reduce - burn the yield
            liquidToken.burn(address(this), amount);
            return;
        }

        // Update global yield index
        // Each unit of debt gets (amount / totalDebt) reduction
        uint256 yieldPerDebt = amount * 1e18 / totalDebt;
        yieldIndex += yieldPerDebt;

        // Reduce total debt (yield burns debt)
        uint256 debtReduction = amount > totalDebt ? totalDebt : amount;
        totalDebt -= debtReduction;
        accumulatedYield += amount;

        // Burn the yield tokens
        liquidToken.burn(address(this), amount);

        emit YieldReceived(amount, yieldIndex);
    }

    /**
     * @notice Legacy yield notification (burns LETH to reduce debt)
     * @param amount Amount of LETH burned as yield
     * @dev Called by LiquidYield after burning LETH
     */
    function notifyYieldBurn(uint256 amount) external onlyRole(LIQUID_YIELD_ROLE) {
        if (amount == 0) return;
        if (totalDebt == 0) return;

        // Update global yield index
        uint256 yieldPerDebt = amount * 1e18 / totalDebt;
        yieldIndex += yieldPerDebt;

        // Reduce total debt
        uint256 debtReduction = amount > totalDebt ? totalDebt : amount;
        totalDebt -= debtReduction;
        accumulatedYield += amount;

        emit YieldReceived(amount, yieldIndex);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position to liquidate
     * @param debtToCover Amount of LETH debt to cover
     */
    function liquidate(
        address user,
        uint256 debtToCover
    ) external nonReentrant whenNotPaused updateYield(user) {
        Position storage position = positions[user];

        // Check if liquidatable
        if (!isLiquidatable(user)) revert NotLiquidatable();

        // Cap at actual debt
        uint256 actualDebtCover = debtToCover > position.debt ? position.debt : debtToCover;

        // Calculate ETH collateral to seize (debt value + bonus)
        uint256 collateralToSeize = actualDebtCover * (BASIS_POINTS + LIQUIDATION_BONUS) / BASIS_POINTS;
        if (collateralToSeize > position.collateral) {
            collateralToSeize = position.collateral;
        }

        // Transfer LETH payment from liquidator and burn
        IERC20(address(liquidToken)).safeTransferFrom(msg.sender, address(this), actualDebtCover);
        liquidToken.burn(address(this), actualDebtCover);

        // Update position
        position.debt -= actualDebtCover;
        position.collateral -= collateralToSeize;
        position.lastUpdate = block.timestamp;

        totalDebt -= actualDebtCover;
        totalCollateral -= collateralToSeize;

        // Transfer ETH collateral to liquidator
        collateral.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(user, msg.sender, actualDebtCover, collateralToSeize);
    }

    /**
     * @notice Check if a position is liquidatable
     * @param user Address to check
     * @return True if position can be liquidated
     */
    function isLiquidatable(address user) public view returns (bool) {
        Position memory position = positions[user];
        if (position.debt == 0) return false;

        // Calculate effective debt after yield
        uint256 effectiveDebt = _getEffectiveDebt(user);

        // Liquidatable if debt > liquidation threshold
        uint256 maxDebt = position.collateral * LIQUIDATION_THRESHOLD / BASIS_POINTS;
        return effectiveDebt > maxDebt;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get position details
     * @param user Address to query
     * @return ethCollateral ETH collateral amount
     * @return lethDebt LETH debt amount
     * @return effectiveDebt Debt after pending yield
     * @return healthFactor Position health (>1e4 is healthy)
     * @return availableToBorrow Additional LETH available to borrow
     */
    function getPosition(address user) external view returns (
        uint256 ethCollateral,
        uint256 lethDebt,
        uint256 effectiveDebt,
        uint256 healthFactor,
        uint256 availableToBorrow
    ) {
        Position memory position = positions[user];
        ethCollateral = position.collateral;
        lethDebt = position.debt;
        effectiveDebt = _getEffectiveDebt(user);

        if (effectiveDebt == 0) {
            healthFactor = type(uint256).max;
        } else {
            healthFactor = ethCollateral * LIQUIDATION_THRESHOLD / effectiveDebt;
        }

        uint256 maxDebt = ethCollateral * E_MODE_LTV / BASIS_POINTS;
        availableToBorrow = maxDebt > effectiveDebt ? maxDebt - effectiveDebt : 0;
    }

    /**
     * @notice Get user's current LTV
     */
    function getCurrentLTV(address user) external view returns (uint256) {
        Position memory position = positions[user];
        if (position.collateral == 0) return 0;
        uint256 effectiveDebt = _getEffectiveDebt(user);
        return effectiveDebt * BASIS_POINTS / position.collateral;
    }

    /**
     * @notice Get user's health factor
     */
    function getHealthFactor(address user) external view returns (uint256) {
        Position memory position = positions[user];
        uint256 effectiveDebt = _getEffectiveDebt(user);
        if (effectiveDebt == 0) return type(uint256).max;
        return position.collateral * LIQUIDATION_THRESHOLD / effectiveDebt;
    }

    /**
     * @notice Get vault utilization
     */
    function getUtilization() external view returns (uint256) {
        if (totalCollateral == 0) return 0;
        return totalDebt * BASIS_POINTS / totalCollateral;
    }

    /**
     * @notice Get total yield distributed
     */
    function getTotalYieldDistributed() external view returns (uint256) {
        return accumulatedYield;
    }

    /**
     * @notice Get collateral token (ETH)
     */
    function getCollateralToken() external view returns (address) {
        return address(collateral);
    }

    /**
     * @notice Get liquid token (LETH)
     */
    function getLiquidToken() external view returns (address) {
        return address(liquidToken);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set LiquidYield address
     */
    function setLiquidYield(address _liquidYield) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_liquidYield == address(0)) revert ZeroAddress();
        liquidYield = _liquidYield;
        _grantRole(LIQUID_YIELD_ROLE, _liquidYield);
    }

    /**
     * @notice Grant yield role (for Teleporter to send yield)
     */
    function grantYieldRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LIQUID_YIELD_ROLE, account);
    }

    /**
     * @notice Set paused state
     */
    function setPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = _paused;
    }

    /**
     * @notice Grant liquidator role
     */
    function grantLiquidator(address liquidator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(LIQUIDATOR_ROLE, liquidator);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update user's yield and reduce their debt
     */
    function _updateUserYield(address user) internal {
        Position storage position = positions[user];
        if (position.debt == 0) {
            userYieldIndex[user] = yieldIndex;
            return;
        }

        uint256 userIndex = userYieldIndex[user];
        if (userIndex == 0) userIndex = 1e18; // Initialize

        if (yieldIndex > userIndex) {
            // Calculate yield share for this user
            uint256 indexDelta = yieldIndex - userIndex;
            uint256 yieldShare = position.debt * indexDelta / 1e18;

            // Reduce user's debt by their yield share
            if (yieldShare > 0) {
                uint256 debtReduction = yieldShare > position.debt ? position.debt : yieldShare;
                position.debt -= debtReduction;
                emit DebtRepaidByYield(user, debtReduction);
            }
        }

        userYieldIndex[user] = yieldIndex;
    }

    /**
     * @notice Get user's effective debt (after pending yield)
     */
    function _getEffectiveDebt(address user) internal view returns (uint256) {
        Position memory position = positions[user];
        if (position.debt == 0) return 0;

        uint256 userIndex = userYieldIndex[user];
        if (userIndex == 0) userIndex = 1e18;

        if (yieldIndex > userIndex) {
            uint256 indexDelta = yieldIndex - userIndex;
            uint256 yieldShare = position.debt * indexDelta / 1e18;

            if (yieldShare >= position.debt) return 0;
            return position.debt - yieldShare;
        }

        return position.debt;
    }
}
