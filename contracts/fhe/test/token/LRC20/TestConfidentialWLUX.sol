// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.31;

import { ConfidentialWLUX } from "../../../token/LRC20/ConfidentialWLUX.sol";

contract TestConfidentialWLUX is ConfidentialWLUX {
    constructor(uint256 maxDecryptionDelay_) ConfidentialWLUX(maxDecryptionDelay_) {}
}
