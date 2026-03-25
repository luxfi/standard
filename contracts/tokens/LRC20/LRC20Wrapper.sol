// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Wrapper } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LRC20Wrapper
 * @author Lux Network
 * @notice Wrapped token implementation for bridging or upgrading tokens
 */
contract LRC20Wrapper is ERC20, ERC20Wrapper, ERC20Permit {
    constructor(IERC20 underlyingToken, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC20Wrapper(underlyingToken)
        ERC20Permit(name_)
    { }

    function decimals() public view override(ERC20, ERC20Wrapper) returns (uint8) {
        return super.decimals();
    }
}
