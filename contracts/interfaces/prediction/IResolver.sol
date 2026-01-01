// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @notice Data structure for a prediction market question
struct QuestionData {
    /// @notice Request timestamp, set when a request is made to the Optimistic Oracle
    /// @dev Used to identify the request and NOT used by the DVM to determine validity
    uint256 requestTimestamp;
    /// @notice Reward offered to a successful proposer
    uint256 reward;
    /// @notice Additional bond required by Optimistic oracle proposers/disputers
    uint256 proposalBond;
    /// @notice Custom liveness period
    uint256 liveness;
    /// @notice Manual resolution timestamp, set when a market is flagged for manual resolution
    uint256 manualResolutionTimestamp;
    /// @notice Flag marking whether a question is resolved
    bool resolved;
    /// @notice Flag marking whether a question is paused
    bool paused;
    /// @notice Flag marking whether a question has been reset. A question can only be reset once
    bool reset;
    /// @notice Flag marking whether a question's reward should be refunded
    bool refund;
    /// @notice ERC20 token address used for payment of rewards, proposal bonds and fees
    address rewardToken;
    /// @notice The address of the question creator
    address creator;
    /// @notice Data used to resolve a condition
    bytes ancillaryData;
}

/// @notice Configuration for per-market bond amounts
struct BondConfig {
    /// @notice Minimum bond amount for this market
    uint256 minBond;
    /// @notice Maximum bond amount for this market (0 = no maximum)
    uint256 maxBond;
    /// @notice Whether this market uses custom bond configuration
    bool customBondEnabled;
}

/// @notice Data structure for ancillary data updates
struct AncillaryDataUpdate {
    uint256 timestamp;
    bytes update;
}

/// @title IResolverErrors
/// @notice Error definitions for Resolver
interface IResolverErrors {
    error NotInitialized();
    error NotFlagged();
    error NotReadyToResolve();
    error Resolved();
    error Initialized();
    error UnsupportedToken();
    error Flagged();
    error Paused();
    error SafetyPeriodPassed();
    error SafetyPeriodNotPassed();
    error PriceNotAvailable();
    error InvalidAncillaryData();
    error NotOracle();
    error InvalidOOPrice();
    error InvalidPayouts();
    error NotAdmin();
    error BondTooLow();
    error BondTooHigh();
    error InvalidBondConfig();
}

/// @title IResolverEvents
/// @notice Event definitions for Resolver
interface IResolverEvents {
    /// @notice Emitted when a questionID is initialized
    event QuestionInitialized(
        bytes32 indexed questionID,
        uint256 indexed requestTimestamp,
        address indexed creator,
        bytes ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond
    );

    /// @notice Emitted when a question is paused by an authorized user
    event QuestionPaused(bytes32 indexed questionID);

    /// @notice Emitted when a question is unpaused by an authorized user
    event QuestionUnpaused(bytes32 indexed questionID);

    /// @notice Emitted when a question is flagged by an admin for manual resolution
    event QuestionFlagged(bytes32 indexed questionID);

    /// @notice Emitted when a question is unflagged by an admin
    event QuestionUnflagged(bytes32 indexed questionID);

    /// @notice Emitted when a question is reset
    event QuestionReset(bytes32 indexed questionID);

    /// @notice Emitted when a question is resolved
    event QuestionResolved(bytes32 indexed questionID, int256 indexed settledPrice, uint256[] payouts);

    /// @notice Emitted when a question is manually resolved
    event QuestionManuallyResolved(bytes32 indexed questionID, uint256[] payouts);

    /// @notice Emitted when an ancillary data update is posted
    event AncillaryDataUpdated(bytes32 indexed questionID, address indexed owner, bytes update);

    /// @notice Emitted when a new admin is added
    event NewAdmin(address indexed admin, address indexed newAdminAddress);

    /// @notice Emitted when an admin is removed
    event RemovedAdmin(address indexed admin, address indexed removedAdmin);

    /// @notice Emitted when default bond configuration is updated
    event DefaultBondConfigUpdated(uint256 minBond, uint256 maxBond);

    /// @notice Emitted when a market-specific bond configuration is set
    event MarketBondConfigUpdated(bytes32 indexed questionID, uint256 minBond, uint256 maxBond, bool enabled);
}

/// @title IResolver
/// @notice Interface for the Lux CTF Adapter (prediction market oracle)
interface IResolver is IResolverErrors, IResolverEvents {
    /// @notice Initializes a question with the Optimistic Oracle
    /// @param ancillaryData Data used to resolve a question
    /// @param rewardToken ERC20 token address used for payment of rewards and fees
    /// @param reward Reward offered to a successful OO proposer
    /// @param proposalBond Bond required to be posted by OO proposers/disputers
    /// @param liveness OO liveness period in seconds
    /// @return questionID The unique identifier for the question
    function initialize(
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) external returns (bytes32 questionID);

    /// @notice Checks whether a questionID is ready to be resolved
    /// @param questionID The unique questionID
    /// @return True if the question is ready to resolve
    function ready(bytes32 questionID) external view returns (bool);

    /// @notice Resolves a question
    /// @param questionID The unique questionID of the question
    function resolve(bytes32 questionID) external;

    /// @notice Flags a market for manual resolution
    /// @param questionID The unique questionID of the question
    function flag(bytes32 questionID) external;

    /// @notice Unflags a market for manual resolution
    /// @param questionID The unique questionID of the question
    function unflag(bytes32 questionID) external;

    /// @notice Resets a question, sending out a new price request
    /// @param questionID The unique questionID
    function reset(bytes32 questionID) external;

    /// @notice Pauses market resolution
    /// @param questionID The unique questionID of the question
    function pause(bytes32 questionID) external;

    /// @notice Unpauses market resolution
    /// @param questionID The unique questionID of the question
    function unpause(bytes32 questionID) external;

    /// @notice Manually resolves a CTF market
    /// @param questionID The unique questionID of the question
    /// @param payouts Array of position payouts for the referenced question
    function resolveManually(bytes32 questionID, uint256[] calldata payouts) external;

    /// @notice Gets the QuestionData for the given questionID
    /// @param questionID The unique questionID
    /// @return The question data
    function getQuestion(bytes32 questionID) external view returns (QuestionData memory);

    /// @notice Gets the expected payout array of the question
    /// @param questionID The unique questionID of the question
    /// @return The expected payouts array
    function getExpectedPayouts(bytes32 questionID) external view returns (uint256[] memory);

    /// @notice Checks if a question is initialized
    /// @param questionID The unique questionID
    /// @return True if initialized
    function isInitialized(bytes32 questionID) external view returns (bool);

    /// @notice Checks if a question has been flagged for manual resolution
    /// @param questionID The unique questionID
    /// @return True if flagged
    function isFlagged(bytes32 questionID) external view returns (bool);

    // ============ Bond Configuration ============

    /// @notice Sets the default bond configuration for all markets
    /// @param minBond Minimum bond amount
    /// @param maxBond Maximum bond amount (0 = no maximum)
    function setDefaultBondConfig(uint256 minBond, uint256 maxBond) external;

    /// @notice Sets a market-specific bond configuration
    /// @param questionID The unique questionID
    /// @param minBond Minimum bond amount for this market
    /// @param maxBond Maximum bond amount for this market (0 = no maximum)
    /// @param enabled Whether to enable custom bond config for this market
    function setMarketBondConfig(
        bytes32 questionID,
        uint256 minBond,
        uint256 maxBond,
        bool enabled
    ) external;

    /// @notice Gets the effective bond configuration for a market
    /// @param questionID The unique questionID
    /// @return minBond The minimum bond amount
    /// @return maxBond The maximum bond amount
    function getEffectiveBondConfig(bytes32 questionID) external view returns (uint256 minBond, uint256 maxBond);

    /// @notice Gets the default bond configuration
    /// @return The default bond config
    function getDefaultBondConfig() external view returns (BondConfig memory);

    /// @notice Gets the market-specific bond configuration
    /// @param questionID The unique questionID
    /// @return The market bond config
    function getMarketBondConfig(bytes32 questionID) external view returns (BondConfig memory);

    // ============ Admin Functions ============

    /// @notice Adds an admin
    /// @param admin The address of the admin
    function addAdmin(address admin) external;

    /// @notice Removes an admin
    /// @param admin The address of the admin to be removed
    function removeAdmin(address admin) external;

    /// @notice Renounces admin privileges from the caller
    function renounceAdmin() external;

    /// @notice Checks if an address is an admin
    /// @param addr The address to be checked
    /// @return True if the address is an admin
    function isAdmin(address addr) external view returns (bool);

    // ============ Bulletin Board Functions ============

    /// @notice Posts an update for a question
    /// @param questionID The unique questionID
    /// @param update The update data
    function postUpdate(bytes32 questionID, bytes memory update) external;

    /// @notice Gets all updates for a questionID and owner
    /// @param questionID The unique questionID
    /// @param owner The address of the question initializer
    /// @return Array of ancillary data updates
    function getUpdates(bytes32 questionID, address owner) external view returns (AncillaryDataUpdate[] memory);

    /// @notice Gets the latest update for a questionID and owner
    /// @param questionID The unique questionID
    /// @param owner The address of the question initializer
    /// @return The latest ancillary data update
    function getLatestUpdate(bytes32 questionID, address owner) external view returns (AncillaryDataUpdate memory);
}
