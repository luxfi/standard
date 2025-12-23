// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IWarrantHedgeyV1
 * @notice Interface for Hedgey-specific warrant implementation
 * @dev This interface defines the Hedgey TokenLockupPlans integration for warrant contracts.
 * The implementation creates a vesting plan through Hedgey when the warrant is executed.
 *
 * Hedgey vesting parameters:
 * - Start time: When vesting begins (absolute or relative to token unlock)
 * - Cliff: Period before any tokens can be claimed
 * - Rate: Amount of tokens vested per period
 * - Period: Time interval for vesting (e.g., daily, monthly)
 *
 * The warrant holder pays a fee to execute and create a Hedgey vesting plan
 * for the recipient address.
 */
interface IWarrantHedgeyV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to execute before hedgeyStart in absolute time mode */
    error HedgeyStartNotElapsed();

    /** @notice Thrown when amount is zero */
    error InvalidAmount();

    /** @notice Thrown when vesting rate is zero */
    error InvalidRate();

    /** @notice Thrown when rate exceeds total amount */
    error RateExceedsAmount();

    /** @notice Thrown when vesting period is zero */
    error InvalidPeriod();

    /** @notice Thrown when token is zero address */
    error InvalidToken();

    /** @notice Thrown when cliff exceeds vesting end time */
    error CliffExceedsEnd(uint256 cliff, uint256 end);

    // --- Structs ---

    /**
     * @notice Parameters for initializing a Hedgey warrant
     * @param relativeTime Whether to use relative time based on token unlock
     * @param owner Owner address who can clawback after expiration
     * @param warrantHolder Address authorized to execute the warrant
     * @param warrantToken Token to be vested
     * @param paymentToken Token used for payment
     * @param warrantTokenAmount Amount of warrant tokens to vest
     * @param warrantTokenPrice Price per warrant token in payment token units (18 decimals)
     * @param paymentReceiver Address that receives payment
     * @param expiration Expiration timestamp or duration
     * @param hedgeyTokenLockupPlans Hedgey contract address
     * @param hedgeyStart Vesting start time (absolute or relative)
     * @param hedgeyRelativeCliff Cliff duration from start
     * @param hedgeyRate Tokens vested per period
     * @param hedgeyPeriod Vesting period duration
     */
    struct InitParams {
        bool relativeTime;
        address owner;
        address warrantHolder;
        address warrantToken;
        address paymentToken;
        uint256 warrantTokenAmount;
        uint256 warrantTokenPrice;
        address paymentReceiver;
        uint256 expiration;
        address hedgeyTokenLockupPlans;
        uint256 hedgeyStart;
        uint256 hedgeyRelativeCliff;
        uint256 hedgeyRate;
        uint256 hedgeyPeriod;
    }

    // --- Events ---

    /**
     * @notice Emitted when a Hedgey vesting plan is created
     * @param planId The ID of the created vesting plan
     * @param recipient The address that will receive the vested tokens
     */
    event HedgeyPlanCreated(uint256 indexed planId, address indexed recipient);

    // --- Initializer Functions ---

    /**
     * @notice Initialize the warrant with Hedgey-specific parameters
     * @param params_ Struct containing all initialization parameters
     */
    function initialize(InitParams calldata params_) external;

    // --- View Functions ---

    /**
     * @notice Address of the Hedgey TokenLockupPlans contract
     * @return The Hedgey contract address for creating vesting plans
     */
    function hedgeyTokenLockupPlans() external view returns (address);

    /**
     * @notice Start time for Hedgey vesting plan
     * @return For absolute time: timestamp when vesting starts
     *         For relative time: offset from token unlock time
     */
    function hedgeyStart() external view returns (uint256);

    /**
     * @notice Cliff duration before tokens can be claimed
     * @return Duration in seconds from hedgeyStart
     */
    function hedgeyRelativeCliff() external view returns (uint256);

    /**
     * @notice Amount of tokens vested per period
     * @return Token amount vested each period
     */
    function hedgeyRate() external view returns (uint256);

    /**
     * @notice Time interval for vesting
     * @return Period duration in seconds
     */
    function hedgeyPeriod() external view returns (uint256);
}
