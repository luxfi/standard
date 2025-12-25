// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
    ██╗     ██╗   ██╗██╗  ██╗    ███████╗ ██████╗  ██████╗ 
    ██║     ██║   ██║╚██╗██╔╝    ╚══███╔╝██╔═══██╗██╔═══██╗
    ██║     ██║   ██║ ╚███╔╝       ███╔╝ ██║   ██║██║   ██║
    ██║     ██║   ██║ ██╔██╗      ███╔╝  ██║   ██║██║   ██║
    ███████╗╚██████╔╝██╔╝ ██╗    ███████╗╚██████╔╝╚██████╔╝
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚══════╝ ╚═════╝  ╚═════╝ 
 */

import "../LRC20B.sol";

contract LuxZOO is LRC20B {
    string public constant _name = "Lux ZOO";
    string public constant _symbol = "LZOO";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
