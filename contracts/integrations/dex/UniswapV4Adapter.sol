// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityEngine} from "@luxfi/contracts/interfaces/liquidity/ILiquidityEngine.sol";

/// @title Uniswap V4 Pool Manager Interface
/// @notice Singleton contract that holds all V4 pools
interface IPoolManager {
    /// @notice Pool key identifying a unique pool
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    /// @notice Swap parameters
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Initialize a new pool
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice Swap tokens in a pool
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external returns (int128 delta0, int128 delta1);

    /// @notice Get pool slot0 (price, tick, etc)
    function getSlot0(bytes32 poolId) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    );
}

/// @title Uniswap V4 Universal Router Interface
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/// @title UniswapV4Adapter
/// @notice Adapter for Uniswap V4 singleton PoolManager
/// @dev V4 uses hooks and flash accounting for gas efficiency
contract UniswapV4Adapter is ILiquidityEngine {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Uniswap V4 PoolManager (Ethereum Mainnet)
    IPoolManager public constant POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

    /// @notice Uniswap V4 Universal Router
    IUniversalRouter public constant ROUTER = IUniversalRouter(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af);

    /// @notice Protocol name
    string public constant NAME = "Uniswap V4";

    /// @notice Default tick spacing for 0.3% fee
    int24 public constant DEFAULT_TICK_SPACING = 60;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Chain this adapter is deployed on
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

    /// @notice Get swap quote for V4 pool
    /// @dev V4 uses on-chain state for quotes
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (SwapQuote memory quote) {
        // Sort tokens for pool lookup
        (address currency0, address currency1) = tokenIn < tokenOut
            ? (tokenIn, tokenOut)
            : (tokenOut, tokenIn);

        // Create pool key with default parameters
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: address(0) // No hooks
        });

        // Get pool ID from key
        bytes32 poolId = _getPoolId(key);

        // Get current price
        (uint160 sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(poolId);

        // Estimate output (simplified - real implementation would simulate swap)
        bool zeroForOne = tokenIn == currency0;
        uint256 estimatedOut = _estimateOutput(amountIn, sqrtPriceX96, zeroForOne);

        quote = SwapQuote({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: estimatedOut,
            priceImpact: 0, // Would need deeper simulation
            gasEstimate: 150000, // V4 is more gas efficient
            route: abi.encode(key),
            validUntil: block.timestamp + 30
        });
    }

    /// @notice Execute swap via V4 Universal Router
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable override returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Deadline expired");

        // Transfer tokens in
        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);
        }

        // Build V4 swap command
        // Command: 0x00 = V4_SWAP
        bytes memory commands = hex"00";
        bytes[] memory inputs = new bytes[](1);

        // Sort tokens
        (address currency0, address currency1) = tokenIn < tokenOut
            ? (tokenIn, tokenOut)
            : (tokenOut, tokenIn);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: address(0)
        });

        bool zeroForOne = tokenIn == currency0;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341
        });

        inputs[0] = abi.encode(key, params, recipient, minAmountOut);

        // Execute swap
        uint256 balanceBefore = tokenOut == address(0)
            ? recipient.balance
            : IERC20(tokenOut).balanceOf(recipient);

        ROUTER.execute{value: tokenIn == address(0) ? amountIn : 0}(
            commands,
            inputs,
            deadline
        );

        uint256 balanceAfter = tokenOut == address(0)
            ? recipient.balance
            : IERC20(tokenOut).balanceOf(recipient);

        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= minAmountOut, "Insufficient output");

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut, "UNISWAP_V4");
    }

    /// @notice Execute swap with pre-computed route
    function swapWithRoute(
        bytes calldata route,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable override returns (uint256 amountOut) {
        // Decode route as V4 command sequence
        (bytes memory commands, bytes[] memory inputs) = abi.decode(route, (bytes, bytes[]));

        // Execute via Universal Router
        ROUTER.execute{value: msg.value}(commands, inputs, deadline);

        // Get output from recipient balance
        // (In production, track deltas properly)
        amountOut = minAmountOut; // Simplified

        return amountOut;
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
        // V4 uses Position Manager for LP positions
        // This requires a separate PositionManager contract call
        revert("Use PositionManager for V4 LP");
    }

    function removeLiquidity(
        address pool,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline
    ) external override returns (uint256 amount0, uint256 amount1) {
        revert("Use PositionManager for V4 LP");
    }

    function getPoolInfo(address pool) external view override returns (PoolInfo memory) {
        revert("Use poolId for V4 pools");
    }

    /*//////////////////////////////////////////////////////////////
                          LENDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getLendingQuote(address, uint256, bool)
        external pure override returns (LendingQuote memory)
    {
        revert("Uniswap V4 does not support lending");
    }

    function supply(address, uint256, address)
        external pure override returns (uint256)
    {
        revert("Uniswap V4 does not support lending");
    }

    function withdraw(address, uint256, address)
        external pure override returns (uint256)
    {
        revert("Uniswap V4 does not support lending");
    }

    function borrow(address, uint256, uint256, address) external pure override {
        revert("Uniswap V4 does not support lending");
    }

    function repay(address, uint256, uint256, address)
        external pure override returns (uint256)
    {
        revert("Uniswap V4 does not support lending");
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function protocolName() external pure override returns (string memory) {
        return NAME;
    }

    function protocolType() external pure override returns (ProtocolType) {
        return ProtocolType.DEX_AMM;
    }

    function chain() external view override returns (Chain) {
        return CHAIN;
    }

    function isTokenSupported(address) external pure override returns (bool) {
        return true; // V4 supports any ERC20
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute pool ID from key
    function _getPoolId(IPoolManager.PoolKey memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    /// @notice Estimate swap output (simplified)
    function _estimateOutput(
        uint256 amountIn,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) internal pure returns (uint256) {
        // Simplified price calculation
        // Real implementation would use V4's tick math
        uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);

        if (zeroForOne) {
            return amountIn * price / 1e18;
        } else {
            return amountIn * 1e18 / price;
        }
    }
}
