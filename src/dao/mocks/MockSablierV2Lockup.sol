// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LockupLinear} from "../interfaces/sablier/types/DataTypes.sol";

/**
 * @title MockSablierV2Lockup
 * @dev Mock implementation of Sablier V2 Lockup for testing purposes.
 * Provides functionality needed for testing UtilityRolesManagementV1.
 */
contract MockSablierV2Lockup {
    // Stream status enum matching Sablier
    enum Status {
        PENDING, // 0
        STREAMING, // 1
        SETTLED, // 2
        CANCELED, // 3
        DEPLETED // 4
    }

    // Mock state
    mapping(uint256 => uint256) public withdrawableAmounts;
    mapping(uint256 => Status) public streamStatuses;
    uint256 private _nextStreamId = 1;

    // Events to track calls
    event WithdrawMaxCalled(uint256 streamId, address to);
    event StreamCanceled(uint256 streamId);
    event StreamCreated(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint128 totalAmount,
        address asset
    );

    /**
     * @dev Set withdrawable amount for a stream (for testing)
     */
    function setWithdrawableAmount(uint256 streamId, uint256 amount) external {
        withdrawableAmounts[streamId] = amount;
    }

    /**
     * @dev Set stream status (for testing)
     */
    function setStreamStatus(uint256 streamId, Status status) external {
        streamStatuses[streamId] = status;
    }

    /**
     * @dev Get withdrawable amount for a stream
     */
    function withdrawableAmountOf(
        uint256 streamId
    ) external view returns (uint256) {
        return withdrawableAmounts[streamId];
    }

    /**
     * @dev Get stream status
     */
    function statusOf(uint256 streamId) external view returns (Status) {
        return streamStatuses[streamId];
    }

    /**
     * @dev Withdraw max amount from stream
     */
    function withdrawMax(uint256 streamId, address to) external {
        require(withdrawableAmounts[streamId] > 0, "No funds to withdraw");
        emit WithdrawMaxCalled(streamId, to);
        // In real implementation, this would transfer tokens
        withdrawableAmounts[streamId] = 0;
    }

    /**
     * @dev Cancel a stream
     */
    function cancel(uint256 streamId) external {
        Status status = streamStatuses[streamId];
        // Only allow cancellation for PENDING or STREAMING streams
        if (status == Status.PENDING || status == Status.STREAMING) {
            streamStatuses[streamId] = Status.CANCELED;
            emit StreamCanceled(streamId);
        }
        // Do nothing for other statuses (don't revert)
    }

    /**
     * @dev Get next stream ID (matches ISablierV2LockupLinear)
     */
    function nextStreamId() external view returns (uint256) {
        return _nextStreamId;
    }

    /**
     * @dev Create a new stream with timestamps (matches ISablierV2LockupLinear)
     */
    function createWithTimestamps(
        LockupLinear.CreateWithTimestamps calldata params
    ) external returns (uint256 streamId) {
        streamId = _nextStreamId++;

        // Verify token approval
        uint256 allowance = IERC20(params.asset).allowance(
            msg.sender,
            address(this)
        );
        require(allowance >= params.totalAmount, "Insufficient allowance");

        // Transfer tokens from sender
        require(
            IERC20(params.asset).transferFrom(
                msg.sender,
                address(this),
                params.totalAmount
            ),
            "Token transfer failed"
        );

        // Set initial stream state
        streamStatuses[streamId] = Status.PENDING;
        withdrawableAmounts[streamId] = 0; // No funds withdrawable initially

        // Emit event
        emit StreamCreated(
            streamId,
            params.sender,
            params.recipient,
            params.totalAmount,
            address(params.asset)
        );

        return streamId;
    }
}
