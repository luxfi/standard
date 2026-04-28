// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IOptionsRouter
 * @author Lux Industries
 * @notice Interface for atomic multi-leg options strategy execution
 * @dev Validates and executes 2-4 leg strategies against an Options contract
 */
interface IOptionsRouter {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Supported multi-leg strategy types
    enum StrategyType {
        VERTICAL_SPREAD,
        IRON_CONDOR,
        BUTTERFLY,
        STRADDLE,
        STRANGLE,
        COLLAR,
        CALENDAR_SPREAD,
        IRON_BUTTERFLY,
        CUSTOM
    }

    /// @notice A single leg of a multi-leg strategy
    struct Leg {
        uint256 seriesId;
        bool isBuy;
        uint256 quantity;
        uint256 maxPremium;
    }

    /// @notice Packed strategy position (up to 4 legs encoded in storage)
    struct StrategyPosition {
        address owner;
        StrategyType strategyType;
        uint256 packedLegs;
        uint256 quantity;
        uint256 collateralLocked;
        bool active;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when no legs provided
    error NoLegs();

    /// @notice Thrown when too many legs (max 4)
    error TooManyLegs();

    /// @notice Thrown when leg count does not match strategy type
    error InvalidLegCount();

    /// @notice Thrown when legs have mismatched underlying assets
    error UnderlyingMismatch();

    /// @notice Thrown when legs have mismatched expiry dates
    error ExpiryMismatch();

    /// @notice Thrown when option types in legs don't match strategy requirements
    error InvalidOptionTypes();

    /// @notice Thrown when strikes are not ordered correctly for the strategy
    error InvalidStrikeOrder();

    /// @notice Thrown when a leg requires both buy and sell but only has one direction
    error InvalidLegDirection();

    /// @notice Thrown when net premium exceeds caller's limit
    error PremiumLimitExceeded();

    /// @notice Thrown when a strategy position does not exist
    error PositionNotFound();

    /// @notice Thrown when caller is not position owner
    error NotPositionOwner();

    /// @notice Thrown when quantity is zero
    error ZeroQuantity();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a strategy is executed
    event StrategyExecuted(
        uint256 indexed positionId,
        address indexed owner,
        StrategyType strategyType,
        uint256 quantity,
        uint256 collateralLocked
    );

    /// @notice Emitted when a strategy position is closed
    event StrategyClosed(uint256 indexed positionId, address indexed owner);

    // ═══════════════════════════════════════════════════════════════════════
    // STRATEGY EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute a multi-leg strategy atomically
     * @param strategyType Type of strategy
     * @param legs Array of strategy legs (2-4 legs)
     * @param netPremiumLimit Maximum net premium the caller is willing to pay (0 for credit strategies)
     * @return positionId Unique position identifier
     */
    function executeStrategy(StrategyType strategyType, Leg[] calldata legs, uint256 netPremiumLimit)
        external
        returns (uint256 positionId);

    /**
     * @notice Close a strategy position (burn/exercise all legs)
     * @param positionId Strategy position ID
     */
    function closeStrategy(uint256 positionId) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate that legs form a valid strategy
     * @param strategyType Type of strategy
     * @param legs Array of legs
     * @return valid True if the legs form a valid strategy
     * @return reason Human-readable reason if invalid
     */
    function validateStrategy(StrategyType strategyType, Leg[] calldata legs)
        external
        view
        returns (bool valid, string memory reason);

    /**
     * @notice Compute the maximum possible loss of a strategy
     * @param strategyType Type of strategy
     * @param legs Array of legs
     * @return maxLoss Maximum loss in quote tokens
     */
    function computeMaxLoss(StrategyType strategyType, Leg[] calldata legs) external view returns (uint256 maxLoss);

    /**
     * @notice Compute the maximum possible gain of a strategy
     * @param strategyType Type of strategy
     * @param legs Array of legs
     * @return maxGain Maximum gain in quote tokens (type(uint256).max for unlimited)
     */
    function computeMaxGain(StrategyType strategyType, Leg[] calldata legs) external view returns (uint256 maxGain);

    /**
     * @notice Compute breakeven prices for a strategy
     * @param strategyType Type of strategy
     * @param legs Array of legs
     * @return breakevenLow Lower breakeven price (0 if none)
     * @return breakevenHigh Upper breakeven price (0 if none)
     */
    function computeBreakeven(StrategyType strategyType, Leg[] calldata legs)
        external
        view
        returns (uint256 breakevenLow, uint256 breakevenHigh);

    /**
     * @notice Get a strategy position
     * @param positionId Position identifier
     * @return position Strategy position data
     */
    function getPosition(uint256 positionId) external view returns (StrategyPosition memory position);
}
