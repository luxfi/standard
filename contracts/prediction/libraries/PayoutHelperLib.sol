// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title PayoutHelperLib
/// @notice Helper library for validating payout arrays in prediction markets
library PayoutHelperLib {
    /// @notice Validates a payout array for binary outcomes
    /// @param payouts The payout array to validate
    /// @return True if the payout array is valid
    /// @dev Valid payouts are [0,1], [1,0], or [1,1] (tie/unknown)
    function isValidPayoutArray(uint256[] memory payouts) internal pure returns (bool) {
        if (payouts.length != 2) return false;

        // Payout must be [0,1], [1,0] or [1,1]
        // If payout[0] is 1, payout[1] must be 0 or 1
        if ((payouts[0] == 1) && (payouts[1] == 0 || payouts[1] == 1)) {
            return true;
        }

        // If payout[0] is 0, payout[1] must be 1
        if ((payouts[0] == 0) && (payouts[1] == 1)) {
            return true;
        }

        return false;
    }
}
