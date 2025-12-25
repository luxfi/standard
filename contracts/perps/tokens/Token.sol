// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Token
 * @notice Simple ERC20 token with public mint and WETH-like deposit/withdraw
 * @dev Used for LP tokens and testing. Extends OZ 5.x ERC20.
 */
contract Token is ERC20 {
    constructor() ERC20("Token", "TOKEN") {}

    /**
     * @notice Mint tokens to an account (public - for LP/test tokens)
     * @param account Recipient address
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    /**
     * @notice Withdraw any ERC20 token from this contract
     * @param token Token address
     * @param account Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawToken(address token, address account, uint256 amount) public {
        IERC20(token).transfer(account, amount);
    }

    /**
     * @notice Deposit ETH and receive tokens (WETH-like)
     */
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw ETH by burning tokens (WETH-like)
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Token: insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}
