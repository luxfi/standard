// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import { SolvencyState } from "../SolvencyStateMachine.sol";

/**
 * @title SolvencyStateMachineV4
 * @author Lux Industries
 * @notice Per-basket extension of the 4-state graduated solvency response.
 *
 * The original SolvencyStateMachine (contracts/bridge/SolvencyStateMachine.sol)
 * holds a single global state across all asset flows. BridgeV4 maps multiple
 * baskets to one entrypoint, so each basket needs its own state — a USD-side
 * shortfall must not block BTC redemptions and vice versa.
 *
 *   Healthy        — B >= L and B >= L/0.9 — all ops allowed
 *   RestrictedMint — B >= L but B < L/0.9  — burns/releases ok, new mints blocked
 *   Emergency      — B < L                  — burns ok, releases queued
 *   Recovery       — governance-initiated   — manual exit
 *
 * Thresholds are configurable per-basket in basis points; defaults are:
 *   healthyBp     = 11_111 (111.11% — the L/0.9 boundary, same as V1 default)
 *   emergencyBp   = 10_000 (100%)
 *   recoveryBp    =  9_850 (98.5%; reserved for future automatic-soft-emergency)
 *
 * The state machine is RECHECKED on every mint/burn inside the LiquidX pool
 * (via _updateSolvencyState). Auto-Emergency fires from any state if
 * backing < liabilities. Recovery → Healthy is governance-only.
 */
abstract contract SolvencyStateMachineV4 {
    /// @notice Per-basket state map, keyed by an opaque basket identifier
    ///         (the LiquidX pool uses the basket-class enum cast to uint8).
    mapping(uint8 => SolvencyState) public solvencyState;

    /// @notice Per-basket healthy threshold (bp, default 11_111 = 111.11%)
    mapping(uint8 => uint16) public healthyBp;

    /// @notice Per-basket emergency threshold (bp, default 10_000 = 100%)
    mapping(uint8 => uint16) public emergencyBp;

    /// @notice Emitted on every per-basket state transition
    event BasketSolvencyChanged(uint8 indexed basket, SolvencyState indexed previous, SolvencyState indexed current);

    /// @notice Emitted when governance changes per-basket thresholds
    event BasketThresholdsSet(uint8 indexed basket, uint16 healthyBp, uint16 emergencyBp);

    error SolvencyV4_InvalidThreshold();
    error SolvencyV4_NotInRecovery();
    error SolvencyV4_BackingInsufficient();
    error SolvencyV4_NotEmergency();

    /// @notice Initialize default thresholds for a basket. Called by the pool
    ///         constructor once per basket on its first reference.
    function _initBasketThresholds(uint8 basket) internal {
        if (healthyBp[basket] != 0) return; // already initialized
        healthyBp[basket] = 11_111;
        emergencyBp[basket] = 10_000;
        emit BasketThresholdsSet(basket, 11_111, 10_000);
    }

    /// @notice Set per-basket thresholds. healthyBp must be >= emergencyBp,
    ///         emergencyBp must be > 0. healthyBp == emergencyBp collapses
    ///         the RestrictedMint band — usable for pools where backing is
    ///         1:1 by construction (no over-collateralization invariant).
    function _setBasketThresholds(uint8 basket, uint16 _healthyBp, uint16 _emergencyBp) internal {
        if (_emergencyBp == 0 || _healthyBp < _emergencyBp) revert SolvencyV4_InvalidThreshold();
        healthyBp[basket] = _healthyBp;
        emergencyBp[basket] = _emergencyBp;
        emit BasketThresholdsSet(basket, _healthyBp, _emergencyBp);
    }

    /// @notice Update per-basket state given current backing & liabilities.
    ///         Called after every mint/burn affecting this basket.
    /// @param basket        basket id (BasketClass cast to uint8)
    /// @param backing       current backing in base units
    /// @param liabilities   current liabilities in base units (= L token supply)
    function _updateBasketSolvency(uint8 basket, uint256 backing, uint256 liabilities) internal {
        SolvencyState prev = solvencyState[basket];
        if (prev == SolvencyState.Recovery) return; // Recovery is exited only via governance

        SolvencyState next;
        if (liabilities == 0) {
            next = SolvencyState.Healthy;
        } else if (backing < liabilities) {
            next = SolvencyState.Emergency;
        } else if (_isBelowHealthy(basket, backing, liabilities)) {
            next = SolvencyState.RestrictedMint;
        } else {
            next = SolvencyState.Healthy;
        }

        if (next != prev) {
            solvencyState[basket] = next;
            emit BasketSolvencyChanged(basket, prev, next);
        }
    }

    /// @notice Overflow-safe check: backing * 10000 < liabilities * healthyBp
    function _isBelowHealthy(uint8 basket, uint256 backing, uint256 liabilities) internal view returns (bool) {
        uint16 h = healthyBp[basket];
        // h is uint16 ≤ 65535, so liabilities * h cannot overflow until
        // liabilities ≈ 1.77e72. backing * 10000 cannot overflow until
        // backing ≈ 1.16e73. We saturate either side conservatively.
        if (liabilities > type(uint256).max / h) return true;
        if (backing > type(uint256).max / 10_000) return false;
        return backing * 10_000 < liabilities * h;
    }

    /// @notice Internal: enter Recovery from Emergency for a specific basket.
    function _enterBasketRecovery(uint8 basket) internal {
        SolvencyState prev = solvencyState[basket];
        if (prev != SolvencyState.Emergency) revert SolvencyV4_NotEmergency();
        solvencyState[basket] = SolvencyState.Recovery;
        emit BasketSolvencyChanged(basket, prev, SolvencyState.Recovery);
    }

    /// @notice Internal: exit Recovery → Healthy or RestrictedMint after
    ///         invariant check (backing >= liabilities required).
    function _exitBasketRecovery(uint8 basket, uint256 backing, uint256 liabilities) internal {
        SolvencyState prev = solvencyState[basket];
        if (prev != SolvencyState.Recovery) revert SolvencyV4_NotInRecovery();
        if (backing < liabilities) revert SolvencyV4_BackingInsufficient();

        SolvencyState next = _isBelowHealthy(basket, backing, liabilities)
            ? SolvencyState.RestrictedMint
            : SolvencyState.Healthy;

        solvencyState[basket] = next;
        emit BasketSolvencyChanged(basket, prev, next);
    }

    /// @notice Read-only: is the basket currently in a state that allows new mints?
    function basketMintAllowed(uint8 basket) public view returns (bool) {
        return solvencyState[basket] == SolvencyState.Healthy;
    }

    /// @notice Read-only: is the basket currently in a state that allows releases?
    function basketReleaseAllowed(uint8 basket) public view returns (bool) {
        SolvencyState s = solvencyState[basket];
        return s != SolvencyState.Emergency && s != SolvencyState.Recovery;
    }
}
