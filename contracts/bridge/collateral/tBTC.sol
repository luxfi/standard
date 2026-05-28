// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged tBTC
 * @author Lux Industries
 * @notice 1:1 bridged Threshold Network tBTC collateral on Lux
 * @dev BTC basket member — accepted as deposit into LiquidBTC pool
 *
 * tBTC is 18 decimals on Ethereum; normalization to LBTC sat parity happens in
 * LiquidBTCPool.
 */
contract BridgedtBTC is LRC20B {
    string public constant _name = "Bridged tBTC";
    string public constant _symbol = "tBTC";

    constructor() LRC20B(_name, _symbol) { }

    function mint(address account, uint256 amount) public onlyAdmin {
        bridgeMint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
