// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import "@luxfi/standard/lib/access/AccessControl.sol";

/**
 * @title LRC20Mintable
 * @author Lux Industries
 * @notice LRC-20 extension for token minting with role control (LP-3022)
 * @dev Composable extension with MINTER_ROLE access control
 */
abstract contract LRC20Mintable is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Error thrown when caller lacks MINTER_ROLE
     */
    error LRC20MintableUnauthorized(address caller);

    /**
     * @notice Creates `amount` tokens and assigns to `to`
     * @dev Caller must have MINTER_ROLE
     * @param to Address to receive minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) public virtual {
        if (!hasRole(MINTER_ROLE, _msgSender())) {
            revert LRC20MintableUnauthorized(_msgSender());
        }
        _mint(to, amount);
    }

    /**
     * @notice Batch mint to multiple addresses
     * @dev Caller must have MINTER_ROLE. Gas optimized for multiple recipients.
     * @param recipients Array of addresses to receive tokens
     * @param amounts Array of amounts to mint to each recipient
     */
    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) public virtual {
        if (!hasRole(MINTER_ROLE, _msgSender())) {
            revert LRC20MintableUnauthorized(_msgSender());
        }
        require(recipients.length == amounts.length, "LRC20Mintable: arrays length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }
}
