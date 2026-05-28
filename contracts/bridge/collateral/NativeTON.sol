// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged Native TON
 * @author Lux Industries
 * @notice 1:1 bridged Toncoin (native) under MPC custody, minted on Lux
 * @dev TON basket — sole member, matches the TON broadcaster agent in luxfi/bridge.
 *
 * Decimals: 9 — preserves nanoton parity (1 TON = 1e9 nanoton).
 */
contract BridgedNativeTON is LRC20B {
    string public constant _name = "Bridged Native TON";
    string public constant _symbol = "nTON";
    uint8 public constant _decimals = 9;

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
