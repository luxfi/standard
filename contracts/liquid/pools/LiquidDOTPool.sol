// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { LiquidPool } from "./LiquidPool.sol";
import { BasketRegistry } from "../../bridge/v4/BasketRegistry.sol";

/**
 * @title LiquidDOTPool
 * @author Lux Industries
 * @notice DOT-basket pool. Accepts NativeDOT today (sole member); issues LDOT
 *         at 10 decimals (Polkadot relay planck parity; Kusama uses 12 but
 *         Lux mints against the Polkadot relay only).
 */
contract LiquidDOTPool is LiquidPool {
    constructor(address admin, address _liquidToken, address _basketRegistry)
        LiquidPool(admin, _liquidToken, _basketRegistry, uint8(BasketRegistry.BasketClass.DOT), 10)
    { }

    function _basketClassEnum() internal pure override returns (BasketRegistry.BasketClass) {
        return BasketRegistry.BasketClass.DOT;
    }
}
