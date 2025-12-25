// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {SynthToken} from "./SynthToken.sol";

/// @title xADA - Lux Synthetic Cardano
/// @notice Self-repaying synthetic ADA backed by yield-bearing LADA
contract xADA is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic ADA", "xADA", FLASH_FEE) {}
}
