// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SynthToken} from "./SynthToken.sol";

/// @title xAI - Lux Synthetic AI
/// @notice Self-repaying synthetic AI backed by yield-bearing staked AI tokens
/// @dev AI is native to Lux - earned through hardware-attested GPU compute mining
contract xAI is SynthToken {
    uint256 constant FLASH_FEE = 10; // 0.1% flash loan fee

    constructor() SynthToken("Lux Synthetic AI", "xAI", FLASH_FEE) {}
}
