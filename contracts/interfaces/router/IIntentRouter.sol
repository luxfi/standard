// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IIntentRouter
 * @author Lux Industries
 * @notice Interface for intent-based trading with limit orders, RFQ, and solver execution
 * @dev Implements EIP-712 for gasless orders and supports multiple execution paths
 */
interface IIntentRouter {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Order type
    enum OrderType {
        LIMIT,          // Standard limit order
        RFQ,            // Request for quote (private)
        DUTCH_AUCTION,  // Decaying price limit
        FILL_OR_KILL    // All or nothing
    }

    /// @notice Order status
    enum OrderStatus {
        OPEN,
        PARTIALLY_FILLED,
        FILLED,
        CANCELED,
        EXPIRED
    }

    /**
     * @notice A signed order/intent
     * @param maker Order creator
     * @param taker Specific taker (address(0) for open)
     * @param tokenIn Token being sold
     * @param tokenOut Token being bought
     * @param amountIn Amount being sold
     * @param amountOutMin Minimum amount to receive
     * @param amountOutMax Maximum amount (for dutch auction)
     * @param nonce Unique nonce for cancellation
     * @param deadline Order expiry
     * @param startTime Start time (for dutch auction)
     * @param orderType Type of order
     * @param partnerCode Partner/affiliate code
     */
    struct Order {
        address maker;
        address taker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 amountOutMax;
        uint256 nonce;
        uint256 deadline;
        uint256 startTime;
        OrderType orderType;
        bytes32 partnerCode;
    }

    /**
     * @notice Fill data for execution
     * @param order The order to fill
     * @param signature EIP-712 signature
     * @param fillAmount Amount of tokenIn to fill
     * @param solver Solver executing the trade
     * @param solverData Calldata for solver execution
     */
    struct Fill {
        Order order;
        bytes signature;
        uint256 fillAmount;
        address solver;
        bytes solverData;
    }

    /**
     * @notice Quote from market maker
     * @param maker Market maker
     * @param taker Quote requester
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @param amountOut Output amount
     * @param deadline Quote expiry
     * @param nonce Quote nonce
     * @param signature EIP-712 signature
     */
    struct Quote {
        address maker;
        address taker;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when signature is invalid
    error InvalidSignature();

    /// @notice Thrown when order has expired
    error OrderExpired();

    /// @notice Thrown when order has not started yet
    error OrderNotStarted();

    /// @notice Thrown when nonce has been used
    error NonceUsed();

    /// @notice Thrown when taker is not authorized
    error InvalidTaker();

    /// @notice Thrown when fill amount is invalid
    error InvalidFillAmount();

    /// @notice Thrown when output is below minimum
    error InsufficientOutput();

    /// @notice Thrown when order is fully filled
    error OrderFullyFilled();

    /// @notice Thrown when solver is not approved
    error SolverNotApproved();

    /// @notice Thrown when order parameters are invalid
    error InvalidOrder();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when an order is filled
     * @param orderHash Order hash
     * @param maker Order maker
     * @param taker Order taker
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount of input token filled
     * @param amountOut Amount of output token received
     * @param partnerCode Partner/affiliate code
     */
    event OrderFilled(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 partnerCode
    );

    /**
     * @notice Emitted when an order is canceled
     * @param maker Order maker
     * @param nonce Canceled nonce
     */
    event OrderCanceled(
        address indexed maker,
        uint256 indexed nonce
    );

    /**
     * @notice Emitted when a quote is filled
     * @param quoteHash Quote hash
     * @param maker Quote maker
     * @param taker Quote taker
     * @param amountIn Input amount
     * @param amountOut Output amount
     */
    event QuoteFilled(
        bytes32 indexed quoteHash,
        address indexed maker,
        address indexed taker,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice Emitted when a solver is updated
     * @param solver Solver address
     * @param approved Whether solver is approved
     */
    event SolverUpdated(address indexed solver, bool approved);

    /**
     * @notice Emitted when a partner is registered
     * @param code Partner code
     * @param receiver Fee receiver
     * @param feeBps Fee in basis points
     */
    event PartnerRegistered(bytes32 indexed code, address receiver, uint256 feeBps);

    // ═══════════════════════════════════════════════════════════════════════
    // ORDER EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Fill a signed order
     * @param fill Fill details including order and solver data
     * @return amountOut Amount of tokenOut received by maker
     */
    function fillOrder(Fill calldata fill) external returns (uint256 amountOut);

    /**
     * @notice Fill multiple orders in one transaction
     * @param fills Array of fills
     * @return amountsOut Array of output amounts
     */
    function fillOrders(Fill[] calldata fills) external returns (uint256[] memory amountsOut);

    /**
     * @notice Fill an RFQ quote
     * @param quote Quote from market maker
     * @return amountOut Amount received
     */
    function fillQuote(Quote calldata quote) external returns (uint256 amountOut);

    /**
     * @notice Solver execution with custom routing
     * @dev Called by approved solvers only
     * @param fills Orders to fill
     * @param routeData Routing data for solver
     * @return amountsOut Output amounts
     */
    function solve(Fill[] calldata fills, bytes calldata routeData) external returns (uint256[] memory amountsOut);

    // ═══════════════════════════════════════════════════════════════════════
    // ORDER MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancel an order by invalidating its nonce
     * @param nonce Nonce to cancel
     */
    function cancelOrder(uint256 nonce) external;

    /**
     * @notice Cancel all orders up to a nonce (inclusive)
     * @param nonce Maximum nonce to cancel
     */
    function cancelOrdersUpToNonce(uint256 nonce) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get EIP-712 hash of an order
     * @param order Order to hash
     * @return Order hash
     */
    function getOrderHash(Order calldata order) external view returns (bytes32);

    /**
     * @notice Get order status
     * @param order Order to check
     * @return Current order status
     */
    function getOrderStatus(Order calldata order) external view returns (OrderStatus);

    /**
     * @notice Get current Dutch auction price
     * @param order Dutch auction order
     * @return Current expected output amount
     */
    function getDutchAuctionPrice(Order calldata order) external view returns (uint256);

    /**
     * @notice Check if an order is valid
     * @param order Order to validate
     * @param signature EIP-712 signature
     * @return Whether the order is valid
     */
    function isOrderValid(Order calldata order, bytes calldata signature) external view returns (bool);

    /**
     * @notice Get remaining fillable amount
     * @param order Order to check
     * @return Remaining amount that can be filled
     */
    function getRemainingAmount(Order calldata order) external view returns (uint256);
}
