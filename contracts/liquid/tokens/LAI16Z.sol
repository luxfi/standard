// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/*
    ██╗     ██╗   ██╗██╗  ██╗     █████╗ ██╗ ██╗ ██████╗ ███████╗
    ██║     ██║   ██║╚██╗██╔╝    ██╔══██╗██║███║██╔════╝ ╚══███╔╝
    ██║     ██║   ██║ ╚███╔╝     ███████║██║╚██║███████╗   ███╔╝ 
    ██║     ██║   ██║ ██╔██╗     ██╔══██║██║ ██║██╔═══██╗ ███╔╝  
    ███████╗╚██████╔╝██╔╝ ██╗    ██║  ██║██║ ██║╚██████╔╝███████╗
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝ ╚═╝ ╚═════╝ ╚══════╝
 */

import "../../bridge/LRC20B.sol";

contract LuxAI16Z is LRC20B {
    string public constant _name = "Lux AI16Z";
    string public constant _symbol = "LAI16Z";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
