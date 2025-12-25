// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "./MintableBaseToken.sol";

/// @title LPX Token
/// @notice Governance token for the Lux Perps protocol
contract LPX is MintableBaseToken {
    constructor() MintableBaseToken("Lux Perps", "LPX", 0) {}
}
