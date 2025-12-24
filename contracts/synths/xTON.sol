// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SynthToken} from "./SynthToken.sol";

/// @title xTON - Lux Synthetic TON
/// @notice Self-repaying synthetic TON backed by yield-bearing LTON
contract xTON is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic TON", "xTON", FLASH_FEE) {}
}
