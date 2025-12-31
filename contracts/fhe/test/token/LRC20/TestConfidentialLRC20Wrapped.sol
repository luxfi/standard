// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.31;

import { ConfidentialLRC20Wrapped } from "../../../token/LRC20/ConfidentialLRC20Wrapped.sol";

contract TestConfidentialLRC20Wrapped is ConfidentialLRC20Wrapped {
    constructor(address lrc20_, uint256 maxDecryptionDelay_) ConfidentialLRC20Wrapped(lrc20_, maxDecryptionDelay_) {}
}
