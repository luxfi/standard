// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;
/*
    ██╗     ██╗   ██╗██╗  ██╗     ██████╗ ██╗ ██████╗  █████╗ 
    ██║     ██║   ██║╚██╗██╔╝    ██╔════╝ ██║██╔════╝ ██╔══██╗
    ██║     ██║   ██║ ╚███╔╝     ██║  ███╗██║██║  ███╗███████║
    ██║     ██║   ██║ ██╔██╗     ██║   ██║██║██║   ██║██╔══██║
    ███████╗╚██████╔╝██╔╝ ██╗    ╚██████╔╝██║╚██████╔╝██║  ██║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝     ╚═════╝ ╚═╝ ╚═════╝ ╚═╝  ╚═╝
 */

import "../../bridge/LRC20B.sol";

contract LuxGIGA is LRC20B {
    constructor() LRC20B("Liquid GIGA", "LGIGA") {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
