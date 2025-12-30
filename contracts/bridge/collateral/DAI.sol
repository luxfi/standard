// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "../LRC20B.sol";

/**
 * @title Bridged DAI
 * @author Lux Industries
 * @notice 1:1 bridged DAI collateral on Lux (minted by Teleporter)
 * @dev Bridged DAI can be deposited into LiquidUSD to borrow LUSD
 */
contract BridgedDAI is LRC20B {
    string public constant _name = "Bridged DAI";
    string public constant _symbol = "DAI";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
