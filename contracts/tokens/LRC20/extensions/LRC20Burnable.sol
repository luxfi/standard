// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";

/**
 * @title LRC20Burnable
 * @author Lux Industries
 * @notice LRC-20 extension for token burning (LP-3021)
 * @dev Composable extension that can be inherited alongside LRC20
 */
abstract contract LRC20Burnable is ERC20 {
    /**
     * @notice Destroys `amount` tokens from the caller
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Destroys `amount` tokens from `account`, deducting from allowance
     * @dev Caller must have allowance for `account`'s tokens of at least `amount`
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
