// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.31;

import { ConfidentialVestingWallet } from "../../finance/ConfidentialVestingWallet.sol";

contract TestConfidentialVestingWallet is ConfidentialVestingWallet {
    constructor(
        address beneficiary_,
        uint64 startTimestamp_,
        uint64 duration_
    ) ConfidentialVestingWallet(beneficiary_, startTimestamp_, duration_) {
        //
    }
}
