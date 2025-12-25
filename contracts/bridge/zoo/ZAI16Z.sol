// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/*
    ███████╗ ██████╗  ██████╗      █████╗ ██╗ ██╗ ██████╗ ███████╗
    ╚══███╔╝██╔═══██╗██╔═══██╗    ██╔══██╗██║███║██╔════╝ ╚══███╔╝
      ███╔╝ ██║   ██║██║   ██║    ███████║██║╚██║███████╗   ███╔╝ 
     ███╔╝  ██║   ██║██║   ██║    ██╔══██║██║ ██║██╔═══██╗ ███╔╝  
    ███████╗╚██████╔╝╚██████╔╝    ██║  ██║██║ ██║╚██████╔╝███████╗
    ╚══════╝ ╚═════╝  ╚═════╝     ╚═╝  ╚═╝╚═╝ ╚═╝ ╚═════╝ ╚══════╝
 */

import "../LRC20B.sol";

contract ZooAI16Z is LRC20B {
    string public constant _name = "Zoo AI16Z";
    string public constant _symbol = "ZAI16Z";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
