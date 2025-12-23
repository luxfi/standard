// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
    ███████╗ ██████╗  ██████╗     ██████╗  ██████╗ ██████╗  ██████╗ █████╗ ████████╗
    ╚══███╔╝██╔═══██╗██╔═══██╗    ██╔══██╗██╔═══██╗██╔══██╗██╔════╝██╔══██╗╚══██╔══╝
      ███╔╝ ██║   ██║██║   ██║    ██████╔╝██║   ██║██████╔╝██║     ███████║   ██║   
     ███╔╝  ██║   ██║██║   ██║    ██╔═══╝ ██║   ██║██╔═══╝ ██║     ██╔══██║   ██║   
    ███████╗╚██████╔╝╚██████╔╝    ██║     ╚██████╔╝██║     ╚██████╗██║  ██║   ██║   
    ╚══════╝ ╚═════╝  ╚═════╝     ╚═╝      ╚═════╝ ╚═╝      ╚═════╝╚═╝  ╚═╝   ╚═╝   
 */

import "../ERC20B.sol";

contract ZooPopcat is ERC20B {
    string public constant _name = "Zoo Popcat";
    string public constant _symbol = "ZPOPCAT";

    constructor() ERC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
