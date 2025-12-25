// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {SynthToken} from "./SynthToken.sol";

/// @title xZOO - Lux Synthetic ZOO
/// @notice Self-repaying synthetic ZOO backed by yield-bearing LZOO
contract xZOO is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic ZOO", "xZOO", FLASH_FEE) {}
}
