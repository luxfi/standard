// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SynthToken} from "./SynthToken.sol";

/// @title xBNB - Lux Synthetic BNB
/// @notice Self-repaying synthetic BNB backed by yield-bearing LBNB
contract xBNB is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic BNB", "xBNB", FLASH_FEE) {}
}
