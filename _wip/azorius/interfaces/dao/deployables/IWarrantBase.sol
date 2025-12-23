// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IWarrantBase
 * @notice Base interface for warrant contracts that allow holders to execute and receive vested tokens
 * @dev This interface defines the core functionality for warrant contracts. A warrant allows
 * a designated holder to pay a fee to receive tokens that will be vested according to
 * implementation-specific rules.
 *
 * Key features:
 * - Single warrant holder with exclusive execution rights
 * - Fee payment in specified token at predetermined price
 * - Support for both absolute and relative time expiration
 * - Owner clawback after expiration if not executed
 *
 * Implementations should handle the actual vesting mechanism (e.g., Hedgey, Sablier)
 * while this base interface provides common warrant functionality.
 */
interface IWarrantBase {
    // --- Errors ---

    /** @notice Thrown when caller is not the designated warrant holder */
    error OnlyWarrantHolder();

    /** @notice Thrown when warrant has already been executed */
    error AlreadyExecuted();

    /** @notice Thrown when warrant has expired and cannot be executed */
    error WarrantExpired();

    /** @notice Thrown when attempting clawback before warrant expiration */
    error WarrantNotExpired();

    /** @notice Thrown when token is still locked (relative time mode only) */
    error TokenLocked();

    /** @notice Thrown when token doesn't support IVotesERC20V1 in relative time mode */
    error UnsupportedToken();

    // --- Events ---

    /**
     * @notice Emitted when warrant is successfully executed
     * @param recipient Address that will receive the vested tokens
     */
    event Executed(address indexed recipient);

    /**
     * @notice Emitted when owner claws back tokens after expiration
     * @param recipient Address that received the clawed back tokens
     * @param amount Amount of tokens clawed back
     */
    event Clawback(address indexed recipient, uint256 amount);

    // --- View Functions ---

    /**
     * @notice Whether the warrant uses relative time based on token unlock
     * @return True if relative time mode, false if absolute time mode
     */
    function relativeTime() external view returns (bool);

    /**
     * @notice The address authorized to execute this warrant
     * @return Address of the warrant holder
     */
    function warrantHolder() external view returns (address);

    /**
     * @notice The token that will be vested upon execution
     * @return Address of the warrant token contract
     */
    function warrantToken() external view returns (address);

    /**
     * @notice The token used for payment
     * @return Address of the payment token contract
     */
    function paymentToken() external view returns (address);

    /**
     * @notice Amount of warrant tokens to be vested
     * @return The warrant token amount
     */
    function warrantTokenAmount() external view returns (uint256);

    /**
     * @notice Price per warrant token in payment token units (18 decimal precision)
     * @return The warrant token price
     */
    function warrantTokenPrice() external view returns (uint256);

    /**
     * @notice Address that receives payment
     * @return The payment receiver address
     */
    function paymentReceiver() external view returns (address);

    /**
     * @notice Expiration timestamp or duration based on time mode
     * @return For absolute time: timestamp when warrant expires
     *         For relative time: duration after token unlock when warrant expires
     */
    function expiration() external view returns (uint256);

    /**
     * @notice Whether the warrant has been executed
     * @return True if executed, false otherwise
     */
    function executed() external view returns (bool);

    // --- State-Changing Functions ---

    /**
     * @notice Execute the warrant by paying the fee and initiating token vesting
     * @dev Only callable by warrant holder before expiration
     * @param recipient_ Address that will receive the vested tokens
     * @custom:throws OnlyWarrantHolder if caller is not the warrant holder
     * @custom:throws AddressZero if recipient is zero address
     * @custom:throws AlreadyExecuted if warrant was already executed
     * @custom:throws Expired if warrant has expired
     * @custom:throws TokenLocked if in relative time mode and token is still locked
     */
    function execute(address recipient_) external;

    /**
     * @notice Owner claws back tokens after warrant expiration
     * @dev Only callable by owner after warrant has expired without execution
     * @param recipient_ Address to receive the clawed back tokens
     * @custom:throws AlreadyExecuted if warrant was already executed
     * @custom:throws WarrantNotExpired if warrant hasn't expired yet
     * @custom:throws TokenLocked if in relative time mode and token is still locked
     */
    function clawback(address recipient_) external;
}
