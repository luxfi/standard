// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/*
    ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗██████╗     ███████╗████████╗██╗  ██╗
    ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗    ██╔════╝╚══██╔══╝██║  ██║
    ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  ██║  ██║    █████╗     ██║   ███████║
    ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  ██║  ██║    ██╔══╝     ██║   ██╔══██║
    ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗██████╔╝    ███████╗   ██║   ██║  ██║
    ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═════╝     ╚══════╝   ╚═╝   ╚═╝  ╚═╝
 */

import "../LRC20B.sol";

/**
 * @title Bridged ETH
 * @author Lux Industries
 * @notice 1:1 bridged ETH collateral on Lux (minted by Teleporter)
 * @dev This is the canonical bridged ETH - NOT the debt token
 *
 * Token Model:
 * - ETH (this): Bridged collateral, 1:1 backed by ETH on Ethereum
 * - LETH: Debt token minted when borrowing from LiquidETH vault
 *
 * Flow:
 * 1. User deposits ETH on Ethereum → LiquidVault
 * 2. MPC attests deposit → Teleporter mints ETH to user on Lux
 * 3. User can hold ETH, or deposit into LiquidETH to earn yield + borrow LETH
 */
contract BridgedETH is LRC20B {
    string public constant _name = "Bridged ETH";
    string public constant _symbol = "ETH";

    constructor() LRC20B(_name, _symbol) {}

    function mint(address account, uint256 amount) public onlyAdmin {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdmin {
        _burn(account, amount);
    }
}
