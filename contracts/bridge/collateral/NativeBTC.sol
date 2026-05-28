// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged Native BTC
 * @author Lux Industries
 * @notice 1:1 bridged mainnet Bitcoin (UTXO chain) under MPC custody, minted on Lux
 * @dev BTC basket member. Differs from BridgedBTC (which is WBTC-on-Ethereum) and
 *      BridgedBTCB/tBTC/cbBTC: this is the canonical native asset moved via the
 *      BTC broadcaster agent in luxfi/bridge's daemon-side broadcaster set.
 *
 * Decimals: 8, matching satoshi parity exactly.
 */
contract BridgedNativeBTC is LRC20B {
    string public constant _name = "Bridged Native BTC";
    string public constant _symbol = "nBTC";
    uint8 public constant _decimals = 8;

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
