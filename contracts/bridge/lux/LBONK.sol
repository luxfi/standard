// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    ██╗     ██╗   ██╗██╗  ██╗    ██████╗  ██████╗ ███╗   ██╗██╗  ██╗
    ██║     ██║   ██║╚██╗██╔╝    ██╔══██╗██╔═══██╗████╗  ██║██║ ██╔╝
    ██║     ██║   ██║ ╚███╔╝     ██████╔╝██║   ██║██╔██╗ ██║█████╔╝ 
    ██║     ██║   ██║ ██╔██╗     ██╔══██╗██║   ██║██║╚██╗██║██╔═██╗ 
    ███████╗╚██████╔╝██╔╝ ██╗    ██████╔╝╚██████╔╝██║ ╚████║██║  ██╗
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝
 */

import "../LRC20B.sol";

contract LuxBONK is LRC20B {
    string public constant _name = "Lux BONK";
    string public constant _symbol = "LBONK";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
