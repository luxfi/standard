// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

/// @title Halmos Symbolic Tests for LiquidLUX (xLUX) Vault
/// @notice Proves invariants about the share/asset math using symbolic execution.
/// @dev We inline the vault math here rather than importing the full contract,
///      because Halmos works best when it can reason about pure math without
///      external calls, storage-heavy state, or OZ modifiers.

contract HalmosLiquidLUXTest is Test {
    // Mirror the vault constants
    uint256 constant VIRTUAL_SHARES = 1e6;
    uint256 constant VIRTUAL_ASSETS = 1e6;
    uint256 constant MINIMUM_LIQUIDITY = 1e6;
    uint256 constant BPS = 10_000;
    uint256 constant MAX_PERF_FEE_BPS = 2000;

    // --- Share/asset conversion (matches LiquidLUX._convertToShares / _convertToAssets) ---

    function _convertToShares(uint256 assets, uint256 totalSupply, uint256 totalAssets)
        internal
        pure
        returns (uint256)
    {
        return (assets * (totalSupply + VIRTUAL_SHARES)) / (totalAssets + VIRTUAL_ASSETS);
    }

    function _convertToAssets(uint256 shares, uint256 totalSupply, uint256 totalAssets)
        internal
        pure
        returns (uint256)
    {
        return (shares * (totalAssets + VIRTUAL_ASSETS)) / (totalSupply + VIRTUAL_SHARES);
    }

    // ==================================================================================
    // Invariant 1: No depositor can withdraw more than they deposited + earned yield
    // ==================================================================================

    /// @notice Prove: deposit then immediate withdraw returns <= deposited amount
    /// @dev With no yield added between deposit and withdraw, shares redeem for at most
    ///      the deposited amount (minus rounding).
    function check_noExcessWithdrawal(uint256 depositAmount) public pure {
        // Bound to avoid overflow and trivial zero case
        vm.assume(depositAmount > MINIMUM_LIQUIDITY + 1);
        vm.assume(depositAmount < type(uint64).max);

        // Simulate first deposit into empty vault
        uint256 totalAssets_before = 0;
        uint256 totalSupply_before = 0;

        uint256 shares = _convertToShares(depositAmount, totalSupply_before, totalAssets_before);
        vm.assume(shares > MINIMUM_LIQUIDITY); // First deposit locks MINIMUM_LIQUIDITY

        // After first deposit: MINIMUM_LIQUIDITY goes to dead, rest to user
        uint256 userShares = shares - MINIMUM_LIQUIDITY;
        uint256 totalSupply_after = shares; // includes dead shares
        uint256 totalAssets_after = depositAmount;

        // Withdraw all user shares immediately (no yield added)
        uint256 withdrawnAssets = _convertToAssets(userShares, totalSupply_after, totalAssets_after);

        // User must not get more than they deposited
        assert(withdrawnAssets <= depositAmount);
    }

    // ==================================================================================
    // Invariant 2: Total shares always correspond to total assets (no free minting)
    // ==================================================================================

    /// @notice Prove: convertToShares(convertToAssets(shares)) <= shares (round-trip)
    /// @dev Converting shares -> assets -> shares must not increase shares due to rounding
    function check_shareAssetRoundTrip(uint256 shares, uint256 totalSupply, uint256 totalAssets) public pure {
        // Avoid division by zero and overflow
        vm.assume(totalSupply > 0 && totalSupply < type(uint64).max);
        vm.assume(totalAssets > 0 && totalAssets < type(uint64).max);
        vm.assume(shares > 0 && shares <= totalSupply);

        uint256 assets = _convertToAssets(shares, totalSupply, totalAssets);
        uint256 sharesBack = _convertToShares(assets, totalSupply, totalAssets);

        // Round-trip must not inflate shares
        assert(sharesBack <= shares);
    }

    /// @notice Prove: convertToAssets(convertToShares(assets)) <= assets (round-trip)
    /// @dev Converting assets -> shares -> assets must not increase assets due to rounding
    function check_assetShareRoundTrip(uint256 assets, uint256 totalSupply, uint256 totalAssets) public pure {
        vm.assume(totalSupply > 0 && totalSupply < type(uint64).max);
        vm.assume(totalAssets > 0 && totalAssets < type(uint64).max);
        vm.assume(assets > 0 && assets <= totalAssets);

        uint256 shares = _convertToShares(assets, totalSupply, totalAssets);
        uint256 assetsBack = _convertToAssets(shares, totalSupply, totalAssets);

        // Round-trip must not inflate assets
        assert(assetsBack <= assets);
    }

    // ==================================================================================
    // Invariant 3: Performance fee never exceeds configured cap
    // ==================================================================================

    /// @notice Prove: performance fee calculation is bounded by MAX_PERF_FEE_BPS
    function check_perfFeeBounded(uint256 amount, uint256 perfFeeBps) public pure {
        vm.assume(amount > 0 && amount < type(uint64).max);
        vm.assume(perfFeeBps <= MAX_PERF_FEE_BPS);

        uint256 perfFee = (amount * perfFeeBps) / BPS;

        // Fee must never exceed 20% of amount
        assert(perfFee <= (amount * MAX_PERF_FEE_BPS) / BPS);
        // Fee must never exceed the input amount
        assert(perfFee <= amount);
    }

    // ==================================================================================
    // Invariant 4: Exchange rate monotonically non-decreasing with fee injection
    // ==================================================================================

    /// @notice Prove: adding fees to vault can only increase or maintain exchange rate
    function check_exchangeRateMonotonic(uint256 totalAssets, uint256 totalSupply, uint256 feeAmount) public pure {
        vm.assume(totalSupply > 0 && totalSupply < type(uint64).max);
        vm.assume(totalAssets > 0 && totalAssets < type(uint64).max);
        vm.assume(feeAmount > 0 && feeAmount < type(uint64).max);

        // Exchange rate before: (totalAssets + VIRTUAL) * 1e18 / (totalSupply + VIRTUAL)
        uint256 rateBefore = ((totalAssets + VIRTUAL_ASSETS) * 1e18) / (totalSupply + VIRTUAL_SHARES);

        // After fee injection (no new shares minted, just assets increase)
        uint256 rateAfter = ((totalAssets + feeAmount + VIRTUAL_ASSETS) * 1e18) / (totalSupply + VIRTUAL_SHARES);

        assert(rateAfter >= rateBefore);
    }

    // ==================================================================================
    // Invariant 5: Deposit amount of zero shares is impossible with nonzero deposit
    // ==================================================================================

    /// @notice Prove: deposit >= totalAssets/totalSupply always produces nonzero shares
    /// @dev A deposit of 1 wei can round to 0 shares when totalAssets >> totalSupply,
    ///      but a deposit proportional to the share price always produces shares.
    function check_nonzeroDepositProducesShares(uint256 depositAmount, uint256 totalSupply, uint256 totalAssets)
        public
        pure
    {
        vm.assume(totalSupply < type(uint64).max);
        vm.assume(totalAssets < type(uint64).max);
        // Deposit must be at least 1 share worth: assets/shares ratio
        // (totalAssets + VIRTUAL) / (totalSupply + VIRTUAL) is the price per share
        // deposit must be >= this to get at least 1 share
        uint256 sharePrice = (totalAssets + VIRTUAL_ASSETS) / (totalSupply + VIRTUAL_SHARES);
        vm.assume(depositAmount >= sharePrice + 1);
        vm.assume(depositAmount < type(uint64).max);

        uint256 shares = _convertToShares(depositAmount, totalSupply, totalAssets);

        // Depositing at least 1 share's worth always produces nonzero shares
        assert(shares > 0);
    }

    // ==================================================================================
    // Invariant 6: Virtual shares prevent ERC-4626 inflation attack
    // The classic attack: deposit 1 wei, donate huge amount, next depositor gets 0 shares
    // ==================================================================================

    /// @notice Prove: With virtual shares, second depositor ALWAYS gets > 0 shares despite donation
    /// @dev Models the full attack sequence: first deposit -> donation -> second deposit
    function check_virtualSharesPreventInflation(
        uint256 firstDeposit,
        uint256 donation,
        uint256 secondDeposit
    ) public pure {
        // First depositor makes a valid deposit
        vm.assume(firstDeposit > MINIMUM_LIQUIDITY * 2 && firstDeposit < 1e24);
        // Attacker donation: can be anything up to a very large amount
        vm.assume(donation < 1e24);
        // Second depositor: reasonable deposit (at least 1 token = 1e18 wei for 18-decimal)
        vm.assume(secondDeposit >= 1e18 && secondDeposit < 1e24);

        // === Phase 1: First deposit ===
        // shares = firstDeposit * (0 + 1e6) / (0 + 1e6) = firstDeposit
        uint256 shares1 = _convertToShares(firstDeposit, 0, 0);
        vm.assume(shares1 > MINIMUM_LIQUIDITY);

        // Burn MINIMUM_LIQUIDITY to dead address
        shares1 -= MINIMUM_LIQUIDITY;
        uint256 totalSupply = shares1 + MINIMUM_LIQUIDITY;
        uint256 totalAssets = firstDeposit;

        // === Phase 2: Attacker donates directly to vault ===
        totalAssets += donation;

        // === Phase 3: Second depositor deposits ===
        uint256 shares2 = _convertToShares(secondDeposit, totalSupply, totalAssets);

        // Virtual shares prevent rounding-to-zero attack
        assert(shares2 > 0);
    }

    // ==================================================================================
    // Invariant 7: MINIMUM_LIQUIDITY burn prevents complete vault drainage
    // ==================================================================================

    /// @notice Prove: After first depositor withdraws, dead address shares retain value
    function check_minimumLiquidityPreventsFullDrain(
        uint256 firstDeposit,
        uint256 donation
    ) public pure {
        vm.assume(firstDeposit > MINIMUM_LIQUIDITY * 2 && firstDeposit < 1e24);
        vm.assume(donation < 1e24);

        // First deposit
        uint256 shares1 = _convertToShares(firstDeposit, 0, 0);
        vm.assume(shares1 > MINIMUM_LIQUIDITY);
        shares1 -= MINIMUM_LIQUIDITY;

        uint256 totalSupply = shares1 + MINIMUM_LIQUIDITY;
        uint256 totalAssets = firstDeposit;

        // Attacker donates
        totalAssets += donation;

        // Attacker withdraws ALL their shares
        uint256 attackerWithdrawal = _convertToAssets(shares1, totalSupply, totalAssets);

        // After attacker withdraws, dead address still holds MINIMUM_LIQUIDITY shares
        uint256 remainingSupply = totalSupply - shares1;
        uint256 remainingAssets = totalAssets - attackerWithdrawal;

        // Dead address shares retain value -- pool is never fully drained
        assert(remainingSupply == MINIMUM_LIQUIDITY);
        uint256 deadValue = _convertToAssets(MINIMUM_LIQUIDITY, remainingSupply, remainingAssets);
        assert(deadValue > 0);
    }

    // ==================================================================================
    // Invariant 8: Deposit never decreases share price for existing holders
    // ==================================================================================

    /// @notice Prove: share price is monotonically non-decreasing across deposits
    function check_depositNeverDecreasesSharePrice(
        uint256 existingSupply,
        uint256 existingAssets,
        uint256 depositAmount
    ) public pure {
        vm.assume(existingSupply > MINIMUM_LIQUIDITY && existingSupply < 1e27);
        vm.assume(existingAssets > MINIMUM_LIQUIDITY && existingAssets < 1e27);
        vm.assume(depositAmount > 0 && depositAmount < 1e27);

        // Share price before (scaled by 1e18)
        uint256 priceBefore = ((existingAssets + VIRTUAL_ASSETS) * 1e18) / (existingSupply + VIRTUAL_SHARES);

        // Deposit: get shares
        uint256 newShares = _convertToShares(depositAmount, existingSupply, existingAssets);
        vm.assume(newShares > 0);

        // New state
        uint256 newSupply = existingSupply + newShares;
        uint256 newAssets = existingAssets + depositAmount;

        // Share price after
        uint256 priceAfter = ((newAssets + VIRTUAL_ASSETS) * 1e18) / (newSupply + VIRTUAL_SHARES);

        // Share price must not decrease
        assert(priceAfter >= priceBefore);
    }
}
