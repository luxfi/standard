// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Streams
 * @author Lux Industries
 * @notice Token streaming protocol for salaries, vesting, and continuous payments
 * @dev Sablier-style linear/exponential streams represented as ERC721 NFTs
 *
 * Key features:
 * - Linear, cliff, and exponential streaming curves
 * - Stream positions as tradeable NFTs
 * - Cancellable with refund to sender
 * - Supports any ERC20 token
 * - Batch operations for efficiency
 */
contract Streams is ERC721, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum StreamType {
        LINEAR,           // Constant rate
        LINEAR_CLIFF,     // Cliff then linear
        EXPONENTIAL,      // Accelerating release
        UNLOCK_LINEAR     // Discrete unlocks + linear between
    }

    struct Stream {
        address sender;           // Who funded the stream
        address token;            // Token being streamed
        uint256 depositAmount;    // Total deposited
        uint256 withdrawnAmount;  // Amount already withdrawn
        uint256 startTime;        // Stream start timestamp
        uint256 endTime;          // Stream end timestamp
        uint256 cliffTime;        // Cliff timestamp (0 if no cliff)
        uint256 cliffAmount;      // Amount unlocked at cliff
        StreamType streamType;    // Type of stream curve
        bool cancelable;          // Can sender cancel?
        bool canceled;            // Has been canceled?
    }

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
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant MAX_DURATION = 100 * 365 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Streams by ID
    mapping(uint256 => Stream) public streams;

    /// @notice Next stream ID
    uint256 public nextStreamId = 1;

    /// @notice Protocol fee in basis points
    uint256 public protocolFeeBps = 25; // 0.25%

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Accumulated fees by token
    mapping(address => uint256) public accumulatedFees;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

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

    event Withdrawn(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );

    event StreamCanceled(
        uint256 indexed streamId,
        address indexed sender,
        uint256 recipientAmount,
        uint256 senderAmount
    );

    event StreamTransferred(
        uint256 indexed streamId,
        address indexed from,
        address indexed to
    );

    event FeesCollected(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidDuration();
    error InvalidAmount();
    error InvalidRecipient();
    error InvalidCliff();
    error StreamNotFound();
    error StreamAlreadyCanceled();
    error StreamNotCancelable();
    error NotSender();
    error NotRecipient();
    error NothingToWithdraw();
    error CliffNotReached();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _feeReceiver,
        address _admin
    ) ERC721("Lux Streams", "STREAM") {
        feeReceiver = _feeReceiver;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CREATE STREAMS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new token stream
     * @param params Stream creation parameters
     * @return streamId ID of created stream
     */
    function createStream(
        CreateParams calldata params
    ) external nonReentrant whenNotPaused returns (uint256 streamId) {
        return _createStream(params);
    }

    /**
     * @notice Create multiple streams in one transaction
     * @param params Array of creation parameters
     * @return streamIds Array of created stream IDs
     */
    function createStreamBatch(
        CreateParams[] calldata params
    ) external nonReentrant whenNotPaused returns (uint256[] memory streamIds) {
        streamIds = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            streamIds[i] = _createStream(params[i]);
        }
    }

    /**
     * @notice Create a simple linear stream
     * @param recipient Stream recipient
     * @param token Token to stream
     * @param amount Total amount to stream
     * @param duration Stream duration in seconds
     */
    function createLinearStream(
        address recipient,
        address token,
        uint256 amount,
        uint256 duration
    ) external nonReentrant whenNotPaused returns (uint256 streamId) {
        return _createStream(CreateParams({
            recipient: recipient,
            token: token,
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            cliffTime: 0,
            cliffAmount: 0,
            streamType: StreamType.LINEAR,
            cancelable: true
        }));
    }

    /**
     * @notice Create a vesting stream with cliff
     * @param recipient Stream recipient
     * @param token Token to stream
     * @param amount Total amount to stream
     * @param cliffDuration Cliff duration in seconds
     * @param totalDuration Total duration in seconds
     * @param cliffPercent Percent unlocked at cliff (in BPS, e.g., 2500 = 25%)
     */
    function createVestingStream(
        address recipient,
        address token,
        uint256 amount,
        uint256 cliffDuration,
        uint256 totalDuration,
        uint256 cliffPercent
    ) external nonReentrant whenNotPaused returns (uint256 streamId) {
        uint256 cliffAmount = (amount * cliffPercent) / 10000;

        return _createStream(CreateParams({
            recipient: recipient,
            token: token,
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + totalDuration,
            cliffTime: block.timestamp + cliffDuration,
            cliffAmount: cliffAmount,
            streamType: StreamType.LINEAR_CLIFF,
            cancelable: true
        }));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WITHDRAW
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Withdraw available tokens from a stream
     * @param streamId Stream ID
     * @return amount Amount withdrawn
     */
    function withdraw(uint256 streamId) external nonReentrant returns (uint256 amount) {
        Stream storage stream = streams[streamId];
        if (stream.depositAmount == 0) revert StreamNotFound();
        if (stream.canceled) revert StreamAlreadyCanceled();

        address recipient = ownerOf(streamId);
        if (msg.sender != recipient) revert NotRecipient();

        amount = _withdrawableAmount(streamId);
        if (amount == 0) revert NothingToWithdraw();

        stream.withdrawnAmount += amount;

        IERC20(stream.token).safeTransfer(recipient, amount);

        emit Withdrawn(streamId, recipient, amount);
    }

    /**
     * @notice Withdraw from multiple streams
     * @param streamIds Array of stream IDs
     * @return amounts Array of amounts withdrawn
     */
    function withdrawBatch(
        uint256[] calldata streamIds
    ) external nonReentrant returns (uint256[] memory amounts) {
        amounts = new uint256[](streamIds.length);

        for (uint256 i = 0; i < streamIds.length; i++) {
            uint256 streamId = streamIds[i];
            Stream storage stream = streams[streamId];

            if (stream.depositAmount == 0 || stream.canceled) continue;

            address recipient = ownerOf(streamId);
            if (msg.sender != recipient) continue;

            uint256 amount = _withdrawableAmount(streamId);
            if (amount == 0) continue;

            stream.withdrawnAmount += amount;
            amounts[i] = amount;

            IERC20(stream.token).safeTransfer(recipient, amount);

            emit Withdrawn(streamId, recipient, amount);
        }
    }

    /**
     * @notice Withdraw maximum available from a stream
     * @param streamId Stream ID
     * @param recipient Where to send tokens
     */
    function withdrawMax(
        uint256 streamId,
        address recipient
    ) external nonReentrant returns (uint256 amount) {
        Stream storage stream = streams[streamId];
        if (stream.depositAmount == 0) revert StreamNotFound();
        if (stream.canceled) revert StreamAlreadyCanceled();

        if (msg.sender != ownerOf(streamId)) revert NotRecipient();

        amount = _withdrawableAmount(streamId);
        if (amount == 0) revert NothingToWithdraw();

        stream.withdrawnAmount += amount;

        IERC20(stream.token).safeTransfer(recipient, amount);

        emit Withdrawn(streamId, recipient, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CANCEL
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancel a stream (sender only, if cancelable)
     * @param streamId Stream ID
     * @return recipientAmount Amount sent to recipient
     * @return senderAmount Amount refunded to sender
     */
    function cancel(
        uint256 streamId
    ) external nonReentrant returns (uint256 recipientAmount, uint256 senderAmount) {
        Stream storage stream = streams[streamId];
        if (stream.depositAmount == 0) revert StreamNotFound();
        if (stream.canceled) revert StreamAlreadyCanceled();
        if (!stream.cancelable) revert StreamNotCancelable();
        if (msg.sender != stream.sender) revert NotSender();

        stream.canceled = true;

        // Calculate amounts
        recipientAmount = _streamedAmount(streamId) - stream.withdrawnAmount;
        senderAmount = stream.depositAmount - stream.withdrawnAmount - recipientAmount;

        address recipient = ownerOf(streamId);

        // Transfer to recipient
        if (recipientAmount > 0) {
            IERC20(stream.token).safeTransfer(recipient, recipientAmount);
        }

        // Refund to sender
        if (senderAmount > 0) {
            IERC20(stream.token).safeTransfer(stream.sender, senderAmount);
        }

        emit StreamCanceled(streamId, stream.sender, recipientAmount, senderAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get stream details
    function getStream(uint256 streamId) external view returns (Stream memory) {
        return streams[streamId];
    }

    /// @notice Get currently withdrawable amount
    function withdrawableAmount(uint256 streamId) external view returns (uint256) {
        return _withdrawableAmount(streamId);
    }

    /// @notice Get total streamed amount
    function streamedAmount(uint256 streamId) external view returns (uint256) {
        return _streamedAmount(streamId);
    }

    /// @notice Get remaining amount in stream
    function remainingAmount(uint256 streamId) external view returns (uint256) {
        Stream storage stream = streams[streamId];
        if (stream.canceled) return 0;
        return stream.depositAmount - stream.withdrawnAmount;
    }

    /// @notice Check if stream is active
    function isActive(uint256 streamId) external view returns (bool) {
        Stream storage stream = streams[streamId];
        return !stream.canceled &&
               block.timestamp >= stream.startTime &&
               block.timestamp < stream.endTime;
    }

    /// @notice Check if stream has ended
    function hasEnded(uint256 streamId) external view returns (bool) {
        Stream storage stream = streams[streamId];
        return stream.canceled || block.timestamp >= stream.endTime;
    }

    /// @notice Get stream progress (0-100%)
    function progress(uint256 streamId) external view returns (uint256) {
        Stream storage stream = streams[streamId];
        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp >= stream.endTime) return 100;

        uint256 elapsed = block.timestamp - stream.startTime;
        uint256 duration = stream.endTime - stream.startTime;
        return (elapsed * 100) / duration;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setProtocolFee(uint256 _feeBps) external onlyRole(ADMIN_ROLE) {
        require(_feeBps <= 500, "Fee too high"); // Max 5%
        protocolFeeBps = _feeBps;
    }

    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        feeReceiver = _feeReceiver;
    }

    function collectFees(address token) external onlyRole(ADMIN_ROLE) {
        uint256 amount = accumulatedFees[token];
        if (amount > 0) {
            accumulatedFees[token] = 0;
            IERC20(token).safeTransfer(feeReceiver, amount);
            emit FeesCollected(token, feeReceiver, amount);
        }
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _createStream(CreateParams memory params) internal returns (uint256 streamId) {
        // Validations
        if (params.recipient == address(0)) revert InvalidRecipient();
        if (params.amount == 0) revert InvalidAmount();
        if (params.endTime <= params.startTime) revert InvalidDuration();
        if (params.endTime - params.startTime < MIN_DURATION) revert InvalidDuration();
        if (params.endTime - params.startTime > MAX_DURATION) revert InvalidDuration();

        if (params.streamType == StreamType.LINEAR_CLIFF) {
            if (params.cliffTime <= params.startTime || params.cliffTime >= params.endTime)
                revert InvalidCliff();
            if (params.cliffAmount > params.amount) revert InvalidCliff();
        }

        streamId = nextStreamId++;

        // Calculate fee
        uint256 fee = (params.amount * protocolFeeBps) / 10000;
        uint256 depositAmount = params.amount - fee;

        // Transfer tokens
        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amount);

        if (fee > 0) {
            accumulatedFees[params.token] += fee;
        }

        // Create stream
        streams[streamId] = Stream({
            sender: msg.sender,
            token: params.token,
            depositAmount: depositAmount,
            withdrawnAmount: 0,
            startTime: params.startTime,
            endTime: params.endTime,
            cliffTime: params.cliffTime,
            cliffAmount: params.cliffAmount,
            streamType: params.streamType,
            cancelable: params.cancelable,
            canceled: false
        });

        // Mint NFT to recipient
        _mint(params.recipient, streamId);

        emit StreamCreated(
            streamId,
            msg.sender,
            params.recipient,
            params.token,
            depositAmount,
            params.startTime,
            params.endTime,
            params.streamType
        );
    }

    function _streamedAmount(uint256 streamId) internal view returns (uint256) {
        Stream storage stream = streams[streamId];

        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp >= stream.endTime) return stream.depositAmount;

        // Handle cliff
        if (stream.streamType == StreamType.LINEAR_CLIFF) {
            if (block.timestamp < stream.cliffTime) return 0;

            // After cliff: cliff amount + linear portion of remaining
            uint256 remaining = stream.depositAmount - stream.cliffAmount;
            uint256 elapsed = block.timestamp - stream.cliffTime;
            uint256 duration = stream.endTime - stream.cliffTime;

            return stream.cliffAmount + (remaining * elapsed) / duration;
        }

        // Linear streaming
        if (stream.streamType == StreamType.LINEAR) {
            uint256 elapsed = block.timestamp - stream.startTime;
            uint256 duration = stream.endTime - stream.startTime;
            return (stream.depositAmount * elapsed) / duration;
        }

        // Exponential streaming (quadratic)
        if (stream.streamType == StreamType.EXPONENTIAL) {
            uint256 elapsed = block.timestamp - stream.startTime;
            uint256 duration = stream.endTime - stream.startTime;
            // x^2 curve
            return (stream.depositAmount * elapsed * elapsed) / (duration * duration);
        }

        return 0;
    }

    function _withdrawableAmount(uint256 streamId) internal view returns (uint256) {
        Stream storage stream = streams[streamId];
        if (stream.canceled) return 0;

        uint256 streamed = _streamedAmount(streamId);
        if (streamed <= stream.withdrawnAmount) return 0;

        return streamed - stream.withdrawnAmount;
    }

    // Override ERC721 for transfers
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            emit StreamTransferred(tokenId, from, to);
        }

        return super._update(to, tokenId, auth);
    }

    // Required overrides
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
