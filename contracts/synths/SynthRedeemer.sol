// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {TransmuterV2} from "./TransmuterV2.sol";

/**
 * @title SynthRedeemer
 * @notice Queue-based 1:1 redemption of synthetic tokens for underlying assets
 *
 * REDEMPTION FLOW:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  1. User deposits xUSD into SynthRedeemer                       │
 * │  2. Position enters queue                                       │
 * │  3. As underlying (LUSD) becomes available from yield...        │
 * │  4. Queue processes in FIFO order                               │
 * │  5. User claims LUSD 1:1 for deposited xUSD                     │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * This enables synth holders to exit at $1 peg even if AMM price deviates.
 * The queue ensures fair ordering and prevents bank runs.
 *
 * KEY TERMS:
 * - SynthRedeemer = TransmuterV2 (Alchemix naming)
 * - Redemption = Transmutation (converting synth → underlying)
 * - Queue position = Tick (position in FIFO queue)
 */
contract SynthRedeemer is TransmuterV2 {
    /// @notice Lux version identifier  
    string public constant LUX_VERSION = "1.0.0";
    
    // All functionality inherited from TransmuterV2
    // This contract provides cleaner naming for the Lux ecosystem
}
