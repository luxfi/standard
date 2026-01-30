// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/*
    ██╗     ███╗   ███╗██╗ ██████╗  █████╗
    ██║     ████╗ ████║██║██╔════╝ ██╔══██╗
    ██║     ██╔████╔██║██║██║  ███╗███████║
    ██║     ██║╚██╔╝██║██║██║   ██║██╔══██║
    ███████╗██║ ╚═╝ ██║██║╚██████╔╝██║  ██║
    ╚══════╝╚═╝     ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═╝

    Liquid MIGA - 1:1 liquid staking token for MIGA
    Deposit MIGA → Receive LMIGA
    Can be used as collateral for ASHA bonding (TIER_1)
 */

import "../../bridge/LRC20B.sol";

contract LuxMIGA is LRC20B {
    string public constant _name = "Liquid MIGA";
    string public constant _symbol = "LMIGA";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
