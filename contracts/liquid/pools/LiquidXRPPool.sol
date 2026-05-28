// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { LiquidPool } from "./LiquidPool.sol";
import { BasketRegistry } from "../../bridge/v4/BasketRegistry.sol";

/**
 * @title LiquidXRPPool
 * @author Lux Industries
 * @notice XRP-basket pool. Accepts NativeXRP today (sole member); issues LXRP
 *         at 6 decimals (drop parity).
 */
contract LiquidXRPPool is LiquidPool {
    constructor(address admin, address _liquidToken, address _basketRegistry)
        LiquidPool(admin, _liquidToken, _basketRegistry, uint8(BasketRegistry.BasketClass.XRP), 6)
    { }

    function _basketClassEnum() internal pure override returns (BasketRegistry.BasketClass) {
        return BasketRegistry.BasketClass.XRP;
    }
}
