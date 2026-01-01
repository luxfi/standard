// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @notice Configuration for dispute bonds per token
struct DisputeBondConfig {
    /// @notice Minimum bond required to dispute a price
    uint256 minBond;
    /// @notice Maximum bond allowed (0 = no maximum)
    uint256 maxBond;
    /// @notice Whether custom bond config is enabled for this token
    bool customBondEnabled;
}

/// @notice Data for an active price dispute
struct PriceDispute {
    /// @notice Token whose price is disputed
    address token;
    /// @notice The disputed price from FastPriceFeed
    uint256 disputedPrice;
    /// @notice The correct price claimed by disputer
    uint256 claimedPrice;
    /// @notice Timestamp when dispute was created
    uint256 timestamp;
    /// @notice Address that initiated the dispute
    address disputer;
    /// @notice Bond amount posted by disputer
    uint256 bond;
    /// @notice Whether dispute has been resolved
    bool resolved;
    /// @notice Whether disputer won (price was incorrect)
    bool disputerWon;
}

/// @title IDisputer
/// @notice Interface for disputing perps oracle prices
interface IDisputer {
    // ============ Events ============

    /// @notice Emitted when a price dispute is initiated
    event PriceDisputeCreated(
        bytes32 indexed disputeId,
        address indexed token,
        address indexed disputer,
        uint256 disputedPrice,
        uint256 claimedPrice,
        uint256 bond
    );

    /// @notice Emitted when a dispute is resolved
    event PriceDisputeResolved(
        bytes32 indexed disputeId,
        address indexed token,
        bool disputerWon,
        uint256 resolvedPrice
    );

    /// @notice Emitted when circuit breaker is triggered
    event CircuitBreakerTriggered(
        address indexed token,
        uint256 incorrectPrice,
        uint256 correctPrice
    );

    /// @notice Emitted when default bond config is updated
    event DefaultBondConfigUpdated(uint256 minBond, uint256 maxBond);

    /// @notice Emitted when token-specific bond config is updated
    event TokenBondConfigUpdated(
        address indexed token,
        uint256 minBond,
        uint256 maxBond,
        bool enabled
    );

    /// @notice Emitted when circuit breaker threshold is updated
    event CircuitBreakerThresholdUpdated(uint256 newThreshold);

    /// @notice Emitted when an admin is added
    event AdminAdded(address indexed admin);

    /// @notice Emitted when an admin is removed
    event AdminRemoved(address indexed admin);

    // ============ Errors ============

    error NotAdmin();
    error NotOracle();
    error InvalidBondConfig();
    error BondTooLow();
    error BondTooHigh();
    error DisputeAlreadyExists();
    error DisputeNotFound();
    error DisputeAlreadyResolved();
    error InvalidPrice();
    error InvalidToken();
    error PriceNotStale();
    error UnsupportedToken();
    error TransferFailed();

    // ============ Dispute Functions ============

    /// @notice Initiate a dispute against the current FastPriceFeed price
    /// @param token The token whose price to dispute
    /// @param claimedCorrectPrice The price the disputer claims is correct
    /// @param bond The bond amount to post
    /// @return disputeId Unique identifier for this dispute
    function disputePrice(
        address token,
        uint256 claimedCorrectPrice,
        uint256 bond
    ) external returns (bytes32 disputeId);

    /// @notice Settle a dispute after UMA resolution
    /// @param disputeId The dispute to settle
    function settleDispute(bytes32 disputeId) external;

    /// @notice Get dispute data
    /// @param disputeId The dispute identifier
    /// @return The dispute data
    function getDispute(bytes32 disputeId) external view returns (PriceDispute memory);

    /// @notice Check if a dispute exists and is active
    /// @param disputeId The dispute identifier
    /// @return True if dispute exists and is not resolved
    function isDisputeActive(bytes32 disputeId) external view returns (bool);

    // ============ Bond Configuration ============

    /// @notice Set default bond configuration
    /// @param minBond Minimum bond amount
    /// @param maxBond Maximum bond amount (0 = no max)
    function setDefaultBondConfig(uint256 minBond, uint256 maxBond) external;

    /// @notice Set token-specific bond configuration
    /// @param token The token address
    /// @param minBond Minimum bond amount
    /// @param maxBond Maximum bond amount (0 = no max)
    /// @param enabled Whether to use custom config for this token
    function setTokenBondConfig(
        address token,
        uint256 minBond,
        uint256 maxBond,
        bool enabled
    ) external;

    /// @notice Get effective bond config for a token
    /// @param token The token address
    /// @return minBond The minimum bond
    /// @return maxBond The maximum bond
    function getEffectiveBondConfig(address token)
        external
        view
        returns (uint256 minBond, uint256 maxBond);

    // ============ Circuit Breaker ============

    /// @notice Set the price deviation threshold for circuit breaker
    /// @param thresholdBps Threshold in basis points (e.g., 500 = 5%)
    function setCircuitBreakerThreshold(uint256 thresholdBps) external;

    /// @notice Get current circuit breaker threshold
    /// @return Threshold in basis points
    function circuitBreakerThreshold() external view returns (uint256);

    /// @notice Check if circuit breaker is active for a token
    /// @param token The token to check
    /// @return True if circuit breaker is active
    function isCircuitBreakerActive(address token) external view returns (bool);

    /// @notice Reset circuit breaker for a token (admin only)
    /// @param token The token to reset
    function resetCircuitBreaker(address token) external;

    // ============ Admin Functions ============

    /// @notice Add an admin
    /// @param admin Address to add as admin
    function addAdmin(address admin) external;

    /// @notice Remove an admin
    /// @param admin Address to remove
    function removeAdmin(address admin) external;

    /// @notice Check if address is admin
    /// @param addr Address to check
    /// @return True if admin
    function isAdmin(address addr) external view returns (bool);

    // ============ View Functions ============

    /// @notice Get the FastPriceFeed address
    function fastPriceFeed() external view returns (address);

    /// @notice Get the VaultPriceFeed address
    function vaultPriceFeed() external view returns (address);

    /// @notice Get the Optimistic Oracle address
    function optimisticOracle() external view returns (address);

    /// @notice Get the bond token address
    function bondToken() external view returns (address);

    /// @notice Get the dispute liveness period
    function liveness() external view returns (uint256);
}
