// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {SynthToken} from "./SynthToken.sol";

/// @title xETH - Lux Synthetic ETH
/// @notice Overcollateralized synthetic ETH backed by yield-generating assets
/// @dev Extends SynthToken with ETH denomination
/// @custom:security-contact security@lux.network
contract xETH is SynthToken {
    /// @notice Flash mint fee (0.1% = 10 bps)
    uint256 constant FLASH_FEE = 10;
    
    constructor() SynthToken("Lux Synthetic ETH", "xETH", FLASH_FEE) {}
}
