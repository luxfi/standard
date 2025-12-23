// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title IVersion
 * @notice Simple interface for contract versioning
 * @dev This interface provides a standard way for contracts to expose their version
 * number. Used throughout the DAO Protocol to track contract versions for
 * upgrades, compatibility checks, and off-chain tooling.
 *
 * Version numbers are uint16 values, typically starting at 1 and incrementing
 * with each major contract revision. This allows:
 * - Upgrade tooling to verify compatibility
 * - Frontend applications to adapt to different versions
 * - Analytics to track deployment versions
 */
interface IVersion {
    // --- Pure Functions ---

    /**
     * @notice Returns the contract's version number
     * @dev Pure function that returns a hardcoded version. Typically returns 1
     * for V1 contracts, 2 for V2, etc.
     * @return version The contract version as a uint16
     */
    function version() external pure returns (uint16 version);
}
