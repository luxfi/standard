// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged PYUSD
 * @author Lux Industries
 * @notice 1:1 bridged PayPal USD collateral on Lux (minted by BridgeV4)
 * @dev USD basket member — accepted as deposit into LiquidUSD pool
 */
contract BridgedPYUSD is LRC20B {
    string public constant _name = "Bridged PYUSD";
    string public constant _symbol = "PYUSD";
    uint8 public constant _decimals = 6;

    constructor() LRC20B(_name, _symbol) { }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public onlyAdmin {
        bridgeMint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
