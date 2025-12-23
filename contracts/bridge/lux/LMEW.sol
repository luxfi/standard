// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
    ██╗     ██╗   ██╗██╗  ██╗    ███╗   ███╗███████╗██╗    ██╗
    ██║     ██║   ██║╚██╗██╔╝    ████╗ ████║██╔════╝██║    ██║
    ██║     ██║   ██║ ╚███╔╝     ██╔████╔██║█████╗  ██║ █╗ ██║
    ██║     ██║   ██║ ██╔██╗     ██║╚██╔╝██║██╔══╝  ██║███╗██║
    ███████╗╚██████╔╝██╔╝ ██╗    ██║ ╚═╝ ██║███████╗╚███╔███╔╝
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝ 
 */

import "../ERC20B.sol";

contract LuxMEW is ERC20B {
    string public constant _name = "Lux MEW";
    string public constant _symbol = "LMEW";

    constructor() ERC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
