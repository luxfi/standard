// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IAmericanOptions
 * @author Lux Industries
 * @notice Interface for American-style options with early exercise and assignment
 * @dev Extends the European Options protocol with pre-expiry exercise
 */
interface IAmericanOptions {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Assignment mode for early exercise
    enum AssignmentMode {
        FIFO,
        PRO_RATA
    }

    /// @notice Writer queue entry tracking order and size
    struct WriterEntry {
        address writer;
        uint256 amount;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when early exercise is attempted on an expired series
    error AlreadyExpired();

    /// @notice Thrown when early exercise is attempted but option is out of the money
    error NotInTheMoney();

    /// @notice Thrown when the writer queue is empty (no writers to assign)
    error NoWritersAvailable();

    /// @notice Thrown when fee basis points exceed maximum
    error FeeTooHigh();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when options are exercised early (before expiry)
    event EarlyExercise(uint256 indexed seriesId, address indexed holder, uint256 amount, uint256 payout, uint256 fee);

    /// @notice Emitted when a writer is assigned due to early exercise
    event WriterAssigned(uint256 indexed seriesId, address indexed writer, uint256 amount, uint256 collateralDeducted);

    /// @notice Emitted when the assignment mode is changed
    event AssignmentModeChanged(uint256 indexed seriesId, AssignmentMode mode);

    /// @notice Emitted when the early exercise fee is changed
    event EarlyExerciseFeeChanged(uint256 oldFeeBps, uint256 newFeeBps);

    // ═══════════════════════════════════════════════════════════════════════
    // EARLY EXERCISE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Exercise options before expiry using current oracle price
     * @param seriesId Option series ID
     * @param amount Number of options to exercise
     * @return payout Net payout after fees
     */
    function exerciseEarly(uint256 seriesId, uint256 amount) external returns (uint256 payout);

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set the assignment mode for a series
     * @param seriesId Option series ID
     * @param mode FIFO or PRO_RATA
     */
    function setAssignmentMode(uint256 seriesId, AssignmentMode mode) external;

    /**
     * @notice Set the early exercise fee in basis points
     * @param feeBps Fee in basis points (e.g., 50 = 0.5%)
     */
    function setEarlyExerciseFeeBps(uint256 feeBps) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the assignment mode for a series
     * @param seriesId Series ID
     * @return mode Current assignment mode
     */
    function getAssignmentMode(uint256 seriesId) external view returns (AssignmentMode mode);

    /**
     * @notice Get the early exercise fee in basis points
     * @return feeBps Fee in basis points
     */
    function earlyExerciseFeeBps() external view returns (uint256 feeBps);

    /**
     * @notice Get the number of writers in the queue for a series
     * @param seriesId Series ID
     * @return count Number of writers
     */
    function getWriterQueueLength(uint256 seriesId) external view returns (uint256 count);

    /**
     * @notice Get a writer entry from the queue
     * @param seriesId Series ID
     * @param index Index in the queue
     * @return entry Writer entry
     */
    function getWriterEntry(uint256 seriesId, uint256 index) external view returns (WriterEntry memory entry);
}
