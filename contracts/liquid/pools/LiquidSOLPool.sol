// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { LiquidPool } from "./LiquidPool.sol";
import { BasketRegistry } from "../../bridge/v4/BasketRegistry.sol";

/**
 * @title LiquidSOLPool
 * @author Lux Industries
 * @notice SOL-basket pool. Accepts NativeSOL today (sole member); issues LSOL.
 *
 * Pool decimals match the existing LiquidSOL token (18 decimals on Lux,
 * same scale as the rest of the L-token family). NativeSOL has 9 decimals
 * (lamport parity); the pool up-scales by 1e9 on deposit and down-scales
 * on burn for clean round-trip.
 */
contract LiquidSOLPool is LiquidPool {
    constructor(address admin, address _liquidToken, address _basketRegistry)
        LiquidPool(admin, _liquidToken, _basketRegistry, uint8(BasketRegistry.BasketClass.SOL), 18)
    { }

    function _basketClassEnum() internal pure override returns (BasketRegistry.BasketClass) {
        return BasketRegistry.BasketClass.SOL;
    }
}
