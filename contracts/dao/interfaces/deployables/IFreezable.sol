// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IFreezable
 * @notice Minimal interface for contracts that can be frozen
 * @dev This interface defines the core freeze state that guards need to check.
 * It allows different freeze mechanisms (voting-based, time-based, etc.) to be
 * used interchangeably by guards without coupling to specific implementations.
 *
 * Key design principles:
 * - Minimal surface area - only what guards actually need
 * - No assumptions about freeze mechanism (voting, multisig, time-based, etc.)
 * - Clear semantics for freeze state and timing
 *
 * Implementations may add their own mechanisms for freezing/unfreezing,
 * but must provide these two view functions for guard compatibility.
 */
interface IFreezable {
    /**
     * @notice Checks if the DAO is currently frozen
     * @dev This should return the current freeze state, taking into account
     * any auto-expiry or other state transitions that the implementation uses.
     * @return isFrozen True if the DAO is currently frozen, false otherwise
     */
    function isFrozen() external view returns (bool isFrozen);

    /**
     * @notice Returns the timestamp of the most recent freeze, even if currently unfrozen
     * @dev CRITICAL SECURITY FUNCTION: This enables the freeze guard security model.
     *
     * Security Invariant: Any transaction that was timelocked BEFORE this timestamp
     * will NEVER be executable, regardless of the current freeze/unfreeze state.
     *
     * This timestamp:
     * - Is set to block.timestamp whenever the DAO is frozen
     * - Is NEVER cleared (remains set even after unfreeze)
     * - Ensures all pre-freeze timelocked transactions are permanently invalidated
     *
     * @return lastFreezeTimestamp Timestamp of the most recent freeze, or 0 if never frozen
     */
    function lastFreezeTime()
        external
        view
        returns (uint48 lastFreezeTimestamp);
}
