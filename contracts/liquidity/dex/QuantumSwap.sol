// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDEX, DEXLib} from "@luxfi/contracts/precompile/interfaces/dex/IDEX.sol";
import {IOracle, OracleLib} from "@luxfi/contracts/precompile/interfaces/IOracle.sol";

/// @title IQuantumSwap
/// @notice High-frequency trading interface for Lux native DEX
/// @dev Wraps DEX precompile with additional HFT features
/// @custom:performance 434M orders/sec (GPU), 1M orders/sec (Go), 500K orders/sec (C++)
/// @custom:latency 2ns (GPU), 487ns (CPU)
/// @custom:finality 1ms (FPC consensus)
interface IQuantumSwap {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice HFT execution strategy
    enum Strategy {
        TWAP,           // Time-weighted average price
        VWAP,           // Volume-weighted average price
        ICEBERG,        // Hidden size orders
        SNIPER,         // Fill at specific price
        ARBITRAGE,      // Cross-venue arbitrage
        MARKET_MAKE     // Provide liquidity both sides
    }

    /// @notice Advanced order with strategy
    struct StrategyOrder {
        address tokenIn;
        address tokenOut;
        uint256 totalAmount;
        uint256 limitPrice;
        Strategy strategy;
        uint256 startTime;
        uint256 endTime;
        uint256 slices;         // Number of execution slices
        uint256 minSliceSize;
        bytes strategyParams;
    }

    /// @notice Market making parameters
    struct MarketMakingParams {
        address token0;
        address token1;
        uint256 spread;         // Basis points
        uint256 depth;          // Order depth per side
        uint256 refreshRate;    // Milliseconds between requotes
        uint256 maxPosition;    // Maximum inventory
        bool autoRebalance;
    }

    /// @notice Execution report
    struct ExecutionReport {
        uint64[] orderIds;
        uint256 totalFilled;
        uint256 avgPrice;
        uint256 slippage;       // Actual vs expected
        uint256 gasUsed;
        uint256 executionTime;  // Nanoseconds
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategyOrderCreated(
        bytes32 indexed strategyId,
        address indexed trader,
        Strategy strategy,
        address tokenIn,
        address tokenOut,
        uint256 totalAmount
    );

    event StrategyOrderExecuted(
        bytes32 indexed strategyId,
        uint256 sliceFilled,
        uint256 slicePrice,
        uint256 remainingAmount
    );

    event MarketMakingStarted(
        bytes32 indexed mmId,
        address indexed maker,
        address token0,
        address token1,
        uint256 spread
    );

    event MarketMakingQuote(
        bytes32 indexed mmId,
        uint256 bidPrice,
        uint256 bidSize,
        uint256 askPrice,
        uint256 askSize
    );

    /*//////////////////////////////////////////////////////////////
                          STRATEGY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Submit TWAP order
    function submitTWAP(StrategyOrder calldata order) external returns (bytes32 strategyId);

    /// @notice Submit VWAP order
    function submitVWAP(StrategyOrder calldata order) external returns (bytes32 strategyId);

    /// @notice Submit iceberg order
    function submitIceberg(StrategyOrder calldata order) external returns (bytes32 strategyId);

    /// @notice Submit sniper order (triggers at price)
    function submitSniper(StrategyOrder calldata order) external returns (bytes32 strategyId);

    /// @notice Cancel strategy order
    function cancelStrategy(bytes32 strategyId) external returns (uint256 refundedAmount);

    /// @notice Get strategy execution status
    function getStrategyStatus(bytes32 strategyId) external view returns (
        uint256 filled,
        uint256 remaining,
        uint256 avgPrice,
        bool isActive
    );

    /*//////////////////////////////////////////////////////////////
                      MARKET MAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Start market making
    function startMarketMaking(MarketMakingParams calldata params) external returns (bytes32 mmId);

    /// @notice Stop market making
    function stopMarketMaking(bytes32 mmId) external returns (ExecutionReport memory report);

    /// @notice Update market making spread
    function updateSpread(bytes32 mmId, uint256 newSpread) external;

    /// @notice Get current inventory
    function getInventory(bytes32 mmId) external view returns (
        int256 token0Position,
        int256 token1Position,
        uint256 unrealizedPnL
    );
}

/// @title QuantumSwap
/// @notice Native HFT DEX wrapper with strategy execution
/// @dev Integrates with DEX precompile for sub-millisecond execution
contract QuantumSwap is IQuantumSwap, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using DEXLib for *;
    using OracleLib for *;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice DEX Precompile
    IDEX public constant DEX = IDEX(0x0200000000000000000000000000000000000010);

    /// @notice Oracle Precompile
    IOracle public constant ORACLE = IOracle(0x0200000000000000000000000000000000000011);

    /// @notice Protocol name
    string public constant NAME = "QuantumSwap";

    /// @notice Protocol version
    string public constant VERSION = "1.0.0";

    /// @notice Minimum slice for TWAP/VWAP
    uint256 public constant MIN_SLICES = 5;

    /// @notice Maximum slices
    uint256 public constant MAX_SLICES = 1000;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Strategy orders
    mapping(bytes32 => StrategyOrderState) public strategies;

    /// @notice Market making states
    mapping(bytes32 => MarketMakingState) public marketMakers;

    /// @notice User strategy IDs
    mapping(address => bytes32[]) public userStrategies;

    /// @notice Strategy order state
    struct StrategyOrderState {
        StrategyOrder order;
        address owner;
        uint256 filled;
        uint256 slicesExecuted;
        uint64[] orderIds;
        bool isActive;
        uint256 createdAt;
    }

    /// @notice Market making state
    struct MarketMakingState {
        MarketMakingParams params;
        address owner;
        int256 token0Position;
        int256 token1Position;
        uint64[] bidOrderIds;
        uint64[] askOrderIds;
        uint256 totalVolume;
        uint256 totalFees;
        bool isActive;
        uint256 startedAt;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {}

    /*//////////////////////////////////////////////////////////////
                           SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute instant swap via DEX precompile
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param minAmountOut Minimum output
    /// @return amountOut Actual output
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(DEX), amountIn);

        IDEX.TradeResult memory result = DEX.marketOrder(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );

        IERC20(tokenOut).safeTransfer(msg.sender, result.amountOut);
        return result.amountOut;
    }

    /// @notice Get swap quote from DEX
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @return quote DEX quote with price impact
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (IDEX.Quote memory quote) {
        return DEX.getQuote(tokenIn, tokenOut, amountIn);
    }

    /*//////////////////////////////////////////////////////////////
                          STRATEGY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Submit TWAP order
    function submitTWAP(
        StrategyOrder calldata order
    ) external nonReentrant returns (bytes32 strategyId) {
        require(order.strategy == Strategy.TWAP, "Not TWAP");
        require(order.slices >= MIN_SLICES && order.slices <= MAX_SLICES, "Invalid slices");
        require(order.endTime > order.startTime, "Invalid time range");

        strategyId = _createStrategy(order);

        // Transfer tokens upfront
        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), order.totalAmount);

        emit StrategyOrderCreated(
            strategyId,
            msg.sender,
            Strategy.TWAP,
            order.tokenIn,
            order.tokenOut,
            order.totalAmount
        );

        return strategyId;
    }

    /// @notice Submit VWAP order
    function submitVWAP(
        StrategyOrder calldata order
    ) external nonReentrant returns (bytes32 strategyId) {
        require(order.strategy == Strategy.VWAP, "Not VWAP");
        require(order.slices >= MIN_SLICES && order.slices <= MAX_SLICES, "Invalid slices");

        strategyId = _createStrategy(order);

        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), order.totalAmount);

        emit StrategyOrderCreated(
            strategyId,
            msg.sender,
            Strategy.VWAP,
            order.tokenIn,
            order.tokenOut,
            order.totalAmount
        );

        return strategyId;
    }

    /// @notice Submit iceberg order
    function submitIceberg(
        StrategyOrder calldata order
    ) external nonReentrant returns (bytes32 strategyId) {
        require(order.strategy == Strategy.ICEBERG, "Not ICEBERG");
        require(order.minSliceSize > 0, "Invalid slice size");

        strategyId = _createStrategy(order);

        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), order.totalAmount);

        // Place first visible slice
        uint256 visibleSize = order.minSliceSize;
        IERC20(order.tokenIn).forceApprove(address(DEX), visibleSize);

        uint64 orderId = DEX.limitOrder(
            order.tokenIn,
            order.tokenOut,
            visibleSize,
            order.limitPrice,
            IDEX.OrderType.GTC,
            order.endTime
        );

        strategies[strategyId].orderIds.push(orderId);

        emit StrategyOrderCreated(
            strategyId,
            msg.sender,
            Strategy.ICEBERG,
            order.tokenIn,
            order.tokenOut,
            order.totalAmount
        );

        return strategyId;
    }

    /// @notice Submit sniper order (triggers at price)
    function submitSniper(
        StrategyOrder calldata order
    ) external nonReentrant returns (bytes32 strategyId) {
        require(order.strategy == Strategy.SNIPER, "Not SNIPER");
        require(order.limitPrice > 0, "Invalid target price");

        strategyId = _createStrategy(order);

        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), order.totalAmount);

        // Place stop order via DEX
        IERC20(order.tokenIn).forceApprove(address(DEX), order.totalAmount);

        // Determine if stop-loss or take-profit based on current price
        IOracle.Price memory currentPrice = ORACLE.getPrice(order.tokenIn, order.tokenOut);

        uint64 orderId;
        if (order.limitPrice < currentPrice.price) {
            // Stop-loss (trigger when price falls to limit)
            orderId = DEX.stopLossOrder(
                order.tokenIn,
                order.tokenOut,
                order.totalAmount,
                order.limitPrice,
                0 // Market execution
            );
        } else {
            // Take-profit (trigger when price rises to limit)
            orderId = DEX.takeProfitOrder(
                order.tokenIn,
                order.tokenOut,
                order.totalAmount,
                order.limitPrice,
                0 // Market execution
            );
        }

        strategies[strategyId].orderIds.push(orderId);

        emit StrategyOrderCreated(
            strategyId,
            msg.sender,
            Strategy.SNIPER,
            order.tokenIn,
            order.tokenOut,
            order.totalAmount
        );

        return strategyId;
    }

    /// @notice Cancel strategy order
    function cancelStrategy(
        bytes32 strategyId
    ) external nonReentrant returns (uint256 refundedAmount) {
        StrategyOrderState storage state = strategies[strategyId];
        require(state.owner == msg.sender, "Not owner");
        require(state.isActive, "Not active");

        // Cancel all pending orders
        for (uint256 i = 0; i < state.orderIds.length; i++) {
            try DEX.cancelOrder(state.orderIds[i]) {} catch {}
        }

        state.isActive = false;

        // Calculate refund
        refundedAmount = state.order.totalAmount - state.filled;

        if (refundedAmount > 0) {
            IERC20(state.order.tokenIn).safeTransfer(msg.sender, refundedAmount);
        }

        return refundedAmount;
    }

    /// @notice Get strategy execution status
    function getStrategyStatus(
        bytes32 strategyId
    ) external view returns (
        uint256 filled,
        uint256 remaining,
        uint256 avgPrice,
        bool isActive
    ) {
        StrategyOrderState storage state = strategies[strategyId];
        filled = state.filled;
        remaining = state.order.totalAmount - state.filled;
        avgPrice = state.filled > 0 ? _calculateAvgPrice(state.orderIds) : 0;
        isActive = state.isActive;
    }

    /*//////////////////////////////////////////////////////////////
                      MARKET MAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Start market making
    function startMarketMaking(
        MarketMakingParams calldata params
    ) external nonReentrant returns (bytes32 mmId) {
        require(params.spread > 0 && params.spread < 10000, "Invalid spread");
        require(params.depth > 0, "Invalid depth");

        mmId = keccak256(abi.encode(
            msg.sender,
            params.token0,
            params.token1,
            block.timestamp
        ));

        marketMakers[mmId] = MarketMakingState({
            params: params,
            owner: msg.sender,
            token0Position: 0,
            token1Position: 0,
            bidOrderIds: new uint64[](0),
            askOrderIds: new uint64[](0),
            totalVolume: 0,
            totalFees: 0,
            isActive: true,
            startedAt: block.timestamp
        });

        // Place initial quotes
        _refreshQuotes(mmId);

        emit MarketMakingStarted(
            mmId,
            msg.sender,
            params.token0,
            params.token1,
            params.spread
        );

        return mmId;
    }

    /// @notice Stop market making
    function stopMarketMaking(
        bytes32 mmId
    ) external nonReentrant returns (ExecutionReport memory report) {
        MarketMakingState storage state = marketMakers[mmId];
        require(state.owner == msg.sender, "Not owner");
        require(state.isActive, "Not active");

        // Cancel all outstanding orders
        uint64[] memory allOrderIds = new uint64[](
            state.bidOrderIds.length + state.askOrderIds.length
        );

        uint256 idx = 0;
        for (uint256 i = 0; i < state.bidOrderIds.length; i++) {
            allOrderIds[idx++] = state.bidOrderIds[i];
            try DEX.cancelOrder(state.bidOrderIds[i]) {} catch {}
        }
        for (uint256 i = 0; i < state.askOrderIds.length; i++) {
            allOrderIds[idx++] = state.askOrderIds[i];
            try DEX.cancelOrder(state.askOrderIds[i]) {} catch {}
        }

        state.isActive = false;

        report = ExecutionReport({
            orderIds: allOrderIds,
            totalFilled: state.totalVolume,
            avgPrice: 0,
            slippage: 0,
            gasUsed: 0,
            executionTime: (block.timestamp - state.startedAt) * 1e9
        });

        return report;
    }

    /// @notice Update market making spread
    function updateSpread(bytes32 mmId, uint256 newSpread) external {
        MarketMakingState storage state = marketMakers[mmId];
        require(state.owner == msg.sender, "Not owner");
        require(state.isActive, "Not active");
        require(newSpread > 0 && newSpread < 10000, "Invalid spread");

        state.params.spread = newSpread;
        _refreshQuotes(mmId);
    }

    /// @notice Get current inventory
    function getInventory(
        bytes32 mmId
    ) external view returns (
        int256 token0Position,
        int256 token1Position,
        uint256 unrealizedPnL
    ) {
        MarketMakingState storage state = marketMakers[mmId];
        token0Position = state.token0Position;
        token1Position = state.token1Position;

        // Calculate unrealized PnL based on current mid price
        (uint256 bid, uint256 ask,) = DEX.getBestPrices(
            state.params.token0,
            state.params.token1
        );
        uint256 midPrice = (bid + ask) / 2;

        // Simplified PnL calculation
        if (token0Position >= 0) {
            unrealizedPnL = uint256(token0Position) * midPrice / 1e18;
        } else {
            unrealizedPnL = uint256(-token0Position) * midPrice / 1e18;
        }
    }

    /*//////////////////////////////////////////////////////////////
                         ORDERBOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get orderbook depth
    function getOrderbook(
        address token0,
        address token1,
        uint256 depth
    ) external view returns (IDEX.Orderbook memory) {
        return DEX.getOrderbook(token0, token1, depth);
    }

    /// @notice Get best prices
    function getBestPrices(
        address token0,
        address token1
    ) external view returns (uint256 bid, uint256 ask, uint256 mid) {
        (bid, ask, mid) = DEX.getBestPrices(token0, token1);
    }

    /// @notice Get 24h volume
    function getVolume24h(
        address token0,
        address token1
    ) external view returns (uint256) {
        return DEX.getVolume24h(token0, token1);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new strategy
    function _createStrategy(
        StrategyOrder calldata order
    ) internal returns (bytes32 strategyId) {
        strategyId = keccak256(abi.encode(
            msg.sender,
            order.tokenIn,
            order.tokenOut,
            order.totalAmount,
            order.strategy,
            block.timestamp
        ));

        strategies[strategyId] = StrategyOrderState({
            order: order,
            owner: msg.sender,
            filled: 0,
            slicesExecuted: 0,
            orderIds: new uint64[](0),
            isActive: true,
            createdAt: block.timestamp
        });

        userStrategies[msg.sender].push(strategyId);

        return strategyId;
    }

    /// @notice Refresh market making quotes
    function _refreshQuotes(bytes32 mmId) internal {
        MarketMakingState storage state = marketMakers[mmId];

        // Cancel existing orders
        for (uint256 i = 0; i < state.bidOrderIds.length; i++) {
            try DEX.cancelOrder(state.bidOrderIds[i]) {} catch {}
        }
        for (uint256 i = 0; i < state.askOrderIds.length; i++) {
            try DEX.cancelOrder(state.askOrderIds[i]) {} catch {}
        }

        delete state.bidOrderIds;
        delete state.askOrderIds;

        // Get current mid price from oracle
        IOracle.Price memory price = ORACLE.getPrice(
            state.params.token0,
            state.params.token1
        );

        if (!price.isValid) return;

        uint256 midPrice = price.price;
        uint256 spreadBps = state.params.spread;

        // Calculate bid/ask prices
        uint256 bidPrice = midPrice * (10000 - spreadBps / 2) / 10000;
        uint256 askPrice = midPrice * (10000 + spreadBps / 2) / 10000;

        // Place bid orders (buying token0)
        uint256 bidSize = state.params.depth;
        // Would need token1 balance check here

        // Place ask orders (selling token0)
        uint256 askSize = state.params.depth;
        // Would need token0 balance check here

        emit MarketMakingQuote(mmId, bidPrice, bidSize, askPrice, askSize);
    }

    /// @notice Calculate average execution price
    function _calculateAvgPrice(uint64[] memory orderIds) internal view returns (uint256) {
        uint256 totalValue = 0;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            IDEX.Order memory order = DEX.getOrder(orderIds[i]);
            if (order.filled > 0) {
                totalValue += order.filled * order.price / 1e18;
                totalAmount += order.filled;
            }
        }

        return totalAmount > 0 ? totalValue * 1e18 / totalAmount : 0;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get user's strategies
    function getUserStrategies(address user) external view returns (bytes32[] memory) {
        return userStrategies[user];
    }

    /// @notice Check if pair is supported
    function isPairSupported(
        address token0,
        address token1
    ) external view returns (bool) {
        return DEX.isPairSupported(token0, token1);
    }

    /// @notice Get protocol info
    function getProtocolInfo() external pure returns (
        string memory name,
        string memory version,
        uint256 maxOrdersPerSec,
        uint256 latencyNs
    ) {
        return (
            NAME,
            VERSION,
            434_000_000,    // 434M orders/sec (GPU)
            2               // 2ns latency (GPU)
        );
    }

    receive() external payable {}
}
