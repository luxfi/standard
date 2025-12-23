// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }

    // Override the decimals function to return 6, like USDT
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
