// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/*
    ██╗      ██████╗██╗   ██╗██████╗ ██╗   ██╗███████╗
    ██║     ██╔════╝╚██╗ ██╔╝██╔══██╗██║   ██║██╔════╝
    ██║     ██║      ╚████╔╝ ██████╔╝██║   ██║███████╗
    ██║     ██║       ╚██╔╝  ██╔══██╗██║   ██║╚════██║
    ███████╗╚██████╗   ██║   ██║  ██║╚██████╔╝███████║
    ╚══════╝ ╚═════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝

    Liquid CYRUS - 1:1 liquid staking token for CYRUS
    Deposit CYRUS → Receive LCYRUS
    Can be used as collateral for ASHA bonding (TIER_1)
 */

import "../../bridge/LRC20B.sol";

contract LuxCYRUS is LRC20B {
    constructor() LRC20B("Liquid CYRUS", "LCYRUS") {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
