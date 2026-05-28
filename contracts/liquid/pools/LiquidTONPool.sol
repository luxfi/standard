// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { LiquidPool } from "./LiquidPool.sol";
import { BasketRegistry } from "../../bridge/v4/BasketRegistry.sol";

/**
 * @title LiquidTONPool
 * @author Lux Industries
 * @notice TON-basket pool. Accepts NativeTON today (sole member); issues LTON.
 *
 * Pool decimals match the existing LiquidTON token (18 decimals on Lux,
 * same scale as the rest of the L-token family). NativeTON has 9 decimals
 * (nanoton parity); the pool up-scales by 1e9 on deposit and down-scales
 * on burn for clean round-trip.
 */
contract LiquidTONPool is LiquidPool {
    constructor(address admin, address _liquidToken, address _basketRegistry)
        LiquidPool(admin, _liquidToken, _basketRegistry, uint8(BasketRegistry.BasketClass.TON), 18)
    { }

    function _basketClassEnum() internal pure override returns (BasketRegistry.BasketClass) {
        return BasketRegistry.BasketClass.TON;
    }
}
