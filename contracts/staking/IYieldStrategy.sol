// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
 * @title IYieldStrategy
 * @author Lux Industries
 * @notice Yield strategy plug for sL* ERC-4626 vaults.
 *
 * Each sL* vault has at most one IYieldStrategy attached. The vault's
 * OPERATOR_ROLE calls strategy.harvest() to pull yield from external venues
 * (Aave / Compound / Lido / restaking / etc.). The strategy is responsible
 * for handing harvested L tokens back to the vault via transfer; the vault
 * accounts for them by reading its own L-token balance against `totalAssets()`.
 *
 * Strategies are SWAPPABLE — governance can detach and replace one at any
 * time, provided harvest() has been called and the strategy's externally-held
 * balance is fully drained back to the vault.
 */
interface IYieldStrategy {
    /// @notice The L token this strategy farms with
    function liquidToken() external view returns (address);

    /// @notice Pull pending yield into the strategy's balance and immediately
    ///         transfer it to the vault. Returns the amount harvested.
    function harvest() external returns (uint256 harvested);

    /// @notice Sum of L tokens externally deployed by this strategy (across
    ///         all integrated venues). Used by the vault to compute totalAssets.
    function externalBalance() external view returns (uint256);

    /// @notice Withdraw `amount` of L tokens from external venues back to the
    ///         vault. Used during strategy swap. May be capped by venue
    ///         liquidity; caller should re-try if `returned < amount`.
    function unwindTo(address vault, uint256 amount) external returns (uint256 returned);
}
