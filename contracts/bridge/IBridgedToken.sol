// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBridgedToken
 * @notice Interface for bridged tokens that support admin-controlled minting and burning
 * @dev Implemented by LRC20B-based tokens (LETH, LBTC, LUSD, etc.)
 *
 * Token implementations use burn(address, uint256) to burn from a specific account.
 * The caller must have admin role on the token.
 */
interface IBridgedToken is IERC20 {
    /**
     * @notice Mint tokens to an account
     * @param account Address to receive tokens
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Burn tokens from an account
     * @param account Address to burn from
     * @param amount Amount to burn
     * @dev Caller must have admin role. To self-burn, pass address(this) or msg.sender depending on implementation.
     */
    function burn(address account, uint256 amount) external;
}
