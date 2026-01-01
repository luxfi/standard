// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDEX, DEXLib} from "@luxfi/contracts/precompile/interfaces/dex/IDEX.sol";
import {IOracle, OracleLib} from "@luxfi/contracts/precompile/interfaces/IOracle.sol";
import {IBridgeAggregator, BridgeLib, IWarp} from "./bridges/IBridgeAggregator.sol";
import {ILiquidityEngine} from "./interfaces/ILiquidityEngine.sol";

/// @title CrossChainDeFiRouter
/// @notice Unified router for omnichain DeFi with HFT DEX integration
/// @dev Combines native DEX precompile, Oracle precompile, and Bridge aggregation
contract CrossChainDeFiRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using DEXLib for *;
    using OracleLib for *;
    using BridgeLib for *;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice DEX Precompile
    IDEX public constant DEX = IDEX(0x0200000000000000000000000000000000000010);

    /// @notice Oracle Precompile
    IOracle public constant ORACLE = IOracle(0x0200000000000000000000000000000000000011);

    /// @notice Warp Precompile
    IWarp public constant WARP = IWarp(0x0200000000000000000000000000000000000005);

    /// @notice Max slippage in basis points (0.5%)
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 50;

    /// @notice Max price staleness (1 minute)
    uint256 public constant MAX_PRICE_STALENESS = 60;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Execution venue for swaps
    enum Venue {
        NATIVE_DEX,         // Lux HFT DEX precompile
        UNISWAP_V3,         // Uniswap V3
        UNISWAP_V4,         // Uniswap V4
        CURVE,              // Curve pools
        ONE_INCH,           // 1inch aggregator
        COWSWAP,            // CoW Protocol
        AUTO                // Auto-select best venue
    }

    /// @notice Cross-chain swap request
    struct CrossChainSwapRequest {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 dstChainId;
        address recipient;
        Venue venue;
        IBridgeAggregator.BridgeProtocol bridge;
        bytes routeData;
    }

    /// @notice Cross-chain swap result
    struct CrossChainSwapResult {
        bytes32 messageId;
        uint256 srcAmountIn;
        uint256 estimatedAmountOut;
        uint256 bridgeFee;
        uint256 executionPrice;
        Venue venueUsed;
        IBridgeAggregator.BridgeProtocol bridgeUsed;
    }

    /// @notice Limit order with cross-chain settlement
    struct CrossChainLimitOrder {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 limitPrice;         // 1e18 precision
        uint256 dstChainId;
        address recipient;
        IDEX.OrderType orderType;
        IBridgeAggregator.BridgeProtocol bridge;
        uint256 expiry;
    }

    /// @notice Flash loan arbitrage params
    struct ArbitrageParams {
        address[] tokens;           // Token path
        uint256[] chainIds;         // Chain path
        uint256 flashAmount;
        uint256 minProfit;
        bytes[] routeData;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Bridge aggregator contract
    IBridgeAggregator public bridgeAggregator;

    /// @notice Registered external liquidity engines
    mapping(Venue => ILiquidityEngine) public liquidityEngines;

    /// @notice Pending cross-chain orders
    mapping(bytes32 => CrossChainLimitOrder) public pendingOrders;

    /// @notice Chain-specific token mappings (srcToken => dstChain => dstToken)
    mapping(address => mapping(uint256 => address)) public tokenMappings;

    /// @notice Owner
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CrossChainSwapInitiated(
        bytes32 indexed messageId,
        address indexed sender,
        uint256 srcChainId,
        uint256 dstChainId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 estimatedAmountOut
    );

    event CrossChainSwapCompleted(
        bytes32 indexed messageId,
        address indexed recipient,
        address tokenOut,
        uint256 amountOut,
        uint256 executionPrice
    );

    event CrossChainLimitOrderPlaced(
        bytes32 indexed orderId,
        address indexed trader,
        uint256 dstChainId,
        uint256 limitPrice
    );

    event ArbitrageExecuted(
        address indexed executor,
        uint256 profit,
        address[] tokens,
        uint256[] chainIds
    );

    event VenueRegistered(Venue indexed venue, address engine);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _bridgeAggregator) {
        bridgeAggregator = IBridgeAggregator(_bridgeAggregator);
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                           SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute swap on native HFT DEX
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param minAmountOut Minimum output
    /// @return result Trade result
    function swapOnDEX(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (IDEX.TradeResult memory result) {
        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(DEX), amountIn);

        // Execute via HFT DEX precompile
        result = DEX.marketOrder(tokenIn, tokenOut, amountIn, minAmountOut);

        // Transfer output to sender
        IERC20(tokenOut).safeTransfer(msg.sender, result.amountOut);

        return result;
    }

    /// @notice Execute swap with best venue selection
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param minAmountOut Minimum output
    /// @return amountOut Actual output amount
    /// @return venueUsed Venue that was used
    function swapBestVenue(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut, Venue venueUsed) {
        // Get quotes from all venues
        (uint256 bestQuote, Venue bestVenue) = _getBestQuote(tokenIn, tokenOut, amountIn);
        require(bestQuote >= minAmountOut, "Insufficient output");

        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Execute on best venue
        if (bestVenue == Venue.NATIVE_DEX) {
            IERC20(tokenIn).forceApprove(address(DEX), amountIn);
            IDEX.TradeResult memory result = DEX.marketOrder(tokenIn, tokenOut, amountIn, minAmountOut);
            amountOut = result.amountOut;
        } else {
            ILiquidityEngine engine = liquidityEngines[bestVenue];
            IERC20(tokenIn).forceApprove(address(engine), amountIn);
            amountOut = engine.swap(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                msg.sender,
                block.timestamp + 300
            );
        }

        // Transfer output
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        return (amountOut, bestVenue);
    }

    /// @notice Execute cross-chain swap
    /// @param request Cross-chain swap request
    /// @return result Swap result with message ID
    function crossChainSwap(
        CrossChainSwapRequest calldata request
    ) external payable nonReentrant returns (CrossChainSwapResult memory result) {
        // Validate oracle price
        IOracle.Price memory price = ORACLE.getPrice(request.tokenIn, request.tokenOut);
        require(price.isValid, "Invalid oracle price");
        require(block.timestamp - price.timestamp <= MAX_PRICE_STALENESS, "Stale price");

        // Transfer input tokens
        IERC20(request.tokenIn).safeTransferFrom(msg.sender, address(this), request.amountIn);

        // Swap locally if needed (tokenIn != bridgeable token)
        address bridgeToken = request.tokenIn;
        uint256 bridgeAmount = request.amountIn;

        // If different tokens, swap first on source chain
        if (request.tokenIn != request.tokenOut && request.dstChainId == block.chainid) {
            bridgeAmount = _executeSwap(
                request.tokenIn,
                request.tokenOut,
                request.amountIn,
                request.minAmountOut,
                request.venue
            );
            bridgeToken = request.tokenOut;
        }

        // Get destination token
        address dstToken = tokenMappings[bridgeToken][request.dstChainId];
        if (dstToken == address(0)) dstToken = bridgeToken;

        // Encode cross-chain payload
        bytes memory payload = abi.encode(
            request.recipient,
            request.tokenOut,
            request.minAmountOut,
            request.venue,
            request.routeData
        );

        // Bridge tokens and message
        IERC20(bridgeToken).forceApprove(address(bridgeAggregator), bridgeAmount);

        IBridgeAggregator.TransferResult memory bridgeResult = bridgeAggregator.bridgeVia{value: msg.value}(
            request.bridge,
            IBridgeAggregator.TransferRequest({
                token: bridgeToken,
                amount: bridgeAmount,
                dstChainId: request.dstChainId,
                recipient: request.recipient,
                minAmountOut: request.minAmountOut,
                gasLimit: 500000,
                extraData: payload
            })
        );

        result = CrossChainSwapResult({
            messageId: bridgeResult.messageId,
            srcAmountIn: request.amountIn,
            estimatedAmountOut: request.minAmountOut,
            bridgeFee: bridgeResult.fee,
            executionPrice: price.price,
            venueUsed: request.venue,
            bridgeUsed: request.bridge
        });

        emit CrossChainSwapInitiated(
            result.messageId,
            msg.sender,
            block.chainid,
            request.dstChainId,
            request.tokenIn,
            request.tokenOut,
            request.amountIn,
            result.estimatedAmountOut
        );

        return result;
    }

    /*//////////////////////////////////////////////////////////////
                         LIMIT ORDER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Place limit order on native HFT DEX
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param limitPrice Limit price (1e18)
    /// @param orderType Order type
    /// @param expiry Expiration timestamp
    /// @return orderId Order identifier
    function placeLimitOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 limitPrice,
        IDEX.OrderType orderType,
        uint256 expiry
    ) external nonReentrant returns (uint64 orderId) {
        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(DEX), amountIn);

        // Place limit order via DEX precompile
        orderId = DEX.limitOrder(
            tokenIn,
            tokenOut,
            amountIn,
            limitPrice,
            orderType,
            expiry
        );

        return orderId;
    }

    /// @notice Place cross-chain limit order
    /// @param order Cross-chain limit order details
    /// @return orderId Order identifier
    function placeCrossChainLimitOrder(
        CrossChainLimitOrder calldata order
    ) external payable nonReentrant returns (bytes32 orderId) {
        // Transfer tokens
        IERC20(order.tokenIn).safeTransferFrom(msg.sender, address(this), order.amountIn);

        // Generate order ID
        orderId = keccak256(abi.encode(
            msg.sender,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.limitPrice,
            order.dstChainId,
            block.timestamp
        ));

        // Store pending order
        pendingOrders[orderId] = order;

        // Place on local DEX with callback mechanism
        IERC20(order.tokenIn).forceApprove(address(DEX), order.amountIn);

        // For GTC orders, place on orderbook
        if (order.orderType == IDEX.OrderType.GTC || order.orderType == IDEX.OrderType.GTD) {
            DEX.limitOrder(
                order.tokenIn,
                order.tokenOut,
                order.amountIn,
                order.limitPrice,
                order.orderType,
                order.expiry
            );
        }

        emit CrossChainLimitOrderPlaced(
            orderId,
            msg.sender,
            order.dstChainId,
            order.limitPrice
        );

        return orderId;
    }

    /// @notice Cancel pending limit order
    /// @param orderId DEX order ID
    /// @return success True if cancelled
    function cancelLimitOrder(uint64 orderId) external nonReentrant returns (bool success) {
        return DEX.cancelOrder(orderId);
    }

    /*//////////////////////////////////////////////////////////////
                        ORDERBOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get orderbook snapshot
    /// @param token0 First token
    /// @param token1 Second token
    /// @param depth Number of levels
    /// @return orderbook Orderbook data
    function getOrderbook(
        address token0,
        address token1,
        uint256 depth
    ) external view returns (IDEX.Orderbook memory orderbook) {
        return DEX.getOrderbook(token0, token1, depth);
    }

    /// @notice Get best bid/ask from DEX
    /// @param token0 First token
    /// @param token1 Second token
    /// @return bestBid Best bid price
    /// @return bestAsk Best ask price
    /// @return spread Spread in basis points
    function getBestPrices(
        address token0,
        address token1
    ) external view returns (uint256 bestBid, uint256 bestAsk, uint256 spread) {
        (bestBid, bestAsk,) = DEX.getBestPrices(token0, token1);
        if (bestAsk > 0) {
            spread = (bestAsk - bestBid) * 10000 / bestAsk;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ORACLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get aggregated price from multiple sources
    /// @param base Base token
    /// @param quote Quote token
    /// @return price Aggregated price
    /// @return confidence Confidence level
    function getAggregatedPrice(
        address base,
        address quote
    ) external view returns (uint256 price, uint256 confidence) {
        IOracle.AggregatedPrice memory agg = ORACLE.getAggregatedPrice(base, quote);
        return (agg.price, agg.confidence);
    }

    /// @notice Get TWAP from native DEX
    /// @param base Base token
    /// @param quote Quote token
    /// @param window TWAP window in seconds
    /// @return twap Time-weighted average price
    function getTWAP(
        address base,
        address quote,
        uint32 window
    ) external view returns (uint256 twap) {
        return ORACLE.getTWAP(
            base,
            quote,
            IOracle.TWAPConfig({
                window: window,
                granularity: 30,
                useGeometric: true
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                       ARBITRAGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute cross-chain arbitrage
    /// @param params Arbitrage parameters
    /// @return profit Net profit
    function executeArbitrage(
        ArbitrageParams calldata params
    ) external payable nonReentrant returns (uint256 profit) {
        require(params.tokens.length >= 2, "Invalid path");
        require(params.tokens.length == params.chainIds.length, "Length mismatch");

        address startToken = params.tokens[0];
        uint256 startBalance = IERC20(startToken).balanceOf(address(this));

        // Flash loan from DEX
        // Note: This requires DEX to support flash loans
        // For now, require tokens to be pre-funded
        require(
            IERC20(startToken).balanceOf(address(this)) >= params.flashAmount,
            "Insufficient flash amount"
        );

        uint256 currentAmount = params.flashAmount;

        // Execute multi-hop, multi-chain arbitrage
        for (uint256 i = 0; i < params.tokens.length - 1; i++) {
            address tokenIn = params.tokens[i];
            address tokenOut = params.tokens[i + 1];
            uint256 srcChain = params.chainIds[i];
            uint256 dstChain = params.chainIds[i + 1];

            if (srcChain == dstChain && srcChain == block.chainid) {
                // Local swap
                currentAmount = _executeSwap(
                    tokenIn,
                    tokenOut,
                    currentAmount,
                    0,
                    Venue.NATIVE_DEX
                );
            } else {
                // Cross-chain swap
                // This would be async, so revert for now
                revert("Async cross-chain arb not supported");
            }
        }

        // Verify profit
        uint256 endBalance = IERC20(startToken).balanceOf(address(this));
        require(endBalance > startBalance, "No profit");

        profit = endBalance - startBalance;
        require(profit >= params.minProfit, "Insufficient profit");

        // Transfer profit to executor
        IERC20(startToken).safeTransfer(msg.sender, profit);

        emit ArbitrageExecuted(msg.sender, profit, params.tokens, params.chainIds);

        return profit;
    }

    /*//////////////////////////////////////////////////////////////
                         QUOTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get quote from native DEX
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @return quote DEX quote
    function getDEXQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (IDEX.Quote memory quote) {
        return DEX.getQuote(tokenIn, tokenOut, amountIn);
    }

    /// @notice Get quotes from all venues
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @return quotes Array of (venue, amountOut)
    function getAllQuotes(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256[] memory quotes) {
        quotes = new uint256[](6);

        // Native DEX
        IDEX.Quote memory dexQuote = DEX.getQuote(tokenIn, tokenOut, amountIn);
        quotes[0] = dexQuote.amountOut;

        // External venues (if registered)
        for (uint256 i = 1; i <= 5; i++) {
            ILiquidityEngine engine = liquidityEngines[Venue(i)];
            if (address(engine) != address(0)) {
                try engine.getSwapQuote(tokenIn, tokenOut, amountIn) returns (
                    ILiquidityEngine.SwapQuote memory q
                ) {
                    quotes[i] = q.amountOut;
                } catch {
                    quotes[i] = 0;
                }
            }
        }

        return quotes;
    }

    /// @notice Get cross-chain quote
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param dstChainId Destination chain
    /// @return estimatedOut Estimated output after bridge
    /// @return bridgeFee Bridge fee
    /// @return totalTime Estimated total time
    function getCrossChainQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 dstChainId
    ) external view returns (
        uint256 estimatedOut,
        uint256 bridgeFee,
        uint256 totalTime
    ) {
        // Get swap quote
        IDEX.Quote memory dexQuote = DEX.getQuote(tokenIn, tokenOut, amountIn);

        // Get bridge quote
        IBridgeAggregator.BridgeQuote[] memory bridgeQuotes =
            bridgeAggregator.getQuotes(tokenOut, dexQuote.amountOut, dstChainId);

        // Find best bridge
        uint256 bestOut = 0;
        uint256 bestFee = type(uint256).max;
        uint256 bestTime = 0;

        for (uint256 i = 0; i < bridgeQuotes.length; i++) {
            if (bridgeQuotes[i].available && bridgeQuotes[i].amountOut > bestOut) {
                bestOut = bridgeQuotes[i].amountOut;
                bestFee = bridgeQuotes[i].fee;
                bestTime = bridgeQuotes[i].estimatedTime;
            }
        }

        return (bestOut, bestFee, bestTime);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register external liquidity engine
    /// @param venue Venue identifier
    /// @param engine Engine contract address
    function registerVenue(Venue venue, address engine) external {
        require(msg.sender == owner, "Not owner");
        require(venue != Venue.NATIVE_DEX, "Cannot override native DEX");
        liquidityEngines[venue] = ILiquidityEngine(engine);
        emit VenueRegistered(venue, engine);
    }

    /// @notice Set token mapping for cross-chain
    /// @param srcToken Source chain token
    /// @param dstChainId Destination chain ID
    /// @param dstToken Destination chain token
    function setTokenMapping(
        address srcToken,
        uint256 dstChainId,
        address dstToken
    ) external {
        require(msg.sender == owner, "Not owner");
        tokenMappings[srcToken][dstChainId] = dstToken;
    }

    /// @notice Update bridge aggregator
    /// @param _bridgeAggregator New bridge aggregator
    function setBridgeAggregator(address _bridgeAggregator) external {
        require(msg.sender == owner, "Not owner");
        bridgeAggregator = IBridgeAggregator(_bridgeAggregator);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get best quote across venues
    function _getBestQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 bestQuote, Venue bestVenue) {
        // Start with native DEX
        IDEX.Quote memory dexQuote = DEX.getQuote(tokenIn, tokenOut, amountIn);
        bestQuote = dexQuote.amountOut;
        bestVenue = Venue.NATIVE_DEX;

        // Check external venues
        for (uint256 i = 1; i <= 5; i++) {
            ILiquidityEngine engine = liquidityEngines[Venue(i)];
            if (address(engine) != address(0)) {
                try engine.getSwapQuote(tokenIn, tokenOut, amountIn) returns (
                    ILiquidityEngine.SwapQuote memory q
                ) {
                    if (q.amountOut > bestQuote) {
                        bestQuote = q.amountOut;
                        bestVenue = Venue(i);
                    }
                } catch {}
            }
        }

        return (bestQuote, bestVenue);
    }

    /// @notice Execute swap on specified venue
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        Venue venue
    ) internal returns (uint256 amountOut) {
        if (venue == Venue.NATIVE_DEX || venue == Venue.AUTO) {
            IERC20(tokenIn).forceApprove(address(DEX), amountIn);
            IDEX.TradeResult memory result = DEX.marketOrder(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut
            );
            return result.amountOut;
        } else {
            ILiquidityEngine engine = liquidityEngines[venue];
            require(address(engine) != address(0), "Venue not registered");

            IERC20(tokenIn).forceApprove(address(engine), amountIn);
            return engine.swap(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                address(this),
                block.timestamp + 300
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                           RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive cross-chain message (called by bridge receiver)
    /// @param sourceChainId Source chain
    /// @param sender Original sender
    /// @param payload Encoded swap/settlement data
    function onCrossChainMessage(
        uint256 sourceChainId,
        address sender,
        bytes calldata payload
    ) external nonReentrant {
        // Decode payload
        (
            address recipient,
            address tokenOut,
            uint256 minAmountOut,
            Venue venue,
            bytes memory routeData
        ) = abi.decode(payload, (address, address, uint256, Venue, bytes));

        // Get bridged token amount (already received)
        // This would come from the bridge callback
        uint256 bridgedAmount = abi.decode(routeData, (uint256));

        // Execute swap if needed
        uint256 amountOut = bridgedAmount;

        // Transfer to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit CrossChainSwapCompleted(
            keccak256(payload),
            recipient,
            tokenOut,
            amountOut,
            0 // execution price
        );
    }

    /// @notice Receive ETH
    receive() external payable {}
}
