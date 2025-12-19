// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {ClockMode} from "../interfaces/dao/ClockMode.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @title ClockModeLib
 * @author Lux Industriesn Inc
 * @notice Library for detecting and handling different time measurement modes
 * @dev This library provides utilities for working with ClockMode, abstracting
 * the differences between timestamp-based and block number-based timing.
 *
 * Key features:
 * - Auto-detection of token clock modes via EIP-6372
 * - Unified interface for getting current time points
 * - Safe fallback to block numbers on detection failure
 * - Gas-efficient implementation
 *
 * Usage:
 * - Call getClockMode() to detect a token's timing preference
 * - Use getCurrentPoint() to get the appropriate time value
 * - Integrates seamlessly with voting and governance contracts
 *
 * EIP-6372 compliance:
 * - Attempts to call CLOCK_MODE() on tokens
 * - Parses "mode=timestamp" string
 * - Defaults to block numbers for safety
 *
 * @custom:security-contact security@lux.network
 */
library ClockModeLib {
    /** @notice Pre-computed hash of "mode=timestamp" for gas efficiency */
    bytes32 internal constant CLOCK_MODE_TIMESTAMP_BYTES32 =
        keccak256("mode=timestamp");

    /**
     * @notice Detects the clock mode used by a token
     * @dev Attempts to call CLOCK_MODE() on the token per EIP-6372.
     * If the call reverts or returns an unexpected value, defaults to BlockNumber
     * for safety. This ensures compatibility with both EIP-6372 compliant tokens
     * and legacy tokens that don't implement the interface.
     * @param token_ The token address to check
     * @return The detected ClockMode (Timestamp or BlockNumber)
     */
    function getClockMode(address token_) internal view returns (ClockMode) {
        try IERC6372(token_).CLOCK_MODE() returns (string memory mode) {
            if (keccak256(bytes(mode)) == CLOCK_MODE_TIMESTAMP_BYTES32) {
                return ClockMode.Timestamp;
            }
            return ClockMode.BlockNumber;
        } catch {
            return ClockMode.BlockNumber;
        }
    }

    /**
     * @notice Gets the current time point based on the specified mode
     * @dev Returns either block.timestamp or block.number depending on the mode.
     * This abstraction allows contracts to work with either timing mechanism
     * without conditional logic throughout the codebase.
     * @param mode_ The ClockMode to use (Timestamp or BlockNumber)
     * @return The current time point in the appropriate units
     */
    function getCurrentPoint(ClockMode mode_) internal view returns (uint256) {
        if (mode_ == ClockMode.Timestamp) {
            return block.timestamp;
        } else {
            return block.number;
        }
    }
}
