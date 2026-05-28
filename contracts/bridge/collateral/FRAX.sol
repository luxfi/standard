// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged FRAX
 * @author Lux Industries
 * @notice 1:1 bridged FRAX collateral on Lux (minted by BridgeV4)
 * @dev USD basket member — accepted as deposit into LiquidUSD pool
 */
contract BridgedFRAX is LRC20B {
    string public constant _name = "Bridged FRAX";
    string public constant _symbol = "FRAX";

    constructor() LRC20B(_name, _symbol) { }

    function mint(address account, uint256 amount) public onlyAdmin {
        bridgeMint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
