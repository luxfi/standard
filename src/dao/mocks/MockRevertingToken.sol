// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract MockRevertingToken is IERC6372 {
    function CLOCK_MODE() external pure returns (string memory) {
        revert("CLOCK_MODE_REVERT");
    }

    function clock() external pure returns (uint48) {
        revert("CLOCK_REVERT");
    }
}
