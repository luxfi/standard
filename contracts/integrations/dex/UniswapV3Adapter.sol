// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityEngine} from "@luxfi/contracts/interfaces/liquidity/ILiquidityEngine.sol";

/// @title Uniswap V3 Router Interface
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external payable returns (uint256 amountOut);

    function exactInput(ExactInputParams calldata params)
        external payable returns (uint256 amountOut);
}

/// @title Uniswap V3 Quoter Interface
interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );
}

/// @title UniswapV3Adapter
/// @notice Adapter for Uniswap V3 swaps and liquidity
contract UniswapV3Adapter is ILiquidityEngine {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Ethereum Mainnet
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoterV2 public constant QUOTER = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    // Fee tiers
    uint24 public constant FEE_LOWEST = 100;    // 0.01%
    uint24 public constant FEE_LOW = 500;       // 0.05%
    uint24 public constant FEE_MEDIUM = 3000;   // 0.30%
    uint24 public constant FEE_HIGH = 10000;    // 1.00%

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

    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (SwapQuote memory quote) {
        // Try each fee tier and find best output
        uint24[4] memory fees = [FEE_LOWEST, FEE_LOW, FEE_MEDIUM, FEE_HIGH];
        uint256 bestAmountOut = 0;
        uint24 bestFee = FEE_MEDIUM;
        uint256 gasEstimate = 0;

        for (uint256 i = 0; i < fees.length; i++) {
            try QUOTER.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: fees[i],
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountOut, uint160, uint32, uint256 gas) {
                if (amountOut > bestAmountOut) {
                    bestAmountOut = amountOut;
                    bestFee = fees[i];
                    gasEstimate = gas;
                }
            } catch {}
        }

        quote = SwapQuote({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: bestAmountOut,
            priceImpact: _calculatePriceImpact(amountIn, bestAmountOut, tokenIn, tokenOut),
            gasEstimate: gasEstimate,
            route: abi.encode(bestFee),
            validUntil: block.timestamp + 60
        });
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable override returns (uint256 amountOut) {
        // Transfer tokens
        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);
        }

        // Use medium fee as default (most common)
        amountOut = ROUTER.exactInputSingle{value: msg.value}(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: FEE_MEDIUM,
                recipient: recipient,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut, "UNISWAP_V3");
    }

    function swapWithRoute(
        bytes calldata route,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable override returns (uint256 amountOut) {
        // Decode fee from route
        uint24 fee = abi.decode(route, (uint24));

        // Get tokens from route
        (address tokenIn, address tokenOut) = _decodeTokensFromRoute(route);

        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);
        }

        amountOut = ROUTER.exactInputSingle{value: msg.value}(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: recipient,
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                         LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(
        address pool,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external override returns (uint256 liquidity) {
        // V3 uses NFT positions - simplified implementation
        revert("Use NonfungiblePositionManager");
    }

    function removeLiquidity(
        address pool,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external override returns (uint256 amount0, uint256 amount1) {
        revert("Use NonfungiblePositionManager");
    }

    function getPoolInfo(address pool) external view override returns (PoolInfo memory) {
        // Would query pool contract
        return PoolInfo({
            pool: pool,
            token0: address(0),
            token1: address(0),
            reserve0: 0,
            reserve1: 0,
            fee: 0,
            tvl: 0,
            volume24h: 0
        });
    }

    /*//////////////////////////////////////////////////////////////
                          LENDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getLendingQuote(address, uint256, bool)
        external pure override returns (LendingQuote memory)
    {
        revert("Not a lending protocol");
    }

    function supply(address, uint256, address)
        external pure override returns (uint256)
    {
        revert("Not a lending protocol");
    }

    function withdraw(address, uint256, address)
        external pure override returns (uint256)
    {
        revert("Not a lending protocol");
    }

    function borrow(address, uint256, uint256, address) external pure override {
        revert("Not a lending protocol");
    }

    function repay(address, uint256, uint256, address)
        external pure override returns (uint256)
    {
        revert("Not a lending protocol");
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function protocolName() external pure override returns (string memory) {
        return "Uniswap V3";
    }

    function protocolType() external pure override returns (ProtocolType) {
        return ProtocolType.DEX_AMM;
    }

    function chain() external view override returns (Chain) {
        return CHAIN;
    }

    function isTokenSupported(address) external pure override returns (bool) {
        return true; // Uniswap supports all ERC20s
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _calculatePriceImpact(
        uint256 amountIn,
        uint256 amountOut,
        address tokenIn,
        address tokenOut
    ) internal pure returns (uint256) {
        // Simplified price impact calculation
        // In production, compare to oracle price
        return 0;
    }

    function _decodeTokensFromRoute(bytes calldata route)
        internal pure returns (address tokenIn, address tokenOut)
    {
        // Simplified - would decode full path
        return (address(0), address(0));
    }

    receive() external payable {}
}
