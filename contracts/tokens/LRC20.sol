// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title LRC20
 * @author Lux Industries
 * @notice Lux Request for Comments 20 - Base fungible token standard
 * @dev Simple ERC20 implementation extending OpenZeppelin 5.x ERC20.
 *      For full-featured tokens with Permit, Votes, FlashMint, use LRC20/LRC20.sol
 */
contract LRC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /**
     * @notice Internal mint function
     * @param account Recipient address
     * @param amount Amount to mint
     */
    function _mintTokens(address account, uint256 amount) internal virtual {
        _mint(account, amount);
    }

    /**
     * @notice Internal burn function
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function _burnTokens(address account, uint256 amount) internal virtual {
        _burn(account, amount);
    }
}
