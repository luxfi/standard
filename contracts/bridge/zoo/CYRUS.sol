// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
     ██████╗██╗   ██╗██████╗ ██╗   ██╗███████╗     █████╗ ██╗
    ██╔════╝╚██╗ ██╔╝██╔══██╗██║   ██║██╔════╝    ██╔══██╗██║
    ██║      ╚████╔╝ ██████╔╝██║   ██║███████╗    ███████║██║
    ██║       ╚██╔╝  ██╔══██╗██║   ██║╚════██║    ██╔══██║██║
    ╚██████╗   ██║   ██║  ██║╚██████╔╝███████║    ██║  ██║██║
     ╚═════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝    ╚═╝  ╚═╝╚═╝
 */

import "../LRC20B.sol";

contract CYRUS is LRC20B {
    string public constant _name = "Cyrus AI";
    string public constant _symbol = "CYRUS";

    constructor() LRC20B(_name, _symbol) {}

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
