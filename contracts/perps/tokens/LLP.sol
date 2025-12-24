// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "./MintableBaseToken.sol";

/// @title LLP Token
/// @notice Liquidity provider token representing shares in the LLP pool
contract LLP is MintableBaseToken {
    constructor() MintableBaseToken("Lux LP", "LLP", 0) {}
}
