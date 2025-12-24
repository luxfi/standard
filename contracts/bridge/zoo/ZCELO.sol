// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;
/*
    ███████╗ ██████╗  ██████╗      ██████╗███████╗██╗      ██████╗ 
    ╚══███╔╝██╔═══██╗██╔═══██╗    ██╔════╝██╔════╝██║     ██╔═══██╗
      ███╔╝ ██║   ██║██║   ██║    ██║     █████╗  ██║     ██║   ██║
     ███╔╝  ██║   ██║██║   ██║    ██║     ██╔══╝  ██║     ██║   ██║
    ███████╗╚██████╔╝╚██████╔╝    ╚██████╗███████╗███████╗╚██████╔╝
    ╚══════╝ ╚═════╝  ╚═════╝      ╚═════╝╚══════╝╚══════╝ ╚═════╝ 
 */

import "../LRC20B.sol";

contract ZooCELO is LRC20B {
    string public constant _name = "Zoo CELO";
    string public constant _symbol = "ZCELO";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
