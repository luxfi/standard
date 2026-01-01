// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title IntentRouter
 * @author Lux Industries
 * @notice Intent-based trading with limit orders, RFQ, and solver execution
 * @dev Implements EIP-712 for gasless orders and supports multiple execution paths
 *
 * Key features:
 * - Gasless limit orders via EIP-712 signatures
 * - Request-for-Quote (RFQ) for market makers
 * - Solver network for optimal execution
 * - Partial fills support
 * - Expiry and cancellation
 * - MEV protection via private mempools
 */
contract IntentRouter is EIP712, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

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

    /// @notice A signed order/intent
    struct Order {
        address maker;           // Order creator
        address taker;           // Specific taker (address(0) for open)
        address tokenIn;         // Token being sold
        address tokenOut;        // Token being bought
        uint256 amountIn;        // Amount being sold
        uint256 amountOutMin;    // Minimum amount to receive
        uint256 amountOutMax;    // Maximum amount (for dutch auction)
        uint256 nonce;           // Unique nonce for cancellation
        uint256 deadline;        // Order expiry
        uint256 startTime;       // Start time (for dutch auction)
        OrderType orderType;     // Type of order
        bytes32 partnerCode;     // Partner/affiliate code
    }

    /// @notice Fill data for execution
    struct Fill {
        Order order;
        bytes signature;
        uint256 fillAmount;      // Amount of tokenIn to fill
        address solver;          // Solver executing the trade
        bytes solverData;        // Calldata for solver execution
    }

    /// @notice Quote from market maker
    struct Quote {
        address maker;           // Market maker
        address taker;           // Quote requester
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 deadline;
        uint256 nonce;
        bytes signature;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SOLVER_ROLE = keccak256("SOLVER_ROLE");
    bytes32 public constant MARKET_MAKER_ROLE = keccak256("MARKET_MAKER_ROLE");

    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,address taker,address tokenIn,address tokenOut,"
        "uint256 amountIn,uint256 amountOutMin,uint256 amountOutMax,"
        "uint256 nonce,uint256 deadline,uint256 startTime,uint8 orderType,bytes32 partnerCode)"
    );

    bytes32 public constant QUOTE_TYPEHASH = keccak256(
        "Quote(address maker,address taker,address tokenIn,address tokenOut,"
        "uint256 amountIn,uint256 amountOut,uint256 deadline,uint256 nonce)"
    );

    uint256 public constant BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Nonces used (maker => nonce => used)
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @notice Filled amounts for partial fills (orderHash => filled)
    mapping(bytes32 => uint256) public filledAmounts;

    /// @notice Protocol fee in basis points
    uint256 public protocolFeeBps = 5; // 0.05%

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Partner fee shares (partnerCode => feeBps)
    mapping(bytes32 => uint256) public partnerFees;

    /// @notice Partner receivers
    mapping(bytes32 => address) public partnerReceivers;

    /// @notice Approved solvers
    mapping(address => bool) public approvedSolvers;

    /// @notice Maker minimum balances for RFQ
    mapping(address => mapping(address => uint256)) public makerBalances;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

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

    event OrderCanceled(
        address indexed maker,
        uint256 indexed nonce
    );

    event QuoteFilled(
        bytes32 indexed quoteHash,
        address indexed maker,
        address indexed taker,
        uint256 amountIn,
        uint256 amountOut
    );

    event SolverUpdated(address indexed solver, bool approved);
    event PartnerRegistered(bytes32 indexed code, address receiver, uint256 feeBps);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidSignature();
    error OrderExpired();
    error OrderNotStarted();
    error NonceUsed();
    error InvalidTaker();
    error InvalidFillAmount();
    error InsufficientOutput();
    error OrderFullyFilled();
    error SolverNotApproved();
    error InvalidOrder();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _feeReceiver,
        address _admin
    ) EIP712("Lux Intent Router", "1") {
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(SOLVER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ORDER EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Fill a signed order
     * @param fill Fill details including order and solver data
     * @return amountOut Amount of tokenOut received by maker
     */
    function fillOrder(
        Fill calldata fill
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        Order calldata order = fill.order;

        // Validate order
        _validateOrder(order);

        // Verify signature
        bytes32 orderHash = _hashOrder(order);
        address signer = ECDSA.recover(_hashTypedDataV4(orderHash), fill.signature);
        if (signer != order.maker) revert InvalidSignature();

        // Check fill amount
        uint256 remaining = order.amountIn - filledAmounts[orderHash];
        if (remaining == 0) revert OrderFullyFilled();

        uint256 fillAmount = fill.fillAmount;
        if (order.orderType == OrderType.FILL_OR_KILL) {
            if (fillAmount != order.amountIn) revert InvalidFillAmount();
        }
        if (fillAmount > remaining) {
            fillAmount = remaining;
        }

        // Calculate expected output (with dutch auction decay if applicable)
        uint256 expectedOut = _calculateExpectedOutput(order, fillAmount);

        // Transfer tokenIn from maker
        IERC20(order.tokenIn).safeTransferFrom(order.maker, address(this), fillAmount);

        // Execute via solver if provided
        if (fill.solver != address(0)) {
            if (!approvedSolvers[fill.solver]) revert SolverNotApproved();

            IERC20(order.tokenIn).forceApprove(fill.solver, fillAmount);

            // Solver callback
            (bool success, bytes memory result) = fill.solver.call(fill.solverData);
            require(success, "Solver execution failed");

            amountOut = abi.decode(result, (uint256));
        } else {
            // Direct taker fill
            IERC20(order.tokenOut).safeTransferFrom(msg.sender, address(this), expectedOut);
            amountOut = expectedOut;
        }

        if (amountOut < expectedOut) revert InsufficientOutput();

        // Update filled amount
        filledAmounts[orderHash] += fillAmount;

        // Apply fees
        (uint256 protocolFee, uint256 partnerFee) = _calculateFees(amountOut, order.partnerCode);
        uint256 makerAmount = amountOut - protocolFee - partnerFee;

        // Transfer to maker
        IERC20(order.tokenOut).safeTransfer(order.maker, makerAmount);

        // Transfer fees
        if (protocolFee > 0) {
            IERC20(order.tokenOut).safeTransfer(feeReceiver, protocolFee);
        }
        if (partnerFee > 0) {
            address partnerReceiver = partnerReceivers[order.partnerCode];
            if (partnerReceiver != address(0)) {
                IERC20(order.tokenOut).safeTransfer(partnerReceiver, partnerFee);
            }
        }

        emit OrderFilled(
            orderHash,
            order.maker,
            msg.sender,
            order.tokenIn,
            order.tokenOut,
            fillAmount,
            makerAmount,
            order.partnerCode
        );
    }

    /**
     * @notice Fill multiple orders in one transaction
     * @param fills Array of fills
     * @return amountsOut Array of output amounts
     */
    function fillOrders(
        Fill[] calldata fills
    ) external nonReentrant whenNotPaused returns (uint256[] memory amountsOut) {
        amountsOut = new uint256[](fills.length);
        for (uint256 i = 0; i < fills.length; i++) {
            amountsOut[i] = _fillOrderInternal(fills[i]);
        }
    }

    /**
     * @notice Fill an RFQ quote
     * @param quote Quote from market maker
     */
    function fillQuote(
        Quote calldata quote
    ) external nonReentrant whenNotPaused returns (uint256) {
        // Validate
        if (block.timestamp > quote.deadline) revert OrderExpired();
        if (quote.taker != msg.sender && quote.taker != address(0)) revert InvalidTaker();
        if (usedNonces[quote.maker][quote.nonce]) revert NonceUsed();

        // Verify signature
        bytes32 quoteHash = _hashQuote(quote);
        address signer = ECDSA.recover(_hashTypedDataV4(quoteHash), quote.signature);
        if (signer != quote.maker) revert InvalidSignature();

        // Mark nonce used
        usedNonces[quote.maker][quote.nonce] = true;

        // Execute swap
        IERC20(quote.tokenIn).safeTransferFrom(msg.sender, quote.maker, quote.amountIn);
        IERC20(quote.tokenOut).safeTransferFrom(quote.maker, msg.sender, quote.amountOut);

        emit QuoteFilled(quoteHash, quote.maker, msg.sender, quote.amountIn, quote.amountOut);

        return quote.amountOut;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ORDER MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancel an order by invalidating its nonce
     * @param nonce Nonce to cancel
     */
    function cancelOrder(uint256 nonce) external {
        usedNonces[msg.sender][nonce] = true;
        emit OrderCanceled(msg.sender, nonce);
    }

    /**
     * @notice Cancel multiple orders
     * @param nonces Array of nonces to cancel
     */
    function cancelOrders(uint256[] calldata nonces) external {
        for (uint256 i = 0; i < nonces.length; i++) {
            usedNonces[msg.sender][nonces[i]] = true;
            emit OrderCanceled(msg.sender, nonces[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get order hash
    function getOrderHash(Order calldata order) external view returns (bytes32) {
        return _hashTypedDataV4(_hashOrder(order));
    }

    /// @notice Get quote hash
    function getQuoteHash(Quote calldata quote) external view returns (bytes32) {
        return _hashTypedDataV4(_hashQuote(quote));
    }

    /// @notice Check if order is valid
    function isOrderValid(
        Order calldata order,
        bytes calldata signature
    ) external view returns (bool) {
        bytes32 orderHash = _hashOrder(order);
        address signer = ECDSA.recover(_hashTypedDataV4(orderHash), signature);

        if (signer != order.maker) return false;
        if (block.timestamp > order.deadline) return false;
        if (order.startTime > 0 && block.timestamp < order.startTime) return false;
        if (usedNonces[order.maker][order.nonce]) return false;
        if (filledAmounts[orderHash] >= order.amountIn) return false;

        return true;
    }

    /// @notice Get remaining fillable amount
    function getRemainingAmount(
        Order calldata order
    ) external view returns (uint256) {
        bytes32 orderHash = _hashOrder(order);
        return order.amountIn - filledAmounts[orderHash];
    }

    /// @notice Calculate expected output for current time
    function getExpectedOutput(
        Order calldata order,
        uint256 fillAmount
    ) external view returns (uint256) {
        return _calculateExpectedOutput(order, fillAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setSolver(address solver, bool approved) external onlyRole(ADMIN_ROLE) {
        approvedSolvers[solver] = approved;
        emit SolverUpdated(solver, approved);
    }

    function registerPartner(
        bytes32 code,
        address receiver,
        uint256 feeBps
    ) external onlyRole(ADMIN_ROLE) {
        require(feeBps <= 500, "Fee too high"); // Max 5%
        partnerFees[code] = feeBps;
        partnerReceivers[code] = receiver;
        emit PartnerRegistered(code, receiver, feeBps);
    }

    function setProtocolFee(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        require(_feeBps <= 100, "Fee too high"); // Max 1%
        protocolFeeBps = _feeBps;
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _validateOrder(Order calldata order) internal view {
        if (block.timestamp > order.deadline) revert OrderExpired();
        if (order.startTime > 0 && block.timestamp < order.startTime) revert OrderNotStarted();
        if (usedNonces[order.maker][order.nonce]) revert NonceUsed();
        if (order.taker != address(0) && order.taker != msg.sender) revert InvalidTaker();
        if (order.amountIn == 0 || order.amountOutMin == 0) revert InvalidOrder();
    }

    function _hashOrder(Order calldata order) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.maker,
            order.taker,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.amountOutMin,
            order.amountOutMax,
            order.nonce,
            order.deadline,
            order.startTime,
            uint8(order.orderType),
            order.partnerCode
        ));
    }

    function _hashQuote(Quote calldata quote) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            QUOTE_TYPEHASH,
            quote.maker,
            quote.taker,
            quote.tokenIn,
            quote.tokenOut,
            quote.amountIn,
            quote.amountOut,
            quote.deadline,
            quote.nonce
        ));
    }

    function _calculateExpectedOutput(
        Order calldata order,
        uint256 fillAmount
    ) internal view returns (uint256) {
        // Pro-rata for partial fills
        uint256 baseOutput = (order.amountOutMin * fillAmount) / order.amountIn;

        if (order.orderType != OrderType.DUTCH_AUCTION) {
            return baseOutput;
        }

        // Dutch auction decay
        if (order.startTime == 0 || order.amountOutMax == 0) {
            return baseOutput;
        }

        uint256 elapsed = block.timestamp - order.startTime;
        uint256 duration = order.deadline - order.startTime;

        if (elapsed >= duration) {
            return baseOutput; // Decayed to minimum
        }

        // Linear decay from max to min
        uint256 maxOutput = (order.amountOutMax * fillAmount) / order.amountIn;
        uint256 decay = ((maxOutput - baseOutput) * elapsed) / duration;

        return maxOutput - decay;
    }

    function _calculateFees(
        uint256 amount,
        bytes32 partnerCode
    ) internal view returns (uint256 protocolFee, uint256 partnerFee) {
        protocolFee = (amount * protocolFeeBps) / BPS;

        if (partnerCode != bytes32(0) && partnerFees[partnerCode] > 0) {
            partnerFee = (amount * partnerFees[partnerCode]) / BPS;
        }
    }

    function _fillOrderInternal(Fill calldata fill) internal returns (uint256) {
        // Simplified version for batch - reuse main logic
        Order calldata order = fill.order;

        bytes32 orderHash = _hashOrder(order);
        address signer = ECDSA.recover(_hashTypedDataV4(orderHash), fill.signature);
        if (signer != order.maker) return 0;

        if (block.timestamp > order.deadline) return 0;
        if (usedNonces[order.maker][order.nonce]) return 0;

        uint256 remaining = order.amountIn - filledAmounts[orderHash];
        if (remaining == 0) return 0;

        uint256 fillAmount = fill.fillAmount > remaining ? remaining : fill.fillAmount;
        uint256 expectedOut = _calculateExpectedOutput(order, fillAmount);

        // Transfer and execute
        IERC20(order.tokenIn).safeTransferFrom(order.maker, address(this), fillAmount);
        IERC20(order.tokenOut).safeTransferFrom(msg.sender, order.maker, expectedOut);

        filledAmounts[orderHash] += fillAmount;

        emit OrderFilled(
            orderHash,
            order.maker,
            msg.sender,
            order.tokenIn,
            order.tokenOut,
            fillAmount,
            expectedOut,
            order.partnerCode
        );

        return expectedOut;
    }
}
