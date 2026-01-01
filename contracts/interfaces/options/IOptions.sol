// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IOptions
 * @author Lux Industries
 * @notice Interface for European-style options protocol with ERC1155 option tokens
 * @dev Supports calls and puts with cash-settled or physical delivery
 */
interface IOptions {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Option type (call or put)
    enum OptionType {
        CALL,
        PUT
    }

    /// @notice Settlement type (cash or physical delivery)
    enum SettlementType {
        CASH,
        PHYSICAL
    }

    /**
     * @notice Option series definition
     * @param underlying Underlying asset address
     * @param quote Quote asset (collateral for puts, payment for calls)
     * @param strikePrice Strike price in quote decimals
     * @param expiry Expiration timestamp
     * @param optionType CALL or PUT
     * @param settlement CASH or PHYSICAL
     * @param exists Whether this series exists
     */
    struct OptionSeries {
        address underlying;
        address quote;
        uint256 strikePrice;
        uint256 expiry;
        OptionType optionType;
        SettlementType settlement;
        bool exists;
    }

    /**
     * @notice Writer position data
     * @param written Options written (short position)
     * @param collateral Collateral deposited
     */
    struct Position {
        uint256 written;
        uint256 collateral;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when series ID does not exist
    error SeriesNotFound();

    /// @notice Thrown when series has already expired
    error SeriesExpired();

    /// @notice Thrown when series has not yet expired
    error SeriesNotExpired();

    /// @notice Thrown when series is already settled
    error SeriesAlreadySettled();

    /// @notice Thrown when series is not yet settled
    error SeriesNotSettled();

    /// @notice Thrown when expiry is invalid
    error InvalidExpiry();

    /// @notice Thrown when strike price is invalid
    error InvalidStrike();

    /// @notice Thrown when collateral is insufficient
    error InsufficientCollateral();

    /// @notice Thrown when option balance is insufficient
    error InsufficientOptions();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when oracle address is invalid
    error InvalidOracle();

    /// @notice Thrown when option is out of the money
    error OutOfTheMoney();

    /// @notice Thrown when position does not exist
    error NoPosition();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new option series is created
     * @param seriesId Unique series identifier
     * @param underlying Underlying asset address
     * @param quote Quote asset address
     * @param strikePrice Strike price
     * @param expiry Expiration timestamp
     * @param optionType CALL or PUT
     * @param settlement CASH or PHYSICAL
     */
    event SeriesCreated(
        uint256 indexed seriesId,
        address indexed underlying,
        address indexed quote,
        uint256 strikePrice,
        uint256 expiry,
        OptionType optionType,
        SettlementType settlement
    );

    /**
     * @notice Emitted when options are written
     * @param seriesId Series identifier
     * @param writer Writer address
     * @param amount Number of options written
     * @param collateral Collateral deposited
     */
    event OptionsWritten(
        uint256 indexed seriesId,
        address indexed writer,
        uint256 amount,
        uint256 collateral
    );

    /**
     * @notice Emitted when options are burned
     * @param seriesId Series identifier
     * @param writer Writer address
     * @param amount Number of options burned
     * @param collateralReturned Collateral returned
     */
    event OptionsBurned(
        uint256 indexed seriesId,
        address indexed writer,
        uint256 amount,
        uint256 collateralReturned
    );

    /**
     * @notice Emitted when options are exercised
     * @param seriesId Series identifier
     * @param holder Holder address
     * @param amount Number of options exercised
     * @param payout Payout amount
     */
    event OptionsExercised(
        uint256 indexed seriesId,
        address indexed holder,
        uint256 amount,
        uint256 payout
    );

    /**
     * @notice Emitted when a series is settled
     * @param seriesId Series identifier
     * @param settlementPrice Settlement price from oracle
     * @param timestamp Settlement timestamp
     */
    event SeriesSettled(
        uint256 indexed seriesId,
        uint256 settlementPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted when collateral is claimed after settlement
     * @param seriesId Series identifier
     * @param writer Writer address
     * @param amount Amount claimed
     */
    event CollateralClaimed(
        uint256 indexed seriesId,
        address indexed writer,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // SERIES MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new option series
     * @dev Must be called by ADMIN_ROLE
     * @param underlying Underlying asset address
     * @param quote Quote asset address (LUSD for most)
     * @param strikePrice Strike price in quote decimals
     * @param expiry Expiration timestamp
     * @param optionType CALL or PUT
     * @param settlement CASH or PHYSICAL
     * @return seriesId New series ID
     */
    function createSeries(
        address underlying,
        address quote,
        uint256 strikePrice,
        uint256 expiry,
        OptionType optionType,
        SettlementType settlement
    ) external returns (uint256 seriesId);

    // ═══════════════════════════════════════════════════════════════════════
    // WRITING & BURNING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Write (sell) options with collateral
     * @param seriesId Option series ID
     * @param amount Number of options to write
     * @param recipient Recipient of option tokens
     * @return collateralRequired Collateral locked
     */
    function write(
        uint256 seriesId,
        uint256 amount,
        address recipient
    ) external returns (uint256 collateralRequired);

    // ═══════════════════════════════════════════════════════════════════════
    // SETTLEMENT & EXERCISE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Settle an expired series with oracle price
     * @dev Must be called by KEEPER_ROLE after expiry
     * @param seriesId Option series ID
     */
    function settle(uint256 seriesId) external;

    /**
     * @notice Exercise options at settlement
     * @param seriesId Option series ID
     * @param amount Number of options to exercise
     * @return payout Payout amount
     */
    function exercise(
        uint256 seriesId,
        uint256 amount
    ) external returns (uint256 payout);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get series details
     * @param seriesId Series identifier
     * @return Series data
     */
    function getSeries(uint256 seriesId) external view returns (OptionSeries memory);

    /**
     * @notice Get writer position
     * @param seriesId Series identifier
     * @param writer Writer address
     * @return Position data
     */
    function getPosition(uint256 seriesId, address writer) external view returns (Position memory);

    /**
     * @notice Calculate collateral required for writing
     * @param seriesId Series identifier
     * @param amount Number of options
     * @return Collateral required
     */
    function getCollateralRequired(uint256 seriesId, uint256 amount) external view returns (uint256);

    /**
     * @notice Calculate exercise payout
     * @param seriesId Series identifier
     * @param amount Number of options
     * @return Payout amount (0 if not settled or out of the money)
     */
    function getExercisePayout(uint256 seriesId, uint256 amount) external view returns (uint256);
}
