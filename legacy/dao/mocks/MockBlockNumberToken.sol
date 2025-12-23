// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

contract MockBlockNumberToken is IERC6372 {
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=blocknumber&from=default"; // Or any string not "mode=timestamp"
    }

    function clock() external view returns (uint48) {
        return uint48(block.number);
    }
}
