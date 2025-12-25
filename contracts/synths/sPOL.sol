// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {SynthToken} from "./SynthToken.sol";

/// @title xPOL - Lux Synthetic Polygon
/// @notice Self-repaying synthetic POL backed by yield-bearing LPOL
contract xPOL is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic POL", "xPOL", FLASH_FEE) {}
}
