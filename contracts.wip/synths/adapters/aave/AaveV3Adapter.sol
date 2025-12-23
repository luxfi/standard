// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IERC20} from "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import {SafeERC20} from "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";

import {IllegalState} from "../../base/Errors.sol";
import {IYieldAdapter, ILendingAdapter} from "../IYieldAdapter.sol";
import "../../libraries/TokenUtils.sol";

/// @title IAavePool
/// @notice Minimal interface for Aave V3 Pool
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );
}

/// @title IAToken
/// @notice Minimal interface for Aave aTokens
interface IAToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function scaledBalanceOf(address user) external view returns (uint256);
}

/// @title AaveV3Adapter
/// @notice Yield adapter for Aave V3 lending protocol
/// @dev Allows depositing assets to earn yield and optionally borrowing against collateral
/// @custom:security-contact security@lux.network
contract AaveV3Adapter is ILendingAdapter {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    string public constant override version = "1.0.0";
    string public constant override protocol = "Aave V3";
    
    /// @notice Variable interest rate mode
    uint256 constant VARIABLE_RATE = 2;
    
    /// @notice Referral code for Lux
    uint16 constant REFERRAL_CODE = 0;
    
    /// @notice Basis points denominator
    uint256 constant BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Aave V3 Pool
    IAavePool public immutable pool;
    
    /// @notice aToken (yield-bearing token)
    address public immutable override token;
    
    /// @notice Underlying asset
    address public immutable override underlyingToken;
    
    /// @notice Chain ID
    uint256 public immutable override chainId;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Active status
    bool public override isActive = true;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Harvested(uint256 rewards);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address _pool, address _aToken, address _underlyingToken) {
        pool = IAavePool(_pool);
        token = _aToken;
        underlyingToken = _underlyingToken;
        chainId = block.chainid;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    function price() external view override returns (uint256) {
        // aTokens maintain 1:1 with underlying, yield is reflected in balance growth
        return 1e18;
    }

    /// @inheritdoc IYieldAdapter
    function apy() external view override returns (uint256) {
        (, uint128 currentLiquidityRate,,,,,,,,,,,,,) = pool.getReserveData(underlyingToken);
        // Aave rates are in ray (27 decimals), convert to bps
        return uint256(currentLiquidityRate) / 1e23; // ray to bps
    }

    /// @inheritdoc IYieldAdapter
    function tvl() external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IYieldAdapter
    function availableLiquidity() external view override returns (uint256) {
        return IERC20(underlyingToken).balanceOf(token);
    }

    /// @inheritdoc ILendingAdapter
    function maxLTV() external view override returns (uint256) {
        (,,, uint256 currentLiquidationThreshold, uint256 ltv,) = pool.getUserAccountData(address(this));
        return ltv; // Already in bps
    }

    /// @inheritdoc ILendingAdapter
    function borrowRate() external view override returns (uint256) {
        (,,,, uint128 variableBorrowRate,,,,,,,,,,) = pool.getReserveData(underlyingToken);
        return uint256(variableBorrowRate) / 1e23; // ray to bps
    }

    /// @inheritdoc ILendingAdapter
    function supplyRate() external view override returns (uint256) {
        (, uint128 currentLiquidityRate,,,,,,,,,,,,,) = pool.getReserveData(underlyingToken);
        return uint256(currentLiquidityRate) / 1e23;
    }

    /// @inheritdoc ILendingAdapter
    function utilizationRate() external view override returns (uint256) {
        // Calculate utilization from supply/borrow
        uint256 totalSupply = IERC20(token).totalSupply();
        uint256 totalBorrow = IERC20(underlyingToken).balanceOf(token);
        if (totalSupply == 0) return 0;
        return ((totalSupply - totalBorrow) * BPS) / totalSupply;
    }

    /// @inheritdoc ILendingAdapter
    function borrowedAmount(address user) external view override returns (uint256) {
        (,uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);
        return totalDebtBase;
    }

    /// @inheritdoc ILendingAdapter
    function collateralValue(address user) external view override returns (uint256) {
        (uint256 totalCollateralBase,,,,,) = pool.getUserAccountData(user);
        return totalCollateralBase;
    }

    /// @inheritdoc ILendingAdapter
    function healthFactor(address user) external view override returns (uint256) {
        (,,,,,uint256 hf) = pool.getUserAccountData(user);
        return hf;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATIVE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IYieldAdapter
    function wrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, address(pool), amount);
        
        uint256 balanceBefore = IERC20(token).balanceOf(recipient);
        pool.supply(underlyingToken, amount, recipient, REFERRAL_CODE);
        uint256 shares = IERC20(token).balanceOf(recipient) - balanceBefore;
        
        emit Deposited(msg.sender, amount, shares);
        return shares;
    }

    /// @inheritdoc IYieldAdapter
    function unwrap(uint256 amount, address recipient) external override returns (uint256) {
        TokenUtils.safeTransferFrom(token, msg.sender, address(this), amount);
        
        uint256 balanceBefore = IERC20(underlyingToken).balanceOf(recipient);
        uint256 withdrawn = pool.withdraw(underlyingToken, amount, recipient);
        uint256 balanceAfter = IERC20(underlyingToken).balanceOf(recipient);
        
        if (balanceAfter - balanceBefore != withdrawn) {
            revert IllegalState();
        }
        
        emit Withdrawn(msg.sender, amount, withdrawn);
        return withdrawn;
    }

    /// @inheritdoc IYieldAdapter
    function harvest() external override returns (uint256) {
        // Aave automatically accrues yield to aToken balance
        // No explicit harvest needed, return 0
        emit Harvested(0);
        return 0;
    }

    /// @inheritdoc ILendingAdapter
    function borrow(uint256 amount, address recipient) external override {
        pool.borrow(underlyingToken, amount, VARIABLE_RATE, REFERRAL_CODE, msg.sender);
        TokenUtils.safeTransfer(underlyingToken, recipient, amount);
        emit Borrowed(msg.sender, amount);
    }

    /// @inheritdoc ILendingAdapter
    function repay(uint256 amount) external override {
        TokenUtils.safeTransferFrom(underlyingToken, msg.sender, address(this), amount);
        TokenUtils.safeApprove(underlyingToken, address(pool), amount);
        pool.repay(underlyingToken, amount, VARIABLE_RATE, msg.sender);
        emit Repaid(msg.sender, amount);
    }
}
