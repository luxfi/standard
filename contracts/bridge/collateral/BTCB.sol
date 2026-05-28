// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged BTCB
 * @author Lux Industries
 * @notice 1:1 bridged Binance-Pegged BTC (BSC's BTCB) collateral on Lux
 * @dev BTC basket member — accepted as deposit into LiquidBTC pool
 *
 * BTCB on BSC is 18 decimals (BEP-20); we preserve that on-chain to round-trip
 * cleanly with the source-chain reserve. Normalization to LBTC's 8-decimal
 * sat parity happens in LiquidBTCPool.deposit().
 */
contract BridgedBTCB is LRC20B {
    string public constant _name = "Bridged BTCB";
    string public constant _symbol = "BTCB";

    constructor() LRC20B(_name, _symbol) { }

    function mint(address account, uint256 amount) public onlyAdmin {
        bridgeMint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
