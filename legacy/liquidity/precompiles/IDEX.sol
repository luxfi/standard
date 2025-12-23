// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.24;

/// @title IDEX
/// @notice Native DEX Precompile Interface for HFT Operations
/// @dev Precompile Address: 0x0200000000000000000000000000000000000010
/// @custom:precompile-address 0x0200000000000000000000000000000000000010
interface IDEX {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Order types supported by the DEX
    enum OrderType {
        MARKET,     // Execute immediately at best price
        LIMIT,      // Execute at specified price or better
        IOC,        // Immediate-or-Cancel
        FOK,        // Fill-or-Kill (all or nothing)
        GTC,        // Good-til-Cancelled
        GTD,        // Good-til-Date
        STOP_LOSS,  // Triggered when price crosses threshold
        TAKE_PROFIT // Triggered when price reaches target
    }

    /// @notice Order side
    enum Side {
        BUY,
        SELL
    }

    /// @notice Order status
    enum OrderStatus {
        PENDING,
        OPEN,
        PARTIAL,
        FILLED,
        CANCELLED,
        EXPIRED,
        REJECTED
    }

    /// @notice Order struct
    struct Order {
        uint64 orderId;
        address trader;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 price;          // 1e18 precision
        OrderType orderType;
        Side side;
        OrderStatus status;
        uint256 filled;
        uint256 remaining;
        uint256 timestamp;
        uint256 expiry;
    }

    /// @notice Quote result
    struct Quote {
        uint256 amountOut;
        uint256 price;          // 1e18 precision
        uint256 priceImpact;    // basis points
        uint256 fee;            // basis points
        uint256 gasEstimate;
    }

    /// @notice Orderbook level
    struct Level {
        uint256 price;          // 1e18 precision
        uint256 quantity;
        uint256 orderCount;
    }

    /// @notice Orderbook snapshot
    struct Orderbook {
        Level[] bids;
        Level[] asks;
        uint256 midPrice;
        uint256 spread;         // basis points
        uint256 timestamp;
    }

    /// @notice Trade execution result
    struct TradeResult {
        uint64 orderId;
        uint256 amountIn;
        uint256 amountOut;
        uint256 avgPrice;
        uint256 fee;
        OrderStatus status;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OrderPlaced(
        uint64 indexed orderId,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 price,
        OrderType orderType,
        Side side
    );

    event OrderFilled(
        uint64 indexed orderId,
        address indexed trader,
        uint256 amountIn,
        uint256 amountOut,
        uint256 avgPrice
    );

    event OrderCancelled(uint64 indexed orderId, address indexed trader);
    event OrderExpired(uint64 indexed orderId);

    event Trade(
        address indexed tokenIn,
        address indexed tokenOut,
        address indexed trader,
        uint256 amountIn,
        uint256 amountOut,
        uint256 price
    );

    /*//////////////////////////////////////////////////////////////
                            ORDER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Place a market order (executes immediately)
    /// @param tokenIn Token to sell
    /// @param tokenOut Token to buy
    /// @param amountIn Amount to sell
    /// @param minAmountOut Minimum output (slippage protection)
    /// @return result Trade execution result
    function marketOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (TradeResult memory result);

    /// @notice Place a limit order
    /// @param tokenIn Token to sell
    /// @param tokenOut Token to buy
    /// @param amountIn Amount to sell
    /// @param price Limit price (1e18 precision)
    /// @param orderType Order type (LIMIT, GTC, GTD, IOC, FOK)
    /// @param expiry Expiration timestamp (0 for GTC)
    /// @return orderId Unique order identifier
    function limitOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 price,
        OrderType orderType,
        uint256 expiry
    ) external returns (uint64 orderId);

    /// @notice Place a stop-loss order
    /// @param tokenIn Token to sell when triggered
    /// @param tokenOut Token to buy
    /// @param amountIn Amount to sell
    /// @param triggerPrice Price that triggers the order
    /// @param limitPrice Limit price for execution (0 for market)
    /// @return orderId Unique order identifier
    function stopLossOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 triggerPrice,
        uint256 limitPrice
    ) external returns (uint64 orderId);

    /// @notice Place a take-profit order
    /// @param tokenIn Token to sell when triggered
    /// @param tokenOut Token to buy
    /// @param amountIn Amount to sell
    /// @param triggerPrice Price that triggers the order
    /// @param limitPrice Limit price for execution (0 for market)
    /// @return orderId Unique order identifier
    function takeProfitOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 triggerPrice,
        uint256 limitPrice
    ) external returns (uint64 orderId);

    /// @notice Cancel an existing order
    /// @param orderId Order to cancel
    /// @return success True if cancelled
    function cancelOrder(uint64 orderId) external returns (bool success);

    /// @notice Cancel multiple orders
    /// @param orderIds Orders to cancel
    /// @return cancelled Number of orders cancelled
    function cancelOrders(uint64[] calldata orderIds) external returns (uint256 cancelled);

    /// @notice Modify an existing order
    /// @param orderId Order to modify
    /// @param newPrice New limit price
    /// @param newAmount New amount (0 to keep current)
    /// @return success True if modified
    function modifyOrder(
        uint64 orderId,
        uint256 newPrice,
        uint256 newAmount
    ) external returns (bool success);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get quote for a swap
    /// @param tokenIn Token to sell
    /// @param tokenOut Token to buy
    /// @param amountIn Amount to sell
    /// @return quote Quote with expected output, price impact, fees
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (Quote memory quote);

    /// @notice Get quotes for multiple amounts
    /// @param tokenIn Token to sell
    /// @param tokenOut Token to buy
    /// @param amounts Amounts to quote
    /// @return quotes Array of quotes
    function getQuotes(
        address tokenIn,
        address tokenOut,
        uint256[] calldata amounts
    ) external view returns (Quote[] memory quotes);

    /// @notice Get orderbook snapshot
    /// @param token0 First token of pair
    /// @param token1 Second token of pair
    /// @param depth Number of levels per side
    /// @return orderbook Orderbook snapshot
    function getOrderbook(
        address token0,
        address token1,
        uint256 depth
    ) external view returns (Orderbook memory orderbook);

    /// @notice Get order details
    /// @param orderId Order identifier
    /// @return order Order details
    function getOrder(uint64 orderId) external view returns (Order memory order);

    /// @notice Get all orders for a trader
    /// @param trader Trader address
    /// @return orders Array of orders
    function getOrders(address trader) external view returns (Order[] memory orders);

    /// @notice Get open orders for a trader
    /// @param trader Trader address
    /// @return orders Array of open orders
    function getOpenOrders(address trader) external view returns (Order[] memory orders);

    /// @notice Get best bid/ask prices
    /// @param token0 First token of pair
    /// @param token1 Second token of pair
    /// @return bestBid Best bid price
    /// @return bestAsk Best ask price
    /// @return midPrice Mid price
    function getBestPrices(
        address token0,
        address token1
    ) external view returns (uint256 bestBid, uint256 bestAsk, uint256 midPrice);

    /// @notice Get 24h volume for a pair
    /// @param token0 First token of pair
    /// @param token1 Second token of pair
    /// @return volume24h Volume in token0 terms
    function getVolume24h(
        address token0,
        address token1
    ) external view returns (uint256 volume24h);

    /// @notice Check if pair is supported
    /// @param token0 First token
    /// @param token1 Second token
    /// @return supported True if pair exists
    function isPairSupported(
        address token0,
        address token1
    ) external view returns (bool supported);
}

/// @title DEXLib
/// @notice Library for interacting with DEX Precompile
library DEXLib {
    /// @notice DEX Precompile address
    IDEX internal constant DEX = IDEX(0x0200000000000000000000000000000000000010);

    /// @notice Execute market swap via precompile
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        IDEX.TradeResult memory result = DEX.marketOrder(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
        return result.amountOut;
    }

    /// @notice Get quote via precompile
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256 amountOut, uint256 priceImpact) {
        IDEX.Quote memory q = DEX.getQuote(tokenIn, tokenOut, amountIn);
        return (q.amountOut, q.priceImpact);
    }

    /// @notice Get mid price via precompile
    function getPrice(
        address token0,
        address token1
    ) internal view returns (uint256 price) {
        (,, price) = DEX.getBestPrices(token0, token1);
    }
}
