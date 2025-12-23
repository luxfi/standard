// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SynthToken} from "./SynthToken.sol";

/// @title xUSD - Lux Synthetic USD
/// @notice Overcollateralized synthetic USD backed by yield-generating assets
/// @dev Extends SynthToken with USD denomination
/// @custom:security-contact security@lux.network
contract xUSD is SynthToken {
    /// @notice Flash mint fee (0.1% = 10 bps)
    uint256 constant FLASH_FEE = 10;
    
    constructor() SynthToken("Lux Synthetic USD", "xUSD", FLASH_FEE) {}
}
