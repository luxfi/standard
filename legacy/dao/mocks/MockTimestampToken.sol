// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract MockTimestampToken is IERC6372 {
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }
}
