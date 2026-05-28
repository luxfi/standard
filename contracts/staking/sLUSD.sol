// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { sLToken } from "./sLToken.sol";

/// @title sLUSD — staked LiquidUSD ERC-4626 yield vault
contract sLUSD is sLToken {
    constructor(IERC20 lusd, address admin) sLToken(lusd, "Staked LiquidUSD", "sLUSD", admin) { }
}
