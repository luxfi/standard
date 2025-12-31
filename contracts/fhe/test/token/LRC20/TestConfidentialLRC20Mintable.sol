// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.31;

import { ConfidentialLRC20Mintable } from "../../../token/LRC20/extensions/ConfidentialLRC20Mintable.sol";

contract TestConfidentialLRC20Mintable is ConfidentialLRC20Mintable {
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ConfidentialLRC20Mintable(name_, symbol_, owner_) {
        //
    }
}
