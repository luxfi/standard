// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title PerAssetLedger
 * @author Lux Industries
 * @notice Abstract ledger tracking the per-asset reserve inventory inside a
 *         LiquidX pool. Decouples bookkeeping from the SolvencyStateMachine —
 *         the pool calls _recordDeposit/_recordWithdraw on every basket-asset
 *         movement, and the solvency machine reads totalReserveInBaseUnits()
 *         on every state recheck.
 *
 * Decimal normalization: reserves are stored as RAW token units (the asset's
 * own decimals). The pool's `_normalize` view converts asset units → basket
 * base-unit (18 decimals everywhere except LBTC which uses 8 sat parity, LSOL
 * 9, LTON 9, LXRP 6, LDOT 10). The base-unit conversion is the pool's
 * responsibility; this ledger is decimals-agnostic.
 */
abstract contract PerAssetLedger {
    /// @notice asset address → reserve balance in raw token units
    mapping(address => uint256) private _assetReserves;

    /// @notice Sum of all per-asset reserves expressed in pool-base units.
    ///         Maintained incrementally on every _recordDeposit/_recordWithdraw.
    uint256 private _totalReserveBaseUnits;

    error PerAssetLedger_InsufficientReserve();

    event ReserveDeposited(address indexed asset, uint256 raw, uint256 baseUnitDelta);
    event ReserveWithdrawn(address indexed asset, uint256 raw, uint256 baseUnitDelta);

    /// @notice Read the current raw-unit reserve of one asset in this pool
    function assetReserve(address asset) public view returns (uint256) {
        return _assetReserves[asset];
    }

    /// @notice Read the cached base-unit sum across all basket members
    function totalReserveInBaseUnits() public view returns (uint256) {
        return _totalReserveBaseUnits;
    }

    /// @notice Internal: record an inbound deposit
    /// @param asset      bridged asset address
    /// @param rawAmount  amount in the asset's own decimals
    /// @param baseUnits  amount normalized to pool base units
    function _recordDeposit(address asset, uint256 rawAmount, uint256 baseUnits) internal {
        _assetReserves[asset] += rawAmount;
        _totalReserveBaseUnits += baseUnits;
        emit ReserveDeposited(asset, rawAmount, baseUnits);
    }

    /// @notice Internal: record an outbound withdrawal. Reverts if reserve would underflow.
    /// @param asset      bridged asset address
    /// @param rawAmount  amount in the asset's own decimals
    /// @param baseUnits  amount normalized to pool base units
    function _recordWithdraw(address asset, uint256 rawAmount, uint256 baseUnits) internal {
        uint256 r = _assetReserves[asset];
        if (r < rawAmount) revert PerAssetLedger_InsufficientReserve();
        unchecked {
            _assetReserves[asset] = r - rawAmount;
        }
        if (_totalReserveBaseUnits < baseUnits) {
            // Defensive: shouldn't happen if deposits/withdraws are balanced,
            // but guard against precision drift in oracle-priced baskets.
            _totalReserveBaseUnits = 0;
        } else {
            unchecked {
                _totalReserveBaseUnits -= baseUnits;
            }
        }
        emit ReserveWithdrawn(asset, rawAmount, baseUnits);
    }
}
