// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.

pragma solidity ^0.8.31;

/// @title Pool Info
/// @notice Liquidity pool metadata
struct PoolInfo {
    address pool;             // Pool address
    address[] tokens;         // Tokens in the pool
    uint256[] reserves;       // Current reserves
    uint256 totalSupply;      // Total LP token supply
    uint256 fee;              // Trading fee (1e6 = 100%)
    uint8 poolType;           // 0=AMM, 1=Stable, 2=Concentrated, 3=Lending
    bool isActive;            // Pool is active
}

/// @title Add Liquidity Parameters
struct AddLiquidityParams {
    address pool;             // Target pool
    address[] tokens;         // Tokens to deposit
    uint256[] amounts;        // Amounts to deposit
    uint256 minLpAmount;      // Minimum LP tokens to receive
    address recipient;        // LP token recipient
}

/// @title Remove Liquidity Parameters
struct RemoveLiquidityParams {
    address pool;             // Target pool
    uint256 lpAmount;         // LP tokens to burn
    uint256[] minAmounts;     // Minimum tokens to receive
    address recipient;        // Token recipient
}

/// @title Single Asset Parameters
struct SingleAssetParams {
    address pool;             // Target pool
    address tokenIn;          // Token to deposit
    uint256 amountIn;         // Amount to deposit
    uint256 minLpAmount;      // Minimum LP tokens to receive
    address recipient;        // LP token recipient
}

/// @title Swap Parameters
struct SwapParams {
    address pool;             // Pool to swap through
    address tokenIn;          // Input token
    address tokenOut;         // Output token
    uint256 amountIn;         // Input amount
    uint256 minAmountOut;     // Minimum output (slippage protection)
    address recipient;        // Output recipient
}

/// @title ILiquidityAdapter
/// @author Lux Industries Inc.
/// @notice Standard interface for liquidity pool adapters
/// @dev Implement for Uniswap, Curve, Balancer, Aave, Compound, etc.
interface ILiquidityAdapter {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event LiquidityAdded(
        address indexed pool,
        address indexed provider,
        uint256[] amounts,
        uint256 lpMinted
    );

    event LiquidityRemoved(
        address indexed pool,
        address indexed provider,
        uint256 lpBurned,
        uint256[] amounts
    );

    event Swapped(
        address indexed pool,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /*//////////////////////////////////////////////////////////////
                              METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the adapter version
    function version() external view returns (string memory);

    /// @notice Returns the name of the underlying protocol
    function protocol() external view returns (string memory);

    /// @notice Returns the chain ID
    function chainId() external view returns (uint256);

    /// @notice Returns the core router contract
    function router() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                             POOL INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns list of supported pools
    function supportedPools() external view returns (address[] memory);

    /// @notice Get pool information
    function getPoolInfo(address pool) external view returns (PoolInfo memory);

    /// @notice Check if pool is supported
    function isPoolSupported(address pool) external view returns (bool);

    /// @notice Get the LP token address for a pool
    function getLpToken(address pool) external view returns (address);

    /// @notice Get current APY/APR for a pool
    /// @return apy Annual percentage yield (1e18 = 100%)
    function getApy(address pool) external view returns (uint256 apy);

    /// @notice Get TVL for a pool
    /// @return tvl Total value locked in USD (1e18 precision)
    function getTvl(address pool) external view returns (uint256 tvl);

    /*//////////////////////////////////////////////////////////////
                         LIQUIDITY OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add liquidity to a pool (balanced)
    /// @param params Add liquidity parameters
    /// @return lpAmount LP tokens minted
    function addLiquidity(AddLiquidityParams calldata params)
        external
        payable
        returns (uint256 lpAmount);

    /// @notice Add liquidity with a single asset
    /// @param params Single asset parameters
    /// @return lpAmount LP tokens minted
    function addLiquiditySingleAsset(SingleAssetParams calldata params)
        external
        payable
        returns (uint256 lpAmount);

    /// @notice Remove liquidity from a pool
    /// @param params Remove liquidity parameters
    /// @return amounts Tokens received
    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        returns (uint256[] memory amounts);

    /// @notice Remove liquidity to a single asset
    /// @param pool Target pool
    /// @param lpAmount LP tokens to burn
    /// @param tokenOut Desired output token
    /// @param minAmountOut Minimum output amount
    /// @param recipient Output recipient
    /// @return amountOut Token amount received
    function removeLiquiditySingleAsset(
        address pool,
        uint256 lpAmount,
        address tokenOut,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                           SWAP OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap tokens through a pool
    /// @param params Swap parameters
    /// @return amountOut Tokens received
    function swap(SwapParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    /// @notice Get swap quote
    /// @param pool Pool address
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @return amountOut Expected output amount
    /// @return fee Trading fee amount
    function getSwapQuote(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 fee);

    /*//////////////////////////////////////////////////////////////
                             ESTIMATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Estimate LP tokens for adding liquidity
    function estimateLpTokens(
        address pool,
        uint256[] calldata amounts
    ) external view returns (uint256 lpAmount);

    /// @notice Estimate tokens for removing liquidity
    function estimateRemoval(
        address pool,
        uint256 lpAmount
    ) external view returns (uint256[] memory amounts);
}
