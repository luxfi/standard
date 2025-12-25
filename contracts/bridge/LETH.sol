// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "./LRC20B.sol";

/**
 * @title LETH - Bridged Ether on Lux Network
 * @notice LRC20B representation of ETH bridged to Lux via Teleport
 * @dev Built on LRC20B (Lux Request for Comments 20 Bridgeable)
 *      Supports admin-controlled bridgeMint/bridgeBurn for bridge operations
 */
contract LETH is LRC20B {
    constructor() LRC20B("Lux Ether", "LETH") {}
}
