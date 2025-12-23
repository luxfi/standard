// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title ClockMode
 * @notice Enum for different time measurement modes in governance contracts
 * @dev This enum is used to specify how time-based operations should be measured,
 * particularly for voting periods, timelocks, and snapshots. Different chains
 * and use cases may prefer different timing mechanisms.
 *
 * Values:
 * - Timestamp: Uses block.timestamp (seconds since epoch)
 * - BlockNumber: Uses block.number (incremental block count)
 */
enum ClockMode {
    Timestamp,
    BlockNumber
}
