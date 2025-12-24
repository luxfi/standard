// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

/**
    ███████╗██╗      ██████╗  ██████╗ 
    ██╔════╝██║     ██╔═══██╗██╔════╝ 
    ███████╗██║     ██║   ██║██║  ███╗
    ╚════██║██║     ██║   ██║██║   ██║
    ███████║███████╗╚██████╔╝╚██████╔╝
    ╚══════╝╚══════╝ ╚═════╝  ╚═════╝ 
 */

import "../LRC20B.sol";

contract SLOG is LRC20B {
    string public constant _name = "Slog";
    string public constant _symbol = "SLOG";

    constructor() LRC20B(_name, _symbol) {
         _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
