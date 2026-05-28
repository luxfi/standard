// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged Native XRP
 * @author Lux Industries
 * @notice 1:1 bridged XRP (XRP Ledger native) under MPC custody, minted on Lux
 * @dev XRP basket — sole member, matches the XRP broadcaster agent in luxfi/bridge.
 *
 * Decimals: 6 — preserves drop parity (1 XRP = 1e6 drops).
 */
contract BridgedNativeXRP is LRC20B {
    string public constant _name = "Bridged Native XRP";
    string public constant _symbol = "nXRP";
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
