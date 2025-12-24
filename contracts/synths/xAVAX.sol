// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SynthToken} from "./SynthToken.sol";

/// @title xAVAX - Lux Synthetic Avalanche
/// @notice Self-repaying synthetic AVAX backed by yield-bearing LAVAX
contract xAVAX is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic AVAX", "xAVAX", FLASH_FEE) {}
}
