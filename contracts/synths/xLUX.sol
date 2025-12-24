// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SynthToken} from "./SynthToken.sol";

/// @title xLUX - Lux Synthetic LUX
/// @notice Overcollateralized synthetic LUX backed by yield-generating assets
/// @dev Extends SynthToken with LUX denomination
/// @custom:security-contact security@lux.network
contract xLUX is SynthToken {
    /// @notice Flash mint fee (0.1% = 10 bps)
    uint256 constant FLASH_FEE = 10;

    constructor() SynthToken("Lux Synthetic LUX", "xLUX", FLASH_FEE) {}
}
