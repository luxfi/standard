// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import {SafeERC20} from "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityEngine} from "../interfaces/ILiquidityEngine.sol";

/// @title 1inch Aggregation Router V5 Interface
interface IAggregationRouterV5 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(
        address executor,
        SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);

    function unoswap(
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function uniswapV3Swap(
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

/// @title OneInchAdapter
/// @notice Adapter for 1inch aggregator - best cross-DEX routing
contract OneInchAdapter is ILiquidityEngine {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // 1inch Router V5 (same address on all EVM chains)
    IAggregationRouterV5 public constant ROUTER =
        IAggregationRouterV5(0x1111111254EEB25477B68fb85Ed929f73A960582);

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

    /// @notice Get quote from 1inch API (must be called off-chain)
    /// @dev On-chain quote not available, use 1inch API
    function getSwapQuote(address, address, uint256)
        external override returns (SwapQuote memory)
    {
        // 1inch requires off-chain API call for quotes
        // Return empty quote - use 1inch API directly
        revert("Use 1inch API for quotes");
    }

    /// @notice Execute swap with 1inch
    /// @dev Route data should be obtained from 1inch API
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable override returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Deadline expired");

        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);
        }

        // Simple swap using unoswap for gas efficiency
        // In production, use full swap() with API-generated route
        IAggregationRouterV5.SwapDescription memory desc = IAggregationRouterV5.SwapDescription({
            srcToken: tokenIn,
            dstToken: tokenOut,
            srcReceiver: payable(address(this)),
            dstReceiver: payable(recipient),
            amount: amountIn,
            minReturnAmount: minAmountOut,
            flags: 0
        });

        (amountOut,) = ROUTER.swap{value: msg.value}(
            address(0), // executor (use default)
            desc,
            "", // permit
            "" // data
        );

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut, "1INCH");
    }

    /// @notice Execute swap with pre-built 1inch route
    /// @param route Full encoded swap data from 1inch API
    function swapWithRoute(
        bytes calldata route,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external payable override returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Deadline expired");

        // Decode route from 1inch API
        (
            address executor,
            IAggregationRouterV5.SwapDescription memory desc,
            bytes memory permit,
            bytes memory data
        ) = abi.decode(route, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Override recipient and minReturn
        desc.dstReceiver = payable(recipient);
        desc.minReturnAmount = minAmountOut;

        if (desc.srcToken != address(0)) {
            IERC20(desc.srcToken).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(desc.srcToken).forceApprove(address(ROUTER), amountIn);
        }

        (amountOut,) = ROUTER.swap{value: msg.value}(
            executor,
            desc,
            permit,
            data
        );
    }

    /*//////////////////////////////////////////////////////////////
                    NOT IMPLEMENTED (DEX ONLY)
    //////////////////////////////////////////////////////////////*/

    function addLiquidity(address, uint256, uint256, uint256, uint256, address, uint256)
        external pure override returns (uint256)
    {
        revert("Aggregator only");
    }

    function removeLiquidity(address, uint256, uint256, uint256, address, uint256)
        external pure override returns (uint256, uint256)
    {
        revert("Aggregator only");
    }

    function getPoolInfo(address) external pure override returns (PoolInfo memory) {
        revert("Aggregator only");
    }

    function getLendingQuote(address, uint256, bool)
        external pure override returns (LendingQuote memory)
    {
        revert("Not a lending protocol");
    }

    function supply(address, uint256, address) external pure override returns (uint256) {
        revert("Not a lending protocol");
    }

    function withdraw(address, uint256, address) external pure override returns (uint256) {
        revert("Not a lending protocol");
    }

    function borrow(address, uint256, uint256, address) external pure override {
        revert("Not a lending protocol");
    }

    function repay(address, uint256, uint256, address) external pure override returns (uint256) {
        revert("Not a lending protocol");
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function protocolName() external pure override returns (string memory) {
        return "1inch";
    }

    function protocolType() external pure override returns (ProtocolType) {
        return ProtocolType.DEX_AGGREGATOR;
    }

    function chain() external view override returns (Chain) {
        return CHAIN;
    }

    function isTokenSupported(address) external pure override returns (bool) {
        return true;
    }

    receive() external payable {}
}
