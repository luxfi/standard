// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILRC20} from "../interfaces/ILRC20.sol";

/**
 * @title SafeLRC20
 * @author Lux Network
 * @notice Safe wrapper for LRC20/ERC20 token transfers
 * @dev Wraps OpenZeppelin's SafeERC20 for Lux naming consistency
 *
 * WHY USE THIS:
 * - Standard `transfer` and `transferFrom` can fail silently (return false)
 * - Some tokens don't return a value (USDT, BNB)
 * - SafeLRC20 reverts on failure, preventing loss of funds
 *
 * USAGE:
 * ```solidity
 * using SafeLRC20 for ILRC20;
 * token.safeTransfer(recipient, amount);
 * token.safeTransferFrom(sender, recipient, amount);
 * token.safeIncreaseAllowance(spender, addedValue);
 * ```
 */
library SafeLRC20 {
    using SafeERC20 for IERC20;

    /**
     * @notice Safely transfer tokens, reverts on failure
     * @param token Token to transfer
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function safeTransfer(ILRC20 token, address to, uint256 value) internal {
        IERC20(address(token)).safeTransfer(to, value);
    }

    /**
     * @notice Safely transfer tokens from, reverts on failure
     * @param token Token to transfer
     * @param from Sender address (must have approval)
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function safeTransferFrom(ILRC20 token, address from, address to, uint256 value) internal {
        IERC20(address(token)).safeTransferFrom(from, to, value);
    }

    /**
     * @notice Safely approve tokens, reverts on failure
     * @dev Note: Prefer safeIncreaseAllowance/safeDecreaseAllowance to avoid front-running
     * @param token Token to approve
     * @param spender Spender address
     * @param value Allowance amount
     */
    function safeApprove(ILRC20 token, address spender, uint256 value) internal {
        IERC20(address(token)).forceApprove(spender, value);
    }

    /**
     * @notice Safely increase allowance, reverts on failure
     * @param token Token to modify allowance
     * @param spender Spender address
     * @param value Amount to add to current allowance
     */
    function safeIncreaseAllowance(ILRC20 token, address spender, uint256 value) internal {
        IERC20(address(token)).safeIncreaseAllowance(spender, value);
    }

    /**
     * @notice Safely decrease allowance, reverts on failure
     * @param token Token to modify allowance
     * @param spender Spender address
     * @param requestedDecrease Amount to subtract from current allowance
     */
    function safeDecreaseAllowance(ILRC20 token, address spender, uint256 requestedDecrease) internal {
        IERC20(address(token)).safeDecreaseAllowance(spender, requestedDecrease);
    }

    /**
     * @notice Force approve with reset to zero first (for non-standard tokens)
     * @dev Use this for tokens that require zero approval before changing
     * @param token Token to approve
     * @param spender Spender address
     * @param value New allowance amount
     */
    function forceApprove(ILRC20 token, address spender, uint256 value) internal {
        IERC20(address(token)).forceApprove(spender, value);
    }
}
