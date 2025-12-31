// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { ConfidentialWLUX } from "../../../token/LRC20/ConfidentialWLUX.sol";

contract TestConfidentialWLUX is ConfidentialWLUX {
    constructor(uint256 maxDecryptionDelay_) ConfidentialWLUX(maxDecryptionDelay_) {}
}
