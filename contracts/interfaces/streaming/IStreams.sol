// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IStreams
 * @author Lux Industries
 * @notice Interface for token streaming protocol (salaries, vesting, continuous payments)
 * @dev Sablier-style linear/exponential streams represented as ERC721 NFTs
 */
interface IStreams {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Stream curve type
    enum StreamType {
        LINEAR,         // Constant rate
        LINEAR_CLIFF,   // Cliff then linear
        EXPONENTIAL,    // Accelerating release
        UNLOCK_LINEAR   // Discrete unlocks + linear between
    }

    /**
     * @notice Stream data structure
     * @param sender Who funded the stream
     * @param token Token being streamed
     * @param depositAmount Total deposited
     * @param withdrawnAmount Amount already withdrawn
     * @param startTime Stream start timestamp
     * @param endTime Stream end timestamp
     * @param cliffTime Cliff timestamp (0 if no cliff)
     * @param cliffAmount Amount unlocked at cliff
     * @param streamType Type of stream curve
     * @param cancelable Can sender cancel?
     * @param canceled Has been canceled?
     */
    struct Stream {
        address sender;
        address token;
        uint256 depositAmount;
        uint256 withdrawnAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 cliffTime;
        uint256 cliffAmount;
        StreamType streamType;
        bool cancelable;
        bool canceled;
    }

    /**
     * @notice Parameters for creating a stream
     * @param recipient Stream recipient
     * @param token Token to stream
     * @param amount Total amount to stream
     * @param startTime Stream start timestamp
     * @param endTime Stream end timestamp
     * @param cliffTime Cliff timestamp
     * @param cliffAmount Amount unlocked at cliff
     * @param streamType Type of stream curve
     * @param cancelable Whether sender can cancel
     */
    struct CreateParams {
        address recipient;
        address token;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 cliffTime;
        uint256 cliffAmount;
        StreamType streamType;
        bool cancelable;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when duration is invalid
    error InvalidDuration();

    /// @notice Thrown when amount is invalid
    error InvalidAmount();

    /// @notice Thrown when recipient is invalid
    error InvalidRecipient();

    /// @notice Thrown when cliff parameters are invalid
    error InvalidCliff();

    /// @notice Thrown when stream does not exist
    error StreamNotFound();

    /// @notice Thrown when stream is already canceled
    error StreamAlreadyCanceled();

    /// @notice Thrown when stream is not cancelable
    error StreamNotCancelable();

    /// @notice Thrown when caller is not the sender
    error NotSender();

    /// @notice Thrown when caller is not the recipient
    error NotRecipient();

    /// @notice Thrown when nothing is available to withdraw
    error NothingToWithdraw();

    /// @notice Thrown when cliff has not been reached
    error CliffNotReached();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a stream is created
     * @param streamId Stream identifier
     * @param sender Who funded the stream
     * @param recipient Stream recipient
     * @param token Token being streamed
     * @param amount Total amount
     * @param startTime Start timestamp
     * @param endTime End timestamp
     * @param streamType Stream curve type
     */
    event StreamCreated(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        StreamType streamType
    );

    /**
     * @notice Emitted when tokens are withdrawn from a stream
     * @param streamId Stream identifier
     * @param recipient Recipient address
     * @param amount Amount withdrawn
     */
    event Withdrawn(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );

    /**
     * @notice Emitted when a stream is canceled
     * @param streamId Stream identifier
     * @param sender Sender address
     * @param recipientAmount Amount sent to recipient
     * @param senderAmount Amount refunded to sender
     */
    event StreamCanceled(
        uint256 indexed streamId,
        address indexed sender,
        uint256 recipientAmount,
        uint256 senderAmount
    );

    /**
     * @notice Emitted when a stream NFT is transferred
     * @param streamId Stream identifier
     * @param from Previous owner
     * @param to New owner
     */
    event StreamTransferred(
        uint256 indexed streamId,
        address indexed from,
        address indexed to
    );

    /**
     * @notice Emitted when protocol fees are collected
     * @param token Token address
     * @param receiver Fee receiver
     * @param amount Amount collected
     */
    event FeesCollected(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // CREATE STREAMS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new token stream
     * @param params Stream creation parameters
     * @return streamId ID of created stream
     */
    function createStream(CreateParams calldata params) external returns (uint256 streamId);

    /**
     * @notice Create multiple streams in one transaction
     * @param params Array of creation parameters
     * @return streamIds Array of created stream IDs
     */
    function createStreamBatch(CreateParams[] calldata params) external returns (uint256[] memory streamIds);

    /**
     * @notice Create a simple linear stream
     * @param recipient Stream recipient
     * @param token Token to stream
     * @param amount Total amount to stream
     * @param duration Stream duration in seconds
     * @return streamId ID of created stream
     */
    function createLinearStream(
        address recipient,
        address token,
        uint256 amount,
        uint256 duration
    ) external returns (uint256 streamId);

    /**
     * @notice Create a vesting stream with cliff
     * @param recipient Stream recipient
     * @param token Token to stream
     * @param amount Total amount to stream
     * @param cliffDuration Cliff duration in seconds
     * @param totalDuration Total duration in seconds
     * @param cliffPercent Percent unlocked at cliff (BPS, e.g., 2500 = 25%)
     * @return streamId ID of created stream
     */
    function createVestingStream(
        address recipient,
        address token,
        uint256 amount,
        uint256 cliffDuration,
        uint256 totalDuration,
        uint256 cliffPercent
    ) external returns (uint256 streamId);

    // ═══════════════════════════════════════════════════════════════════════
    // WITHDRAW
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Withdraw available tokens from a stream
     * @param streamId Stream ID
     * @return amount Amount withdrawn
     */
    function withdraw(uint256 streamId) external returns (uint256 amount);

    /**
     * @notice Withdraw maximum available from a stream to a specific address
     * @param streamId Stream ID
     * @param recipient Where to send tokens
     * @return amount Amount withdrawn
     */
    function withdrawMax(uint256 streamId, address recipient) external returns (uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // CANCEL
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancel a stream (sender only, if cancelable)
     * @param streamId Stream ID
     * @return recipientAmount Amount sent to recipient
     * @return senderAmount Amount refunded to sender
     */
    function cancel(uint256 streamId) external returns (uint256 recipientAmount, uint256 senderAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get stream details
     * @param streamId Stream identifier
     * @return Stream data
     */
    function getStream(uint256 streamId) external view returns (Stream memory);

    /**
     * @notice Get total streamed amount (vested amount)
     * @param streamId Stream identifier
     * @return Total amount that has streamed so far
     */
    function getStreamedAmount(uint256 streamId) external view returns (uint256);

    /**
     * @notice Get currently withdrawable amount
     * @param streamId Stream identifier
     * @return Amount available to withdraw now
     */
    function getWithdrawableAmount(uint256 streamId) external view returns (uint256);
}
