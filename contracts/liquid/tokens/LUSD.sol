// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
    ██╗     ██╗   ██╗██╗  ██╗    ██╗   ██╗███████╗██████╗ 
    ██║     ██║   ██║╚██╗██╔╝    ██║   ██║██╔════╝██╔══██╗
    ██║     ██║   ██║ ╚███╔╝     ██║   ██║███████╗██║  ██║
    ██║     ██║   ██║ ██╔██╗     ██║   ██║╚════██║██║  ██║
    ███████╗╚██████╔╝██╔╝ ██╗    ╚██████╔╝███████║██████╔╝
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝     ╚═════╝ ╚══════╝╚═════╝ 
 */

import "../../bridge/LRC20B.sol";

contract LuxUSD is LRC20B {
    constructor() LRC20B("Liquid Dollar", "LUSD") {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
