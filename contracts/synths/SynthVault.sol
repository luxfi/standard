// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AlchemistV2} from "./AlchemistV2.sol";

/**
 * @title SynthVault
 * @notice Vault for synthetic asset minting with yield-based auto-repayment
 *
 * SYNTH VAULT FLOW:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  1. Deposit sLUX (yield-bearing collateral)                     │
 * │  2. Mint xLUX/xUSD (synthetic tokens) up to collateral ratio    │
 * │  3. Yield accrues from collateral                               │
 * │  4. Yield automatically repays debt                             │
 * │  5. Eventually: debt = 0, full collateral available             │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * RECEIVES BOOST FROM:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  FeeSplitter ──► SynthVault ──► Additional yield for stakers    │
 * │                                  (on top of base collateral     │
 * │                                   yield from sLUX)              │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * This is the first-principles renamed version of AlchemistV2.
 * All functionality is inherited from the battle-tested Alchemix codebase.
 *
 * KEY TERMS (Lux naming → Alchemix naming):
 * - SynthVault = AlchemistV2 (the vault)
 * - SynthRedeemer = TransmuterV2 (1:1 redemption queue)
 * - xUSD, xETH, xLUX = alUSD, alETH equivalents
 * - sLUX = yield token (like yvDAI, stETH)
 */
contract SynthVault is AlchemistV2 {
    /// @notice Lux version identifier
    string public constant LUX_VERSION = "1.0.0";
    
    // All functionality inherited from AlchemistV2
    // This contract provides cleaner naming for the Lux ecosystem
}
