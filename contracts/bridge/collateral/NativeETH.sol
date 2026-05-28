// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { LRC20B } from "../LRC20B.sol";

/**
 * @title Bridged Native ETH
 * @author Lux Industries
 * @notice 1:1 bridged mainnet Ether (native, not wrapped) under MPC custody, minted on Lux
 * @dev ETH basket member. BridgedETH (collateral/ETH.sol) represents WETH-on-Ethereum
 *      flowing through the canonical ERC-20 path; this represents raw ETH locked in
 *      MPC custody on Ethereum and minted here.
 *
 * Decimals: 18, matching wei.
 */
contract BridgedNativeETH is LRC20B {
    string public constant _name = "Bridged Native ETH";
    string public constant _symbol = "nETH";

    constructor() LRC20B(_name, _symbol) { }

    function mint(address account, uint256 amount) public onlyAdmin {
        bridgeMint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
