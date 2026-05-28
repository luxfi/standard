// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged Native DOT
 * @author Lux Industries
 * @notice 1:1 bridged Polkadot (native) under MPC custody, minted on Lux
 * @dev DOT basket — sole member, matches the DOT broadcaster agent in luxfi/bridge.
 *
 * Decimals: 10 — preserves planck parity on the Polkadot relay (1 DOT = 1e10 planck).
 *             Kusama planck would be 12; Lux mints against the Polkadot relay only.
 */
contract BridgedNativeDOT is LRC20B {
    string public constant _name = "Bridged Native DOT";
    string public constant _symbol = "nDOT";
    uint8 public constant _decimals = 10;

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
