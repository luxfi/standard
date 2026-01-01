// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

/// @title IMarketsCallbacks
/// @notice Callback interface for Markets operations
interface IMarketsCallbacks {
    /// @notice Called during supply
    function onSupply(uint256 assets, bytes calldata data) external;

    /// @notice Called during repay
    function onRepay(uint256 assets, bytes calldata data) external;

    /// @notice Called during supplyCollateral
    function onSupplyCollateral(uint256 assets, bytes calldata data) external;

    /// @notice Called during liquidate
    function onLiquidate(uint256 repaidAssets, bytes calldata data) external;

    /// @notice Called during flashLoan
    function onFlashLoan(uint256 assets, bytes calldata data) external;
}
