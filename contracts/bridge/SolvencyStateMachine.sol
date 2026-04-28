// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SolvencyStateMachine
 * @author Lux Industries
 * @notice 4-state graduated response for bridge solvency:
 *
 *   Healthy        -- B >= L and B >= L/0.9   -- all ops allowed
 *   RestrictedMint -- B >= L but B < L/0.9    -- burns/releases ok, new mints blocked
 *   Emergency      -- B < L or B < 0.985*L    -- burns ok, releases queued
 *   Recovery       -- governance-initiated     -- burns ok, releases queued, manual exit
 *
 *   Transitions:
 *     Healthy -> RestrictedMint : backing drops below 111% of liabilities
 *     Healthy -> Emergency      : backing drops below liabilities
 *     RestrictedMint -> Healthy : backing restored above 111%
 *     RestrictedMint -> Emergency : backing drops below liabilities
 *     Emergency -> Recovery     : MPC quorum calls enterRecovery()
 *     Recovery -> Healthy       : MPC quorum calls exitRecovery() + invariant check passes
 *     Any -> Emergency          : backing < liabilities (automatic)
 */

enum SolvencyState {
    Healthy,
    RestrictedMint,
    Emergency,
    Recovery
}

abstract contract SolvencyStateMachine {
    /// @notice Current solvency state
    SolvencyState public solvencyState;

    /// @notice Emitted on every state transition
    event SolvencyStateChanged(SolvencyState indexed previous, SolvencyState indexed current);

    // ================================================================
    //  MODIFIERS
    // ================================================================

    /// @notice Only when fully healthy
    modifier onlyHealthy() {
        require(solvencyState == SolvencyState.Healthy, "not healthy");
        _;
    }

    /// @notice Minting allowed only in Healthy state
    modifier mintAllowed() {
        require(solvencyState == SolvencyState.Healthy, "mint restricted");
        _;
    }

    /// @notice Burns are always allowed (exit guarantee for users)
    modifier burnAllowed() {
        _;
    }

    /// @notice Releases blocked in Emergency and Recovery (queued instead)
    modifier releaseAllowed() {
        require(solvencyState != SolvencyState.Emergency && solvencyState != SolvencyState.Recovery, "releases queued");
        _;
    }

    // ================================================================
    //  STATE TRANSITIONS
    // ================================================================

    /// @notice Update solvency state based on backing vs liabilities
    /// @param backing Total backing value (locked on source chains)
    /// @param liabilities Total liabilities (minted bridged tokens)
    /// @dev Called after every backing attestation.
    ///
    ///   Healthy:        B >= L and B*9 >= L*10   (i.e. B >= L/0.9 = L*10/9)
    ///   RestrictedMint: B >= L but B*9 < L*10
    ///   Emergency:      B < L
    ///
    ///   Recovery state is not entered automatically -- only via enterRecovery().
    ///   If in Recovery and backing is restored, exitRecovery() must be called.
    function _updateSolvencyState(uint256 backing, uint256 liabilities) internal {
        // Recovery state is only exited explicitly, not by ratio changes
        if (solvencyState == SolvencyState.Recovery) return;

        SolvencyState previous = solvencyState;
        SolvencyState next;

        if (liabilities == 0) {
            next = SolvencyState.Healthy;
        } else if (backing < liabilities) {
            next = SolvencyState.Emergency;
        } else if (_isUndercollateralized(backing, liabilities)) {
            // B < L * 10/9, overflow-safe
            next = SolvencyState.RestrictedMint;
        } else {
            next = SolvencyState.Healthy;
        }

        if (next != previous) {
            solvencyState = next;
            emit SolvencyStateChanged(previous, next);
        }
    }

    /// @notice Overflow-safe check: backing * 9 < liabilities * 10
    function _isUndercollateralized(uint256 backing, uint256 liabilities) internal pure returns (bool) {
        // backing < liabilities * 10 / 9, but overflow-safe
        // Equivalent: backing * 9 < liabilities * 10
        // Safe if we check for overflow first
        if (liabilities > type(uint256).max / 10) {
            return true; // liabilities so large that system is certainly undercollateralized
        }
        if (backing > type(uint256).max / 9) {
            return false; // backing so large that system is certainly overcollateralized
        }
        return backing * 9 < liabilities * 10;
    }

    /// @notice Enter Recovery mode (MPC quorum required)
    /// @dev Implementor must enforce MPC signature verification
    function enterRecovery() external virtual;

    /// @notice Exit Recovery mode (MPC quorum + invariant check)
    /// @dev Implementor must verify backing >= liabilities before calling _exitRecovery
    function exitRecovery() external virtual;

    /// @notice Internal: set state to Healthy from Recovery after invariant check
    /// @param backing Current backing
    /// @param liabilities Current liabilities
    function _exitRecovery(uint256 backing, uint256 liabilities) internal {
        require(solvencyState == SolvencyState.Recovery, "not in recovery");
        require(backing >= liabilities, "backing insufficient");

        SolvencyState previous = solvencyState;

        // Determine correct state based on current ratios (overflow-safe)
        if (!_isUndercollateralized(backing, liabilities)) {
            solvencyState = SolvencyState.Healthy;
        } else {
            solvencyState = SolvencyState.RestrictedMint;
        }

        emit SolvencyStateChanged(previous, solvencyState);
    }

    /// @notice Internal: enter Recovery from Emergency
    function _enterRecovery() internal {
        require(solvencyState == SolvencyState.Emergency, "recovery only from emergency");
        SolvencyState previous = solvencyState;
        solvencyState = SolvencyState.Recovery;
        emit SolvencyStateChanged(previous, SolvencyState.Recovery);
    }
}
