// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "../LRC20B.sol";

/**
 * @title Bridged USDC
 * @author Lux Industries
 * @notice 1:1 bridged USDC collateral on Lux (minted by Teleporter)
 * @dev Bridged USDC can be deposited into LiquidUSD to borrow LUSD
 */
contract BridgedUSDC is LRC20B {
    string public constant _name = "Bridged USDC";
    string public constant _symbol = "USDC";
    uint8 public constant _decimals = 6;

    constructor() LRC20B(_name, _symbol) {}

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
