// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

/// @title ILiquidityEngine
/// @notice Universal interface for cross-chain liquidity aggregation
/// @dev All adapters must implement this interface for unified access
interface ILiquidityEngine {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Supported chains
    enum Chain {
        ETHEREUM,       // 1
        BSC,            // 56
        ARBITRUM,       // 42161
        BASE,           // 8453
        POLYGON,        // 137
        OPTIMISM,       // 10
        AVALANCHE,      // 43114
        LUX_CCHAIN,     // 96369
        LUX_HANZO,      // TBD
        LUX_ZOO,        // TBD
        SOLANA,         // Non-EVM
        TON             // Non-EVM
    }

    /// @notice Protocol types
    enum ProtocolType {
        DEX_AMM,        // Uniswap, Raydium, STON.fi
        DEX_ORDERBOOK,  // dYdX, Serum
        DEX_AGGREGATOR, // 1inch, Jupiter
        LENDING,        // Aave, Compound, Solend
        PERPS,          // GMX, Aster
        STAKING,        // Lido, Marinade
        BRIDGE          // Warp, Wormhole
    }

    /// @notice Swap quote
    struct SwapQuote {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 priceImpact;    // basis points
        uint256 gasEstimate;
        bytes route;            // encoded route data
        uint256 validUntil;
    }

    /// @notice Supply/Borrow quote for lending
    struct LendingQuote {
        address token;
        uint256 amount;
        uint256 apy;            // annual percentage yield (1e18 = 100%)
        uint256 utilizationRate;
        uint256 ltv;            // loan-to-value ratio
        uint256 liquidationThreshold;
    }

    /// @notice Liquidity pool info
    struct PoolInfo {
        address pool;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 fee;            // basis points
        uint256 tvl;
        uint256 volume24h;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Swap(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 protocol
    );

    event LiquidityAdded(
        address indexed user,
        address indexed pool,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event LiquidityRemoved(
        address indexed user,
        address indexed pool,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    event Supplied(
        address indexed user,
        address indexed token,
        uint256 amount,
        bytes32 protocol
    );

    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 amount,
        bytes32 protocol
    );

    /*//////////////////////////////////////////////////////////////
                              SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get best swap quote across all protocols
    /// @dev Some protocols (e.g., Uniswap Quoter) require state simulation
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (SwapQuote memory quote);

    /// @notice Execute swap with best route
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    /// @notice Execute swap with specific route
    function swapWithRoute(
        bytes calldata route,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                           LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add liquidity to a pool
    function addLiquidity(
        address pool,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external returns (uint256 liquidity);

    /// @notice Remove liquidity from a pool
    function removeLiquidity(
        address pool,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Get pool information
    function getPoolInfo(address pool) external view returns (PoolInfo memory);

    /*//////////////////////////////////////////////////////////////
                            LENDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get lending quote
    function getLendingQuote(
        address token,
        uint256 amount,
        bool isSupply
    ) external view returns (LendingQuote memory quote);

    /// @notice Supply tokens to lending protocol
    function supply(
        address token,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256 shares);

    /// @notice Withdraw tokens from lending protocol
    function withdraw(
        address token,
        uint256 amount,
        address recipient
    ) external returns (uint256 withdrawn);

    /// @notice Borrow tokens from lending protocol
    function borrow(
        address token,
        uint256 amount,
        uint256 rateMode, // 1 = stable, 2 = variable
        address onBehalfOf
    ) external;

    /// @notice Repay borrowed tokens
    function repay(
        address token,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256 repaid);

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get protocol name
    function protocolName() external view returns (string memory);

    /// @notice Get protocol type
    function protocolType() external view returns (ProtocolType);

    /// @notice Get supported chain
    function chain() external view returns (Chain);

    /// @notice Check if token is supported
    function isTokenSupported(address token) external view returns (bool);
}
