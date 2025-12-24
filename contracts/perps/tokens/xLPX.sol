// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "./MintableBaseToken.sol";

/// @title xLPX Token  
/// @notice Escrowed LPX token earned from staking, vests to LPX over time
contract xLPX is MintableBaseToken {
    constructor() MintableBaseToken("Escrowed LPX", "xLPX", 0) {}
}
