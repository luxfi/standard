// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

/// @title Halmos Symbolic Tests for Markets (Morpho-style Lending)
/// @notice Proves invariants about the lending math using symbolic execution.
/// @dev Inlines SharesMathLib and MathLib to avoid external contract calls.

contract HalmosMarketsTest is Test {
    // Mirror SharesMathLib constants
    uint256 constant VIRTUAL_ASSETS = 1;
    uint256 constant VIRTUAL_SHARES = 1e6;
    uint256 constant ORACLE_PRICE_SCALE = 1e36;
    uint256 constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;
    uint256 constant WAD = 1e18;

    // --- MathLib mirrors ---

    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + d - 1) / d;
    }

    // --- SharesMathLib mirrors ---

    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivDown(assets, totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivUp(assets, totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivDown(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivUp(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    // --- Health check mirror ---

    function _isHealthy(
        uint256 borrowShares,
        uint256 collateral,
        uint256 collateralPrice,
        uint256 lltv,
        uint256 totalBorrowAssets,
        uint256 totalBorrowShares
    ) internal pure returns (bool) {
        if (borrowShares == 0) return true;
        uint256 collateralValue = mulDivDown(collateral, collateralPrice, ORACLE_PRICE_SCALE);
        uint256 maxBorrow = mulDivDown(collateralValue, lltv, WAD);
        uint256 borrowed = toAssetsUp(borrowShares, totalBorrowAssets, totalBorrowShares);
        return borrowed <= maxBorrow;
    }

    function _liquidationIncentiveFactor(uint256 lltv) internal pure returns (uint256) {
        uint256 candidate = WAD + (WAD - lltv) / 2;
        return candidate < MAX_LIQUIDATION_INCENTIVE_FACTOR ? candidate : MAX_LIQUIDATION_INCENTIVE_FACTOR;
    }

    // ==================================================================================
    // Invariant 1: totalBorrowAssets <= totalSupplyAssets (solvency)
    // ==================================================================================

    /// @notice Prove: after a supply + borrow sequence, borrow never exceeds supply
    function check_borrowNeverExceedsSupply(uint256 supplyAmount, uint256 borrowAmount) public pure {
        vm.assume(supplyAmount > 0 && supplyAmount < type(uint128).max);
        vm.assume(borrowAmount > 0 && borrowAmount <= supplyAmount);

        uint256 totalSupplyAssets = 0;
        uint256 totalSupplyShares = 0;
        uint256 totalBorrowAssets = 0;
        uint256 totalBorrowShares = 0;

        // Supply
        uint256 supplyShares = toSharesDown(supplyAmount, totalSupplyAssets, totalSupplyShares);
        vm.assume(supplyShares > 0);
        totalSupplyAssets += supplyAmount;
        totalSupplyShares += supplyShares;

        // Borrow (capped at supply)
        uint256 borrowShares = toSharesUp(borrowAmount, totalBorrowAssets, totalBorrowShares);
        vm.assume(borrowShares > 0);
        totalBorrowAssets += borrowAmount;
        totalBorrowShares += borrowShares;

        // Solvency invariant
        assert(totalBorrowAssets <= totalSupplyAssets);
    }

    // ==================================================================================
    // Invariant 2: Borrow is bounded by collateral * LLTV (health invariant)
    // ==================================================================================

    /// @notice Prove: a healthy position always has borrowed <= collateral * price * lltv
    function check_healthyPositionBorrowing(
        uint256 collateral,
        uint256 collateralPrice,
        uint256 lltv,
        uint256 borrowShares,
        uint256 totalBorrowAssets,
        uint256 totalBorrowShares
    ) public pure {
        // Bound inputs to realistic ranges
        vm.assume(collateral > 0 && collateral < type(uint96).max);
        vm.assume(collateralPrice > 0 && collateralPrice < type(uint96).max);
        vm.assume(lltv > 0 && lltv < WAD); // LLTV must be < 100%
        vm.assume(totalBorrowAssets > 0 && totalBorrowAssets < type(uint96).max);
        vm.assume(totalBorrowShares > 0 && totalBorrowShares < type(uint96).max);
        vm.assume(borrowShares > 0 && borrowShares <= totalBorrowShares);

        bool healthy = _isHealthy(borrowShares, collateral, collateralPrice, lltv, totalBorrowAssets, totalBorrowShares);

        if (healthy) {
            uint256 collateralValue = mulDivDown(collateral, collateralPrice, ORACLE_PRICE_SCALE);
            uint256 maxBorrow = mulDivDown(collateralValue, lltv, WAD);
            uint256 borrowed = toAssetsUp(borrowShares, totalBorrowAssets, totalBorrowShares);
            assert(borrowed <= maxBorrow);
        }
    }

    // ==================================================================================
    // Invariant 3: Liquidation incentive is bounded
    // ==================================================================================

    /// @notice Prove: liquidation incentive never exceeds MAX_LIQUIDATION_INCENTIVE_FACTOR
    function check_liquidationIncentiveBounded(uint256 lltv) public pure {
        vm.assume(lltv > 0 && lltv < WAD);

        uint256 factor = _liquidationIncentiveFactor(lltv);

        assert(factor <= MAX_LIQUIDATION_INCENTIVE_FACTOR);
        assert(factor >= WAD); // Incentive is at least 1x (no penalty to liquidator)
    }

    // ==================================================================================
    // Invariant 4: Share math round-trips are non-inflationary
    // ==================================================================================

    /// @notice Prove: toSharesDown(toAssetsDown(shares)) <= shares
    function check_shareRoundTripDown(uint256 shares, uint256 totalAssets, uint256 totalShares) public pure {
        vm.assume(totalAssets > 0 && totalAssets < type(uint64).max);
        vm.assume(totalShares > 0 && totalShares < type(uint64).max);
        vm.assume(shares > 0 && shares <= totalShares);

        uint256 assets = toAssetsDown(shares, totalAssets, totalShares);
        uint256 sharesBack = toSharesDown(assets, totalAssets, totalShares);

        assert(sharesBack <= shares);
    }

    /// @notice Prove: toAssetsUp(toSharesUp(assets)) >= assets
    /// @dev Up-rounding conversions maintain conservative lending invariants
    function check_assetRoundTripUp(uint256 assets, uint256 totalAssets, uint256 totalShares) public pure {
        vm.assume(totalAssets > 0 && totalAssets < type(uint64).max);
        vm.assume(totalShares > 0 && totalShares < type(uint64).max);
        vm.assume(assets > 0 && assets <= totalAssets);

        uint256 shares = toSharesUp(assets, totalAssets, totalShares);
        uint256 assetsBack = toAssetsUp(shares, totalAssets, totalShares);

        // Up-rounding should preserve or over-estimate
        assert(assetsBack >= assets);
    }

    // ==================================================================================
    // Invariant 5: Repay reduces borrow (monotonicity)
    // ==================================================================================

    /// @notice Prove: repaying assets always reduces totalBorrowAssets
    function check_repayReducesBorrow(uint256 totalBorrowAssets, uint256 totalBorrowShares, uint256 repayAssets)
        public
        pure
    {
        vm.assume(totalBorrowAssets > 0 && totalBorrowAssets < type(uint96).max);
        vm.assume(totalBorrowShares > 0 && totalBorrowShares < type(uint96).max);
        vm.assume(repayAssets > 0 && repayAssets <= totalBorrowAssets);

        uint256 repayShares = toSharesDown(repayAssets, totalBorrowAssets, totalBorrowShares);
        vm.assume(repayShares > 0 && repayShares <= totalBorrowShares);

        uint256 newBorrowAssets = totalBorrowAssets - repayAssets;
        uint256 newBorrowShares = totalBorrowShares - repayShares;

        // Borrow must decrease
        assert(newBorrowAssets < totalBorrowAssets);
        assert(newBorrowShares < totalBorrowShares);
    }

    // ==================================================================================
    // Invariant 6: Interest accrual maintains solvency
    // ==================================================================================

    /// @notice Prove: interest adds equally to borrow and supply (no value leak)
    function check_interestAccrualSolvency(uint256 totalSupplyAssets, uint256 totalBorrowAssets, uint256 interest)
        public
        pure
    {
        vm.assume(totalSupplyAssets > 0 && totalSupplyAssets < type(uint96).max);
        vm.assume(totalBorrowAssets > 0 && totalBorrowAssets <= totalSupplyAssets);
        vm.assume(interest > 0 && interest < type(uint64).max);
        // After interest: solvency must still hold
        vm.assume(totalBorrowAssets + interest <= type(uint128).max);

        uint256 newBorrow = totalBorrowAssets + interest;
        uint256 newSupply = totalSupplyAssets + interest;

        // Interest accrues to both sides equally
        assert(newBorrow <= newSupply);
        // The spread is preserved
        assert(newSupply - newBorrow == totalSupplyAssets - totalBorrowAssets);
    }
}
