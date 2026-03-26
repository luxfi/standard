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

import { LRC20B } from "../../bridge/LRC20B.sol";

contract LiquidMIGA is LRC20B {
    constructor() LRC20B("Liquid MIGA", "LMIGA") { }

    /// @notice C-02 fix: use MINTER_ROLE not DEFAULT_ADMIN_ROLE for vault minting
    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    /// @notice C-02 fix: use MINTER_ROLE not DEFAULT_ADMIN_ROLE for vault burning
    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
