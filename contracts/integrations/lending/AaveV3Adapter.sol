// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityEngine} from "@luxfi/contracts/interfaces/liquidity/ILiquidityEngine.sol";

/// @title Aave V3 Pool Interface
interface IPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);

    function getUserAccountData(address user)
        external view returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function getReserveData(address asset)
        external view returns (ReserveData memory);

    struct ReserveData {
        uint256 configuration;
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

/// @title Aave V3 Pool Addresses Provider
interface IPoolAddressesProvider {
    function getPool() external view returns (address);
    function getPriceOracle() external view returns (address);
}

/// @title AaveV3Adapter
/// @notice Adapter for Aave V3 lending protocol
contract AaveV3Adapter is ILiquidityEngine {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Mainnet addresses
    IPoolAddressesProvider public constant ADDRESSES_PROVIDER =
        IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);

    uint16 public constant REFERRAL_CODE = 0;

    Chain public immutable CHAIN;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(Chain _chain) {
        CHAIN = _chain;
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getSwapQuote(address, address, uint256)
        external pure override returns (SwapQuote memory)
    {
        revert("Not a DEX");
    }

    function swap(address, address, uint256, uint256, address, uint256)
        external payable override returns (uint256)
    {
        revert("Not a DEX");
    }

    function swapWithRoute(bytes calldata, uint256, uint256, address, uint256)
        external payable override returns (uint256)
    {
        revert("Not a DEX");
    }

    /*//////////////////////////////////////////////////////////////
                         LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(address, uint256, uint256, uint256, uint256, address, uint256)
        external pure override returns (uint256)
    {
        revert("Use supply() for Aave");
    }

    function removeLiquidity(address, uint256, uint256, uint256, address, uint256)
        external pure override returns (uint256, uint256)
    {
        revert("Use withdraw() for Aave");
    }

    function getPoolInfo(address) external pure override returns (PoolInfo memory) {
        revert("Not applicable for lending");
    }

    /*//////////////////////////////////////////////////////////////
                          LENDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getLendingQuote(
        address token,
        uint256 amount,
        bool isSupply
    ) external view override returns (LendingQuote memory quote) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        IPool.ReserveData memory reserveData = pool.getReserveData(token);

        uint256 apy;
        if (isSupply) {
            // currentLiquidityRate is in ray (1e27)
            apy = uint256(reserveData.currentLiquidityRate) * 1e18 / 1e27;
        } else {
            apy = uint256(reserveData.currentVariableBorrowRate) * 1e18 / 1e27;
        }

        quote = LendingQuote({
            token: token,
            amount: amount,
            apy: apy,
            utilizationRate: _calculateUtilization(reserveData),
            ltv: 8000, // 80% default, should read from config
            liquidationThreshold: 8500 // 85% default
        });
    }

    function supply(
        address token,
        uint256 amount,
        address onBehalfOf
    ) external override returns (uint256 shares) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        IPool.ReserveData memory reserveData = pool.getReserveData(token);

        // Transfer tokens from sender
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).forceApprove(address(pool), amount);

        // Get aToken balance before
        uint256 aTokenBefore = IERC20(reserveData.aTokenAddress).balanceOf(onBehalfOf);

        // Supply to Aave
        pool.supply(token, amount, onBehalfOf, REFERRAL_CODE);

        // Calculate shares (aTokens minted)
        shares = IERC20(reserveData.aTokenAddress).balanceOf(onBehalfOf) - aTokenBefore;

        emit Supplied(onBehalfOf, token, amount, "AAVE_V3");
    }

    function withdraw(
        address token,
        uint256 amount,
        address recipient
    ) external override returns (uint256 withdrawn) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());

        // Withdraw from Aave (caller must have approved aTokens)
        withdrawn = pool.withdraw(token, amount, recipient);
    }

    function borrow(
        address token,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external override {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());

        pool.borrow(token, amount, rateMode, REFERRAL_CODE, onBehalfOf);

        emit Borrowed(onBehalfOf, token, amount, "AAVE_V3");
    }

    function repay(
        address token,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external override returns (uint256 repaid) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).forceApprove(address(pool), amount);

        repaid = pool.repay(token, amount, rateMode, onBehalfOf);
    }

    /*//////////////////////////////////////////////////////////////
                         AAVE-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get user account data
    function getUserData(address user) external view returns (
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 availableBorrows,
        uint256 liquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        return pool.getUserAccountData(user);
    }

    /// @notice Get reserve data
    function getReserveData(address asset)
        external view returns (IPool.ReserveData memory)
    {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        return pool.getReserveData(asset);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function protocolName() external pure override returns (string memory) {
        return "Aave V3";
    }

    function protocolType() external pure override returns (ProtocolType) {
        return ProtocolType.LENDING;
    }

    function chain() external view override returns (Chain) {
        return CHAIN;
    }

    function isTokenSupported(address token) external view override returns (bool) {
        try IPool(ADDRESSES_PROVIDER.getPool()).getReserveData(token)
            returns (IPool.ReserveData memory data)
        {
            return data.aTokenAddress != address(0);
        } catch {
            return false;
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _calculateUtilization(IPool.ReserveData memory data)
        internal pure returns (uint256)
    {
        // Simplified - would calculate from indices
        return 0;
    }
}
