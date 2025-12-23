// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IHats} from "./IHats.sol";

/**
 * @notice Extended Hats interface to access lastTopHatId
 * @dev This interface adds the lastTopHatId getter which is present in the
 * Hats contract but not exposed in the standard IHats interface.
 */
interface IHatsExtended is IHats {
    // --- View Functions ---

    /**
     * @notice Returns the ID of the most recently created top hat
     * @return lastTopHatId The ID of the most recently created top hat
     */
    function lastTopHatId() external view returns (uint32 lastTopHatId);
}
