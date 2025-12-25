// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.31;

import {SynthToken} from "./SynthToken.sol";

/// @title xBTC - Lux Synthetic BTC
/// @notice Overcollateralized synthetic BTC backed by yield-generating assets
/// @dev Extends SynthToken with BTC denomination
/// @custom:security-contact security@lux.network
contract xBTC is SynthToken {
    /// @notice Flash mint fee (0.1% = 10 bps)
    uint256 constant FLASH_FEE = 10;
    
    constructor() SynthToken("Lux Synthetic BTC", "xBTC", FLASH_FEE) {}
}
