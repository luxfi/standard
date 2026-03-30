// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { IFutures } from "../interfaces/futures/IFutures.sol";
import { IFuturesMargin } from "../interfaces/futures/IFuturesMargin.sol";
import { IOracle } from "../oracle/IOracle.sol";

/**
 * @title FuturesSettlement
 * @author Lux Industries
 * @notice Settlement engine for traditional dated futures at expiry
 * @dev Handles both cash and physical delivery settlement modes
 *
 * Key features:
 * - Cash settlement: pay/receive difference between last settlement price and final price
 * - Physical delivery: actual underlying token transfer at contract price
 * - Auto-settle all open positions at expiry via keeper
 * - Settlement price sourced from oracle with staleness check
 * - Batched processing to avoid gas limits
 */
contract FuturesSettlement is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10_000;

    /// @notice Maximum positions to settle in one transaction
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice Maximum oracle price age for settlement (1 hour)
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Settlement record for a trader
    struct SettlementRecord {
        address trader;
        int256 pnl;
        uint256 marginReturned;
        bool physicalDelivery;
        uint256 settledAt;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Futures contract reference
    IFutures public futures;

    /// @notice Margin engine reference
    IFuturesMargin public marginEngine;

    /// @notice Price oracle
    IOracle public oracle;

    /// @notice Fee receiver for settlement fees
    address public feeReceiver;

    /// @notice Settlement fee in basis points
    uint256 public settlementFeeBps = 2; // 0.02%

    /// @notice Whether a contract has been finally settled
    mapping(uint256 => bool) public isSettled;

    /// @notice Final settlement price per contract
    mapping(uint256 => uint256) public finalPrices;

    /// @notice Settlement timestamp per contract
    mapping(uint256 => uint256) public settlementTimestamps;

    /// @notice Settlement records: contractId => trader => record
    mapping(uint256 => mapping(address => SettlementRecord)) public settlements;

    /// @notice Number of positions settled per contract
    mapping(uint256 => uint256) public settledCount;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event FinalPriceSet(uint256 indexed contractId, uint256 finalPrice, uint256 timestamp);

    event PositionSettled(
        uint256 indexed contractId,
        address indexed trader,
        IFutures.Side side,
        uint256 size,
        int256 pnl,
        uint256 marginReturned
    );

    event PhysicalDelivery(
        uint256 indexed contractId, address indexed buyer, address indexed seller, uint256 underlyingAmount
    );

    event BatchSettlementComplete(uint256 indexed contractId, uint256 positionsSettled, uint256 remaining);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ContractNotExpired();
    error ContractNotFound();
    error AlreadySettled();
    error NotSettled();
    error PriceStale();
    error ZeroAddress();
    error AlreadySettledTrader();
    error NothingToSettle();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _futures, address _marginEngine, address _oracle, address _feeReceiver, address _admin) {
        if (_futures == address(0) || _marginEngine == address(0) || _oracle == address(0)) revert ZeroAddress();

        futures = IFutures(_futures);
        marginEngine = IFuturesMargin(_marginEngine);
        oracle = IOracle(_oracle);
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(KEEPER_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FINAL SETTLEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set the final settlement price for an expired contract
     * @dev Must be called by KEEPER_ROLE after contract expiry. Price sourced from oracle.
     * @param contractId Futures contract ID
     */
    function setFinalPrice(uint256 contractId) external onlyRole(KEEPER_ROLE) {
        if (isSettled[contractId]) revert AlreadySettled();

        IFutures.ContractSpec memory spec = futures.getContract(contractId);
        if (!spec.exists) revert ContractNotFound();
        if (block.timestamp < spec.expiryDate) revert ContractNotExpired();

        // Get oracle price with staleness check
        (uint256 price, uint256 timestamp) = oracle.getPrice(spec.underlying);
        if (block.timestamp - timestamp > MAX_PRICE_AGE) revert PriceStale();

        finalPrices[contractId] = price;
        settlementTimestamps[contractId] = block.timestamp;
        isSettled[contractId] = true;

        emit FinalPriceSet(contractId, price, block.timestamp);
    }

    /**
     * @notice Batch-settle open positions for an expired contract (cash settlement)
     * @dev Called by KEEPER_ROLE after setFinalPrice. Processes up to MAX_BATCH_SIZE positions.
     *      Call repeatedly until all positions are settled.
     * @param contractId Futures contract ID
     * @param traders Array of trader addresses to settle
     */
    function settleCashBatch(uint256 contractId, address[] calldata traders) external onlyRole(KEEPER_ROLE) nonReentrant {
        if (!isSettled[contractId]) revert NotSettled();
        if (traders.length == 0) revert NothingToSettle();

        IFutures.ContractSpec memory spec = futures.getContract(contractId);
        uint256 finalPrice = finalPrices[contractId];

        uint256 processed = 0;

        for (uint256 i = 0; i < traders.length && processed < MAX_BATCH_SIZE; i++) {
            address trader = traders[i];

            // Skip if already settled
            if (settlements[contractId][trader].settledAt > 0) continue;

            IFutures.Position memory pos = futures.getPosition(contractId, trader);

            // Skip if not open
            if (pos.status != IFutures.PositionStatus.OPEN) continue;

            // Calculate PnL from last settlement price to final price
            int256 pnl = _calculatePnl(pos.side, pos.size, pos.lastSettlementPrice, finalPrice, spec.contractSize);

            // Get margin from margin engine
            uint256 marginBalance = marginEngine.getEffectiveBalance(contractId, trader);

            // Net settlement: margin + pnl - fee
            uint256 notional = (pos.size * spec.contractSize * finalPrice) / PRECISION;
            uint256 fee = (notional * settlementFeeBps) / BPS;

            int256 netAmount = int256(marginBalance) + pnl - int256(fee);

            // Record settlement
            settlements[contractId][trader] = SettlementRecord({
                trader: trader,
                pnl: pnl,
                marginReturned: netAmount > 0 ? uint256(netAmount) : 0,
                physicalDelivery: false,
                settledAt: block.timestamp
            });

            // Transfer settlement amount to trader
            if (netAmount > 0) {
                IERC20(spec.quote).safeTransfer(trader, uint256(netAmount));
            }

            // Transfer fee
            if (fee > 0 && feeReceiver != address(0)) {
                IERC20(spec.quote).safeTransfer(feeReceiver, fee);
            }

            settledCount[contractId]++;
            processed++;

            emit PositionSettled(contractId, trader, pos.side, pos.size, pnl, netAmount > 0 ? uint256(netAmount) : 0);
        }

        emit BatchSettlementComplete(contractId, processed, traders.length - processed);
    }

    /**
     * @notice Settle a position with physical delivery of the underlying
     * @dev For physical delivery contracts. Buyer receives underlying, seller receives quote.
     *      Both parties must have approved this contract for the respective token transfers.
     * @param contractId Futures contract ID
     * @param buyer Address of the long position holder
     * @param seller Address of the short position holder
     */
    function settlePhysical(uint256 contractId, address buyer, address seller)
        external
        onlyRole(KEEPER_ROLE)
        nonReentrant
    {
        if (!isSettled[contractId]) revert NotSettled();

        IFutures.ContractSpec memory spec = futures.getContract(contractId);
        if (spec.settlement != IFutures.SettlementType.PHYSICAL) revert NothingToSettle();

        if (settlements[contractId][buyer].settledAt > 0) revert AlreadySettledTrader();
        if (settlements[contractId][seller].settledAt > 0) revert AlreadySettledTrader();

        IFutures.Position memory buyerPos = futures.getPosition(contractId, buyer);
        IFutures.Position memory sellerPos = futures.getPosition(contractId, seller);

        if (buyerPos.status != IFutures.PositionStatus.OPEN || buyerPos.side != IFutures.Side.LONG) {
            revert NothingToSettle();
        }
        if (sellerPos.status != IFutures.PositionStatus.OPEN || sellerPos.side != IFutures.Side.SHORT) {
            revert NothingToSettle();
        }

        // Determine delivery quantity (min of both positions)
        uint256 deliverySize = buyerPos.size < sellerPos.size ? buyerPos.size : sellerPos.size;
        uint256 underlyingAmount = (deliverySize * spec.contractSize) / PRECISION;
        uint256 quoteAmount = (deliverySize * spec.contractSize * finalPrices[contractId]) / (PRECISION * PRECISION);

        // Fee
        uint256 fee = (quoteAmount * settlementFeeBps) / BPS;

        // Seller delivers underlying to buyer
        IERC20(spec.underlying).safeTransferFrom(seller, buyer, underlyingAmount);

        // Buyer pays quote amount to seller (from their margin or direct)
        uint256 buyerMargin = marginEngine.getEffectiveBalance(contractId, buyer);
        uint256 buyerPayment = quoteAmount + fee;

        // Use margin first, then require additional payment
        if (buyerMargin >= buyerPayment) {
            // Margin covers payment + fee
            IERC20(spec.quote).safeTransfer(seller, quoteAmount);
            if (fee > 0 && feeReceiver != address(0)) {
                IERC20(spec.quote).safeTransfer(feeReceiver, fee);
            }

            // Return remaining margin to buyer
            uint256 remaining = buyerMargin - buyerPayment;
            if (remaining > 0) {
                IERC20(spec.quote).safeTransfer(buyer, remaining);
            }
        }

        // Return seller's margin
        uint256 sellerMargin = marginEngine.getEffectiveBalance(contractId, seller);
        if (sellerMargin > 0) {
            IERC20(spec.quote).safeTransfer(seller, sellerMargin);
        }

        // Record settlements
        settlements[contractId][buyer] = SettlementRecord({
            trader: buyer,
            pnl: 0, // Physical delivery — PnL is implicit in delivery
            marginReturned: buyerMargin > buyerPayment ? buyerMargin - buyerPayment : 0,
            physicalDelivery: true,
            settledAt: block.timestamp
        });

        settlements[contractId][seller] = SettlementRecord({
            trader: seller,
            pnl: 0,
            marginReturned: sellerMargin + quoteAmount,
            physicalDelivery: true,
            settledAt: block.timestamp
        });

        settledCount[contractId] += 2;

        emit PhysicalDelivery(contractId, buyer, seller, underlyingAmount);
        emit PositionSettled(contractId, buyer, IFutures.Side.LONG, deliverySize, 0, 0);
        emit PositionSettled(contractId, seller, IFutures.Side.SHORT, deliverySize, 0, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get settlement record for a trader
    function getSettlement(uint256 contractId, address trader) external view returns (SettlementRecord memory) {
        return settlements[contractId][trader];
    }

    /// @notice Get final settlement price
    function getFinalPrice(uint256 contractId) external view returns (uint256) {
        return finalPrices[contractId];
    }

    /// @notice Check if a specific trader has been settled
    function isTraderSettled(uint256 contractId, address trader) external view returns (bool) {
        return settlements[contractId][trader].settledAt > 0;
    }

    /// @notice Calculate expected cash settlement for a trader
    function calculateSettlement(uint256 contractId, address trader)
        external
        view
        returns (int256 pnl, uint256 marginReturn, uint256 fee)
    {
        if (!isSettled[contractId]) return (0, 0, 0);

        IFutures.ContractSpec memory spec = futures.getContract(contractId);
        IFutures.Position memory pos = futures.getPosition(contractId, trader);
        uint256 finalPrice = finalPrices[contractId];

        if (pos.status != IFutures.PositionStatus.OPEN) return (0, 0, 0);

        pnl = _calculatePnl(pos.side, pos.size, pos.lastSettlementPrice, finalPrice, spec.contractSize);

        uint256 marginBalance = marginEngine.getEffectiveBalance(contractId, trader);
        uint256 notional = (pos.size * spec.contractSize * finalPrice) / PRECISION;
        fee = (notional * settlementFeeBps) / BPS;

        int256 net = int256(marginBalance) + pnl - int256(fee);
        marginReturn = net > 0 ? uint256(net) : 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert ZeroAddress();
        oracle = IOracle(_oracle);
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function setSettlementFee(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        settlementFeeBps = _feeBps;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _calculatePnl(IFutures.Side side, uint256 size, uint256 fromPrice, uint256 toPrice, uint256 contractSize)
        internal
        pure
        returns (int256 pnl)
    {
        int256 priceDelta = int256(toPrice) - int256(fromPrice);
        int256 notionalDelta = (int256(size) * int256(contractSize) * priceDelta) / int256(PRECISION);
        pnl = side == IFutures.Side.LONG ? notionalDelta : -notionalDelta;
    }
}
