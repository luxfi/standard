// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

/**
    ███╗   ███╗███████╗██╗      █████╗ ███╗   ██╗██╗ █████╗ 
    ████╗ ████║██╔════╝██║     ██╔══██╗████╗  ██║██║██╔══██╗
    ██╔████╔██║█████╗  ██║     ███████║██╔██╗ ██║██║███████║
    ██║╚██╔╝██║██╔══╝  ██║     ██╔══██║██║╚██╗██║██║██╔══██║
    ██║ ╚═╝ ██║███████╗███████╗██║  ██║██║ ╚████║██║██║  ██║
    ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝  
 */

import "../ERC20B.sol";

contract MELANIA is ERC20B {
    string public constant _name = "Melania Meme";
    string public constant _symbol = "MELANIA";

    constructor() ERC20B(_name, _symbol) {}

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
