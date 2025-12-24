// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../LRC20B.sol";

contract LuxREDO is LRC20B {
    string public constant _name = "Lux Resistance Dog";
    string public constant _symbol = "LREDO";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
