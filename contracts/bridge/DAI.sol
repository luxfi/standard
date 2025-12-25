// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DAI is ERC20 {
    constructor() ERC20("Dai Stablecoin", "DAI") {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }

    // DAI uses 18 decimals by default, so no need to override decimals function
}
