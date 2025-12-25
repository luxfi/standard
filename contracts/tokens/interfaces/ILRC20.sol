// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILRC20
 * @author Lux Network
 * @notice Lux Request for Comments 20 - Standard fungible token interface
 * @dev Extends IERC20 for full ERC-20 compatibility while establishing Lux naming.
 *
 * LRC20 tokens are fully ERC-20 compatible. This interface exists to:
 * - Establish Lux-specific naming conventions
 * - Provide a base for future Lux-specific extensions
 * - Enable SafeLRC20 library compatibility
 *
 * All LRC20 implementations support standard ERC-20 operations:
 * - totalSupply(), balanceOf(), transfer(), allowance(), approve(), transferFrom()
 */
interface ILRC20 is IERC20 {
    // Inherits all IERC20 functions:
    // - totalSupply() external view returns (uint256)
    // - balanceOf(address account) external view returns (uint256)
    // - transfer(address to, uint256 value) external returns (bool)
    // - allowance(address owner, address spender) external view returns (uint256)
    // - approve(address spender, uint256 value) external returns (bool)
    // - transferFrom(address from, address to, uint256 value) external returns (bool)
}
