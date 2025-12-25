// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {SynthToken} from "./SynthToken.sol";

/// @title xSOL - Lux Synthetic Solana
/// @notice Self-repaying synthetic SOL backed by yield-bearing LSOL
contract xSOL is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic SOL", "xSOL", FLASH_FEE) {}
}
