// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

/**
 * @title CurveStrategy
 * @notice Yield strategy for Curve Finance pools
 * @dev Supports multiple pool types: 3pool, stETH/ETH, tricrypto, etc.
 *
 * Curve pools earn:
 * - Trading fees (0.04% per swap)
 * - CRV emissions (if gauge staked)
 * - Convex boost (if using Convex)
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Curve Pool interface
interface ICurvePool {
    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external returns (uint256);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_amount) external returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
}

/// @notice Curve Gauge interface
interface ICurveGauge {
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
    function claim_rewards() external;
    function balanceOf(address _addr) external view returns (uint256);
    function claimable_reward(address _addr, address _token) external view returns (uint256);
}

/// @notice Curve 3pool addresses (Ethereum mainnet)
contract CurveStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Curve 3pool (DAI/USDC/USDT)
    address public constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    /// @notice 3CRV LP token
    address public constant CRV_3POOL = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;

    /// @notice Curve 3pool gauge
    address public constant GAUGE_3POOL = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;

    /// @notice CRV token
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Pool coins
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Curve pool address
    address public immutable pool;

    /// @notice LP token address
    address public immutable lpToken;

    /// @notice Gauge address (for CRV rewards)
    address public immutable gauge;

    /// @notice Underlying asset (DAI, USDC, or USDT)
    address public immutable underlyingAsset;

    /// @notice Coin index in pool (0=DAI, 1=USDC, 2=USDT)
    int128 public immutable coinIndex;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total LP tokens deposited
    uint256 public totalLpTokens;

    /// @notice Total deposited (for IYieldStrategy interface)
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Strategy name
    string public name;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 assetAmount, uint256 lpReceived);
    event Withdrawn(uint256 lpAmount, uint256 assetReceived);
    event RewardsHarvested(uint256 crvAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "CurveStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _vault,
        address _pool,
        address _lpToken,
        address _gauge,
        address _asset,
        int128 _coinIndex,
        string memory _name
    ) Ownable(msg.sender) {
        vault = _vault;
        pool = _pool;
        lpToken = _lpToken;
        gauge = _gauge;
        underlyingAsset = _asset;
        coinIndex = _coinIndex;
        name = _name;

        // Approve pool to spend asset
        IERC20(_asset).approve(_pool, type(uint256).max);
        // Approve gauge to spend LP token
        IERC20(_lpToken).approve(_gauge, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        require(active, "CurveStrategy: not active");

        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Prepare amounts array (only our coin has value)
        uint256[3] memory amounts;
        amounts[uint256(int256(coinIndex))] = amount;

        // Add liquidity to Curve
        uint256 lpBefore = IERC20(lpToken).balanceOf(address(this));
        ICurvePool(pool).add_liquidity(amounts, 0);
        uint256 lpAfter = IERC20(lpToken).balanceOf(address(this));
        shares = lpAfter - lpBefore;

        // Stake in gauge for CRV rewards
        ICurveGauge(gauge).deposit(shares);
        totalLpTokens += shares;
        totalDeposited += amount;

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        require(shares <= totalLpTokens, "CurveStrategy: insufficient LP");

        // Withdraw from gauge
        ICurveGauge(gauge).withdraw(shares);
        totalLpTokens -= shares;

        // Remove liquidity from Curve (single coin)
        amount = ICurvePool(pool).remove_liquidity_one_coin(shares, coinIndex, 0);

        // Track deposited amount
        if (totalDeposited >= amount) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }

        // Transfer to recipient
        IERC20(underlyingAsset).safeTransfer(vault, amount);

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // Claim CRV rewards
        ICurveGauge(gauge).claim_rewards();

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance > 0) {
            // Transfer CRV to vault (vault can sell or compound)
            IERC20(CRV).safeTransfer(vault, crvBalance);
            harvested = crvBalance;
            emit RewardsHarvested(crvBalance);
        }
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        // Calculate LP value in underlying terms
        uint256 virtualPrice = ICurvePool(pool).get_virtual_price();
        return (totalLpTokens * virtualPrice) / 1e18;
    }

    /// @notice
    function currentAPY() external pure returns (uint256) {
        // Curve 3pool typically yields 2-5%
        return 350; // 3.5% in basis points
    }

    /// @notice
    function asset() external view returns (address) {
        return underlyingAsset;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
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
}

// ═══════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title Curve3poolUSDCStrategy
 * @notice Curve 3pool strategy for USDC
 */
contract Curve3poolUSDCStrategy is CurveStrategy {
    constructor(address _vault) CurveStrategy(
        _vault,
        0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3pool
        0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490, // 3CRV
        0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A, // gauge
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        1, // USDC index
        "Curve 3pool USDC Strategy"
    ) {}
}

/**
 * @title Curve3poolDAIStrategy
 * @notice Curve 3pool strategy for DAI
 */
contract Curve3poolDAIStrategy is CurveStrategy {
    constructor(address _vault) CurveStrategy(
        _vault,
        0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3pool
        0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490, // 3CRV
        0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A, // gauge
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0, // DAI index
        "Curve 3pool DAI Strategy"
    ) {}
}
