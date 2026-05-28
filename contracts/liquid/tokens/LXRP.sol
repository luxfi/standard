// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/*
    ██╗     ██╗   ██╗██╗  ██╗    ██╗  ██╗██████╗ ██████╗
    ██║     ██║   ██║╚██╗██╔╝    ╚██╗██╔╝██╔══██╗██╔══██╗
    ██║     ██║   ██║ ╚███╔╝      ╚███╔╝ ██████╔╝██████╔╝
    ██║     ██║   ██║ ██╔██╗      ██╔██╗ ██╔══██╗██╔═══╝
    ███████╗╚██████╔╝██╔╝ ██╗    ██╔╝ ██╗██║  ██║██║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝
 */

import { LRC20B } from "../../bridge/LRC20B.sol";

/// @title LiquidXRP — the XRP-basket pool token (6 decimals, drop parity).
contract LiquidXRP is LRC20B {
    uint8 public constant _decimals = 6;

    constructor() LRC20B("Liquid XRP", "LXRP") { }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
