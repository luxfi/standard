// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {ClockModeLib} from "../libs/ClockModeLib.sol";
import {ClockMode} from "../interfaces/dao/ClockMode.sol";

contract ClockModeLibTester {
    function getClockModeFromLib(
        address token
    ) external view returns (ClockMode) {
        return ClockModeLib.getClockMode(token);
    }

    function getCurrentPointFromLib(
        ClockMode mode
    ) external view returns (uint256) {
        return ClockModeLib.getCurrentPoint(mode);
    }
}
