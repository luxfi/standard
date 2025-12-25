/***
 *Submitted for verification at basescan.org on 2024-03-20
 */
// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LERC4626 is ERC4626 {
    constructor(
        IERC20 asset_,
        string memory name,
        string memory symbol
    ) ERC4626(asset_) ERC20(name, symbol) {}
}
