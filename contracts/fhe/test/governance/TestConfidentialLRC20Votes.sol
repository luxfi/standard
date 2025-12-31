// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.31;

import { ConfidentialLRC20Votes } from "../../governance/ConfidentialLRC20Votes.sol";

contract TestConfidentialLRC20Votes is ConfidentialLRC20Votes {
    constructor(
        address owner_,
        string memory name_,
        string memory symbol_,
        string memory version_,
        uint64 totalSupply_
    ) ConfidentialLRC20Votes(owner_, name_, symbol_, version_, totalSupply_) {
        //
    }
}
