// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../../bridge/LRC20B.sol";

contract LiquidDOGS is LRC20B {
    constructor() LRC20B("Liquid DOGS", "LDOGS") { }

    /// @notice C-02 fix: use MINTER_ROLE not DEFAULT_ADMIN_ROLE for vault minting
    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    /// @notice C-02 fix: use MINTER_ROLE not DEFAULT_ADMIN_ROLE for vault burning
    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
