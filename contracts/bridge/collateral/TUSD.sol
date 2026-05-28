// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged TUSD
 * @author Lux Industries
 * @notice 1:1 bridged TrueUSD collateral on Lux (minted by BridgeV4)
 * @dev USD basket member — accepted as deposit into LiquidUSD pool
 */
contract BridgedTUSD is LRC20B {
    string public constant _name = "Bridged TUSD";
    string public constant _symbol = "TUSD";

    constructor() LRC20B(_name, _symbol) { }

    function mint(address account, uint256 amount) public onlyAdmin {
        bridgeMint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
