// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../LRC20B.sol";

contract LuxMRB is LRC20B {
    string public constant _name = "Lux MoonRabbits";
    string public constant _symbol = "LMRB";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
