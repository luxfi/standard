// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { sLToken } from "./sLToken.sol";

/// @title sLSOL — staked LiquidSOL ERC-4626 yield vault
contract sLSOL is sLToken {
    constructor(IERC20 lsol, address admin) sLToken(lsol, "Staked LiquidSOL", "sLSOL", admin) { }
}
