// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IFutures
 * @author Lux Industries
 * @notice Interface for traditional dated futures contracts (CME-style)
 * @dev Supports long/short positions with daily mark-to-market, margin, and settlement at expiry
 */
interface IFutures {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Settlement type at contract expiry
    enum SettlementType {
        CASH,
        PHYSICAL
    }

    /// @notice Position direction
    enum Side {
        LONG,
        SHORT
    }

    /// @notice Position status
    enum PositionStatus {
        OPEN,
        CLOSED,
        LIQUIDATED
    }

    /**
     * @notice Futures contract specification
     * @param underlying Underlying asset address
     * @param quote Quote/margin asset address (e.g., USDL)
     * @param expiryDate Expiration timestamp
     * @param contractSize Size of one contract in underlying units (18 decimals)
     * @param tickSize Minimum price increment (18 decimals)
     * @param initialMarginBps Initial margin requirement in basis points of notional
     * @param maintenanceMarginBps Maintenance margin in basis points of notional
     * @param settlement Cash or physical delivery
     * @param exists Whether this contract spec exists
     */
    struct ContractSpec {
        address underlying;
        address quote;
        uint256 expiryDate;
        uint256 contractSize;
        uint256 tickSize;
        uint256 initialMarginBps;
        uint256 maintenanceMarginBps;
        SettlementType settlement;
        bool exists;
    }

    /**
     * @notice Trader position
     * @param contractId Futures contract ID
     * @param trader Trader address
     * @param side LONG or SHORT
     * @param size Number of contracts
     * @param entryPrice Weighted average entry price (18 decimals)
     * @param margin Deposited margin in quote asset
     * @param realisedPnl Cumulative realised PnL from partial closes and daily settlement
     * @param lastSettlementPrice Price at last daily settlement
     * @param status OPEN, CLOSED, or LIQUIDATED
     */
    struct Position {
        uint256 contractId;
        address trader;
        Side side;
        uint256 size;
        uint256 entryPrice;
        uint256 margin;
        int256 realisedPnl;
        uint256 lastSettlementPrice;
        PositionStatus status;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when contract ID does not exist
    error ContractNotFound();

    /// @notice Thrown when contract has expired
    error ContractExpired();

    /// @notice Thrown when contract has not yet expired
    error ContractNotExpired();

    /// @notice Thrown when contract is already settled
    error ContractAlreadySettled();

    /// @notice Thrown when contract is not yet settled
    error ContractNotSettled();

    /// @notice Thrown when expiry date is invalid
    error InvalidExpiry();

    /// @notice Thrown when contract size is zero
    error InvalidContractSize();

    /// @notice Thrown when tick size is zero
    error InvalidTickSize();

    /// @notice Thrown when margin parameters are invalid
    error InvalidMarginParams();

    /// @notice Thrown when deposited margin is insufficient for initial requirement
    error InsufficientMargin();

    /// @notice Thrown when position does not exist or is not open
    error PositionNotFound();

    /// @notice Thrown when trying to close more contracts than held
    error InsufficientPosition();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when oracle address is invalid
    error InvalidOracle();

    /// @notice Thrown when price is not aligned to tick size
    error PriceNotAlignedToTick();

    /// @notice Thrown when position limit would be exceeded
    error PositionLimitExceeded();

    /// @notice Thrown when caller is not authorized
    error Unauthorized();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when position is not below liquidation threshold
    error NotLiquidatable();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new futures contract spec is created
     * @param contractId Unique contract identifier
     * @param underlying Underlying asset address
     * @param quote Quote asset address
     * @param expiryDate Expiration timestamp
     * @param contractSize Size per contract
     * @param settlement CASH or PHYSICAL
     */
    event ContractCreated(
        uint256 indexed contractId,
        address indexed underlying,
        address indexed quote,
        uint256 expiryDate,
        uint256 contractSize,
        SettlementType settlement
    );

    /**
     * @notice Emitted when a position is opened
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param side LONG or SHORT
     * @param size Number of contracts
     * @param price Entry price
     * @param margin Margin deposited
     */
    event PositionOpened(
        uint256 indexed contractId,
        address indexed trader,
        Side side,
        uint256 size,
        uint256 price,
        uint256 margin
    );

    /**
     * @notice Emitted when a position is increased
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param addedSize Contracts added
     * @param newAvgPrice New weighted average entry price
     * @param addedMargin Additional margin deposited
     */
    event PositionIncreased(
        uint256 indexed contractId,
        address indexed trader,
        uint256 addedSize,
        uint256 newAvgPrice,
        uint256 addedMargin
    );

    /**
     * @notice Emitted when a position is partially or fully closed
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param closedSize Contracts closed
     * @param closePrice Price at close
     * @param pnl Realised PnL from this close
     */
    event PositionClosed(
        uint256 indexed contractId,
        address indexed trader,
        uint256 closedSize,
        uint256 closePrice,
        int256 pnl
    );

    /**
     * @notice Emitted when daily mark-to-market settlement occurs
     * @param contractId Contract identifier
     * @param settlementPrice Daily settlement price
     * @param timestamp Settlement timestamp
     */
    event DailySettlement(uint256 indexed contractId, uint256 settlementPrice, uint256 timestamp);

    /**
     * @notice Emitted when a position is liquidated
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param liquidator Liquidator address
     * @param size Contracts liquidated
     * @param price Liquidation price
     */
    event PositionLiquidated(
        uint256 indexed contractId,
        address indexed trader,
        address indexed liquidator,
        uint256 size,
        uint256 price
    );

    /**
     * @notice Emitted when a margin call is triggered
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param currentMargin Current margin balance
     * @param requiredMargin Required maintenance margin
     */
    event MarginCall(uint256 indexed contractId, address indexed trader, uint256 currentMargin, uint256 requiredMargin);

    /**
     * @notice Emitted when margin is deposited
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param amount Amount deposited
     */
    event MarginDeposited(uint256 indexed contractId, address indexed trader, uint256 amount);

    /**
     * @notice Emitted when excess margin is withdrawn
     * @param contractId Contract identifier
     * @param trader Trader address
     * @param amount Amount withdrawn
     */
    event MarginWithdrawn(uint256 indexed contractId, address indexed trader, uint256 amount);

    /**
     * @notice Emitted when final settlement occurs at expiry
     * @param contractId Contract identifier
     * @param finalPrice Final settlement price
     * @param timestamp Settlement timestamp
     */
    event FinalSettlement(uint256 indexed contractId, uint256 finalPrice, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACT MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new futures contract specification
     * @param underlying Underlying asset address
     * @param quote Quote/margin asset address
     * @param expiryDate Expiration timestamp
     * @param contractSize Size of one contract in underlying units
     * @param tickSize Minimum price increment
     * @param initialMarginBps Initial margin in basis points
     * @param maintenanceMarginBps Maintenance margin in basis points
     * @param settlement Cash or physical delivery
     * @return contractId New contract ID
     */
    function createContract(
        address underlying,
        address quote,
        uint256 expiryDate,
        uint256 contractSize,
        uint256 tickSize,
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps,
        SettlementType settlement
    ) external returns (uint256 contractId);

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Open or increase a futures position
     * @param contractId Futures contract ID
     * @param side LONG or SHORT
     * @param size Number of contracts
     * @param price Limit price (must be tick-aligned)
     * @param marginAmount Margin to deposit
     */
    function openPosition(uint256 contractId, Side side, uint256 size, uint256 price, uint256 marginAmount) external;

    /**
     * @notice Close or reduce a futures position
     * @param contractId Futures contract ID
     * @param size Number of contracts to close
     * @param price Close price
     * @return pnl Realised PnL
     */
    function closePosition(uint256 contractId, uint256 size, uint256 price) external returns (int256 pnl);

    // ═══════════════════════════════════════════════════════════════════════
    // MARGIN
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit additional margin to a position
     * @param contractId Futures contract ID
     * @param amount Amount of quote asset to deposit
     */
    function depositMargin(uint256 contractId, uint256 amount) external;

    /**
     * @notice Withdraw excess margin from a position
     * @param contractId Futures contract ID
     * @param amount Amount of quote asset to withdraw
     */
    function withdrawMargin(uint256 contractId, uint256 amount) external;

    // ═══════════════════════════════════════════════════════════════════════
    // SETTLEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Perform daily mark-to-market settlement for a contract
     * @dev Must be called by KEEPER_ROLE
     * @param contractId Futures contract ID
     */
    function dailySettlement(uint256 contractId) external;

    /**
     * @notice Liquidate an under-margined position
     * @param contractId Futures contract ID
     * @param trader Address of the trader to liquidate
     */
    function liquidate(uint256 contractId, address trader) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get contract specification
     * @param contractId Contract identifier
     * @return Contract spec data
     */
    function getContract(uint256 contractId) external view returns (ContractSpec memory);

    /**
     * @notice Get a trader's position
     * @param contractId Contract identifier
     * @param trader Trader address
     * @return Position data
     */
    function getPosition(uint256 contractId, address trader) external view returns (Position memory);

    /**
     * @notice Get unrealised PnL for a position at a given mark price
     * @param contractId Contract identifier
     * @param trader Trader address
     * @return pnl Unrealised PnL (negative = loss)
     */
    function getUnrealisedPnl(uint256 contractId, address trader) external view returns (int256 pnl);

    /**
     * @notice Get total open interest for a contract (in number of contracts)
     * @param contractId Contract identifier
     * @return longOI Long open interest
     * @return shortOI Short open interest
     */
    function getOpenInterest(uint256 contractId) external view returns (uint256 longOI, uint256 shortOI);

    /**
     * @notice Check if a position is liquidatable
     * @param contractId Contract identifier
     * @param trader Trader address
     * @return True if position margin is below maintenance requirement
     */
    function isLiquidatable(uint256 contractId, address trader) external view returns (bool);
}
