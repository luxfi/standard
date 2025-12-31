// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {
    ConfidentialLRC20WithErrorsMintable
} from "../../../token/LRC20/extensions/ConfidentialLRC20WithErrorsMintable.sol";

contract TestConfidentialLRC20WithErrorsMintable is ConfidentialLRC20WithErrorsMintable {
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ConfidentialLRC20WithErrorsMintable(name_, symbol_, owner_) {
        //
    }
}
