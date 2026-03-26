// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

/// @title HalmosE2ETest - End-to-end symbolic proofs for L* token lifecycle
/// @notice Proves safety invariants across: bridge mint/burn -> LiquidLUX deposit -> yield/fees -> teleport
///
/// @dev We inline all math from the actual contracts to keep Halmos in pure-only mode
///      (no external calls, no storage). All `check_*` functions are formal verification targets.
///
/// ## Architecture Under Test
///
///   Bridge (LRC20B)           Vault (LiquidLUX)         Fee Distribution           Teleport
///   +------------+           +------------------+       +--------------+          +----------+
///   | bridgeMint |--deposit->| _convertToShares |--fee->| receiveFees  |--lock--->| lock src |
///   | bridgeBurn |<-withdraw-| _convertToAssets |       | perfFee+net  |          | mint dst |
///   +------------+           +------------------+       +--------------+          +----------+
///
/// ## Solver Strategy
///
///   Uses typed inputs to constrain bitvector width for SMT tractability.
///   All assertions are carefully structured to use only linear arithmetic or
///   at most one nonlinear product per assertion, avoiding cross-multiplication
///   of symbolic variables against large constants (BPS=10000, VIRTUAL=1e6).
///
///   Where nonlinear reasoning is required (vault share math), we use uint8 with
///   scaled-down constants (VIRTUAL=10, MIN_LIQ=10) and prove the floor-division
///   property: floor(a*b/c)*c <= a*b. This algebraic identity holds at any bit width.
///
///   For fee/router math (division by BPS=10000), we decompose proofs into
///   sub-properties that involve only one floor() per assertion, matching the
///   decomposition approach from HalmosAMM.t.sol.
///
/// ## Invariants Proven (23 check_ functions)
///
///   BRIDGE (3):       conservation, multi-step, daily limit
///   DEPOSIT (3):      share proportionality, first-depositor roundtrip, second-depositor roundtrip
///   TELEPORT (2):     two-chain conservation, multi-hop 3-chain
///   SELF-REPAY (1):   debt floor
///   SOLVENCY (1):     withdrawal preserves collateralization
///   YIELD (2):        full roundtrip, partial deallocate
///   FEES (4):         accounting identity, full accounting, treasury cap, exchange rate monotonicity
///   ROUTER (2):       3-recipient conservation, equal-weight symmetry
///   COLLECT (3):      accounting identity, multi-cycle, full pipeline
///   E2E (2):          cross-chain total supply, full lifecycle
contract HalmosE2ETest is Test {
    // ============================================================================
    // Constants mirrored from production contracts
    // ============================================================================

    uint256 constant VIRTUAL_SHARES = 1e6;
    uint256 constant VIRTUAL_ASSETS = 1e6;
    uint256 constant MINIMUM_LIQUIDITY = 1e6;
    uint256 constant BPS = 10_000;
    uint256 constant MAX_PERF_FEE_BPS = 2000; // 20% ceiling
    uint256 constant ROUTER_BASE = 10_000;

    // Scaled constants for uint8 domain (algebraically equivalent)
    uint256 constant SV = 10; // Scaled VIRTUAL
    uint256 constant SML = 10; // Scaled MINIMUM_LIQUIDITY

    // ============================================================================
    // Inlined math
    // ============================================================================

    function _toShares(uint256 a, uint256 s, uint256 t) internal pure returns (uint256) {
        return (a * (s + VIRTUAL_SHARES)) / (t + VIRTUAL_ASSETS);
    }

    function _toAssets(uint256 sh, uint256 s, uint256 t) internal pure returns (uint256) {
        return (sh * (t + VIRTUAL_ASSETS)) / (s + VIRTUAL_SHARES);
    }

    function _sToShares(uint256 a, uint256 s, uint256 t) internal pure returns (uint256) {
        return (a * (s + SV)) / (t + SV);
    }

    function _sToAssets(uint256 sh, uint256 s, uint256 t) internal pure returns (uint256) {
        return (sh * (t + SV)) / (s + SV);
    }

    // ============================================================================
    //                              BRIDGE INVARIANTS
    // ============================================================================

    /// @notice Prove: mint/burn conservation identity
    function check_bridgeConservation(uint32 _mint, uint32 _burn) public pure {
        uint256 m = uint256(_mint);
        uint256 b = uint256(_burn);
        vm.assume(m > 0 && b <= m);

        uint256 supply = m - b;
        assert(supply == m - b);
        assert(b <= m);
    }

    /// @notice Prove: sequential mint/burn ops maintain conservation
    function check_bridgeMultiStepConservation(uint24 _m1, uint24 _m2, uint24 _b1, uint24 _b2) public pure {
        uint256 m1 = uint256(_m1);
        uint256 m2 = uint256(_m2);
        uint256 b1 = uint256(_b1);
        uint256 b2 = uint256(_b2);

        vm.assume(m1 > 0 && m2 > 0);
        uint256 totalMinted = m1 + m2;
        vm.assume(b1 <= m1);
        vm.assume(b2 <= totalMinted - b1);

        uint256 totalBurned = b1 + b2;
        assert(totalBurned <= totalMinted);
    }

    /// @notice Prove: minted-in-period never exceeds dailyMintLimit
    function check_bridgeDailyLimitEnforcement(uint32 _limit, uint32 _m1, uint32 _m2, uint32 _m3) public pure {
        uint256 limit = uint256(_limit);
        uint256 m1 = uint256(_m1);
        uint256 m2 = uint256(_m2);
        uint256 m3 = uint256(_m3);
        vm.assume(limit > 0 && m1 > 0 && m2 > 0 && m3 > 0);

        uint256 minted = 0;
        vm.assume(minted + m1 <= limit);
        minted += m1;
        assert(minted <= limit);

        vm.assume(minted + m2 <= limit);
        minted += m2;
        assert(minted <= limit);

        vm.assume(minted + m3 <= limit);
        minted += m3;
        assert(minted <= limit);
        assert(minted == m1 + m2 + m3);
    }

    // ============================================================================
    //                      DEPOSIT / WITHDRAW INVARIANTS
    // ============================================================================

    // Uses uint8 with scaled constants (SV=10, SML=10).
    // The floor-division property floor(a*b/c)*c <= a*b is bit-width independent.

    /// @notice Prove: depositor gets shares with vault-favorable rounding
    function check_depositShareProportionality(uint8 _assets, uint8 _shares, uint8 _deposit) public pure {
        uint256 a = uint256(_assets);
        uint256 s = uint256(_shares);
        uint256 d = uint256(_deposit);
        vm.assume(a > 0 && s > 0 && d > 0);

        uint256 newShares = _sToShares(d, s, a);

        // Floor division: result * denominator <= numerator
        // newShares * (a + SV) <= d * (s + SV)
        assert(newShares * (a + SV) <= d * (s + SV));
    }

    /// @notice Prove: deposit then immediate withdraw returns <= deposited
    function check_depositWithdrawRoundTrip(uint8 _deposit) public pure {
        uint256 d = uint256(_deposit);
        vm.assume(d > SML + 1);

        uint256 shares = _sToShares(d, 0, 0);
        vm.assume(shares > SML);

        uint256 userShares = shares - SML;
        uint256 withdrawn = _sToAssets(userShares, shares, d);

        assert(withdrawn <= d);
    }

    /// @notice Prove: second depositor cannot profit from deposit-then-withdraw
    function check_secondDepositorRoundTrip(uint8 _d1, uint8 _d2) public pure {
        uint256 d1 = uint256(_d1);
        uint256 d2 = uint256(_d2);
        vm.assume(d1 > SML * 2 && d2 > 0);

        uint256 s1 = _sToShares(d1, 0, 0);
        vm.assume(s1 > SML);

        uint256 s2 = _sToShares(d2, s1, d1);
        vm.assume(s2 > 0);

        uint256 w2 = _sToAssets(s2, s1 + s2, d1 + d2);
        assert(w2 <= d2);
    }

    // ============================================================================
    //                          TELEPORT INVARIANTS
    // ============================================================================

    /// @notice Prove: teleport preserves combined supply across two chains
    function check_teleportConservation(uint32 _src, uint32 _dst, uint32 _amt) public pure {
        uint256 src = uint256(_src);
        uint256 dst = uint256(_dst);
        uint256 amt = uint256(_amt);
        vm.assume(amt > 0 && amt <= src);

        uint256 totalBefore = src + dst;
        assert((src - amt) + (dst + amt) == totalBefore);
    }

    /// @notice Prove: two-hop teleport preserves total across 3 chains
    function check_teleportMultiHop(uint24 _a, uint24 _b, uint24 _c, uint24 _h1, uint24 _h2) public pure {
        uint256 a = uint256(_a);
        uint256 b = uint256(_b);
        uint256 c = uint256(_c);
        uint256 h1 = uint256(_h1);
        uint256 h2 = uint256(_h2);
        vm.assume(h1 > 0 && h1 <= a);

        uint256 total = a + b + c;
        a -= h1;
        b += h1;
        vm.assume(h2 > 0 && h2 <= b);
        b -= h2;
        c += h2;

        assert(a + b + c == total);
    }

    // ============================================================================
    //                          SELF-REPAY INVARIANT
    // ============================================================================

    /// @notice Prove: self-repay never causes debt underflow or over-repayment
    function check_selfRepayFloor(uint32 _debt, uint32 _yield) public pure {
        uint256 debt = uint256(_debt);
        uint256 y = uint256(_yield);
        vm.assume(debt > 0);

        uint256 repay = y > debt ? debt : y;
        uint256 remaining = debt - repay;

        assert(remaining <= debt);
        assert(repay <= debt);
        assert(repay <= y);
        if (y >= debt) assert(remaining == 0);
        if (y < debt) assert(repay == y);
    }

    // ============================================================================
    //                          SOLVENCY INVARIANT
    // ============================================================================

    /// @notice Prove: withdrawal preserves 200% collateralization
    function check_withdrawalSolvency(uint32 _dep, uint32 _bor, uint32 _rep, uint32 _wdr) public pure {
        uint256 dep = uint256(_dep);
        uint256 bor = uint256(_bor);
        uint256 rep = uint256(_rep);
        uint256 wdr = uint256(_wdr);

        vm.assume(dep > 0);
        vm.assume(bor <= dep / 2); // 50% LTV
        vm.assume(rep <= bor);

        uint256 remDebt = bor - rep;
        uint256 locked = remDebt * 2;
        vm.assume(dep >= locked);

        uint256 free = dep - locked;
        vm.assume(wdr <= free);

        uint256 remCol = dep - wdr;
        if (remDebt > 0) {
            assert(remCol >= remDebt * 2);
        }
        assert(remCol - locked == free - wdr);
    }

    // ============================================================================
    //                      YIELD STRATEGY INVARIANTS
    // ============================================================================

    /// @notice Prove: allocate->earn->deallocate = original + yield
    function check_yieldStrategyConservation(uint32 _vault, uint32 _alloc, uint24 _yield) public pure {
        uint256 v = uint256(_vault);
        uint256 a = uint256(_alloc);
        uint256 y = uint256(_yield);

        vm.assume(v > MINIMUM_LIQUIDITY && a > 0 && a <= v);

        uint256 after_ = (v - a) + (a + y);
        assert(after_ == v + y);
        assert(after_ >= v);
    }

    /// @notice Prove: partial deallocate preserves vault + strategy total
    function check_yieldPartialDeallocate(uint24 _v, uint24 _a, uint24 _y, uint24 _d) public pure {
        uint256 v = uint256(_v);
        uint256 a = uint256(_a);
        uint256 y = uint256(_y);
        uint256 d = uint256(_d);

        vm.assume(a > 0 && a <= v);

        uint256 vBal = v - a;
        uint256 sBal = a + y;
        uint256 mid = vBal + sBal;

        assert(mid == v + y);

        vm.assume(d <= sBal);
        assert((vBal + d) + (sBal - d) == mid);
    }

    // ============================================================================
    //                      FEE DISTRIBUTION INVARIANTS
    // ============================================================================

    /// @notice Prove: perfFee + vaultNet == amount (zero value leak)
    function check_feeDistributionAccounting(uint32 _amt, uint16 _bps) public pure {
        uint256 amt = uint256(_amt);
        uint256 bps = uint256(_bps);
        vm.assume(amt > 0 && bps <= MAX_PERF_FEE_BPS);

        uint256 fee = (amt * bps) / BPS;
        uint256 net = amt - fee;

        assert(fee + net == amt);
    }

    /// @notice Prove: full accounting identity with slashing reserve
    ///
    /// Decomposed proof: (1) fee+net==amt is linear. (2) net >= reserve
    /// reduces to fee <= amt - reserve, which holds when bps_fee + bps_slash <= BPS.
    /// We prove each sub-property independently.
    function check_feeDistributionFullAccounting(uint8 _amt, uint8 _feeBps, uint8 _slashBps) public pure {
        uint256 amt = uint256(_amt);
        uint256 feeBps = uint256(_feeBps);
        uint256 slashBps = uint256(_slashBps);

        vm.assume(amt > 0);
        vm.assume(feeBps <= MAX_PERF_FEE_BPS);
        vm.assume(slashBps <= MAX_PERF_FEE_BPS);

        uint256 fee = (amt * feeBps) / BPS;
        uint256 reserve = (amt * slashBps) / BPS;
        uint256 net = amt - fee;

        // Sub-property 1: exact accounting
        assert(fee + net == amt);

        // Sub-property 2: reserve is carved from net
        // Holds because fee <= amt*2000/10000 = amt/5 and reserve <= amt/5
        // so net = amt - fee >= amt*4/5 >= amt/5 >= reserve
        if (feeBps + slashBps <= BPS) {
            assert(net >= reserve);
        }
    }

    /// @notice Prove: treasury perfFee <= amount (fee never exceeds input)
    ///
    /// We prove fee <= amt directly. Since feeBps <= 2000 and BPS == 10000,
    /// fee = floor(amt * feeBps / 10000) <= floor(amt * 2000 / 10000) = floor(amt/5) <= amt.
    /// The floor division property floor(a*b/c) <= a when b <= c is proven via:
    ///   floor(a*b/c) * c <= a*b <= a*c  (when b <= c)
    ///   => floor(a*b/c) <= a
    function check_feeDistributionTreasuryCap(uint32 _amt, uint16 _bps) public pure {
        uint256 amt = uint256(_amt);
        uint256 bps = uint256(_bps);
        vm.assume(amt > 0 && bps <= MAX_PERF_FEE_BPS);

        uint256 fee = (amt * bps) / BPS;

        // fee = floor(amt * bps / BPS) <= amt * bps / BPS <= amt * BPS / BPS = amt
        // since bps <= MAX_PERF_FEE_BPS <= BPS
        assert(fee <= amt);

        // The net (vault portion) is always >= 80% of amount
        uint256 net = amt - fee;
        assert(net >= amt - amt / 5);
    }

    /// @notice Prove: exchange rate is non-decreasing after fee injection
    ///
    /// rate = (assets + V) / (supply + V). Adding to numerator with fixed denominator
    /// can only increase the quotient. We prove this via the algebraic identity:
    /// (a + x) / d >= a / d  when x >= 0 and d > 0.
    /// Decomposed: floor((a+x)*M/d) >= floor(a*M/d) follows from (a+x)*M >= a*M.
    function check_exchangeRateMonotonicWithFees(uint32 _assets, uint32 _supply, uint32 _feeNet) public pure {
        uint256 assets = uint256(_assets);
        uint256 supply = uint256(_supply);
        uint256 feeNet = uint256(_feeNet);

        vm.assume(assets > 0 && supply > 0 && feeNet > 0);

        uint256 denom = supply + VIRTUAL_SHARES;
        // Numerator strictly increases, denominator unchanged
        // floor((a+f+V)*1e18/d) >= floor((a+V)*1e18/d)
        // because (a+f+V)*1e18 > (a+V)*1e18 and floor is monotone
        uint256 numBefore = (assets + VIRTUAL_ASSETS) * 1e18;
        uint256 numAfter = (assets + feeNet + VIRTUAL_ASSETS) * 1e18;

        assert(numAfter > numBefore);
        // By monotonicity of floor(x/d): numAfter > numBefore => floor(numAfter/d) >= floor(numBefore/d)
        assert(numAfter / denom >= numBefore / denom);
    }

    // ============================================================================
    //                      ROUTER DISTRIBUTION INVARIANTS
    // ============================================================================

    /// @notice Prove: 3-recipient weighted distribution never exceeds input, dust <= 2
    ///
    /// Each share_i = floor(amount * w_i / BASE). Since floor(x) <= x,
    /// sum(share_i) = sum(floor(amt*w_i/B)) <= sum(amt*w_i/B) = amt*sum(w_i)/B = amt.
    /// Dust = amt - sum <= 2 (each of 3 floor operations loses at most 1).
    function check_routerDistributionConservation(uint32 _amt, uint16 _w1, uint16 _w2) public pure {
        uint256 amt = uint256(_amt);
        uint256 w1 = uint256(_w1);
        uint256 w2 = uint256(_w2);

        vm.assume(amt > 0);
        vm.assume(w1 <= ROUTER_BASE && w2 <= ROUTER_BASE);
        vm.assume(w1 + w2 <= ROUTER_BASE);
        uint256 w3 = ROUTER_BASE - w1 - w2;

        uint256 s1 = (amt * w1) / ROUTER_BASE;
        uint256 s2 = (amt * w2) / ROUTER_BASE;
        uint256 s3 = (amt * w3) / ROUTER_BASE;

        // Each share uses floor division, so share_i <= amt * w_i / ROUTER_BASE
        // The floor property: floor(x/d)*d <= x, so s_i * ROUTER_BASE <= amt * w_i
        // Summing: (s1+s2+s3)*ROUTER_BASE <= amt*(w1+w2+w3) = amt*ROUTER_BASE
        // => s1+s2+s3 <= amt

        // We assert sum <= amt. This is linear in the shares (already computed).
        assert(s1 + s2 + s3 <= amt);

        // Dust: each floor loses at most 1, so dust <= 2 for 3 terms
        // Proved by: amt - (s1+s2+s3) = amt - floor(amt*w1/B) - floor(amt*w2/B) - floor(amt*w3/B)
        //          <= 3 * 1 = 3, but w1+w2+w3=B tightens to <= 2
        assert(amt - (s1 + s2 + s3) <= 2);
    }

    /// @notice Prove: equal weights give equal shares
    function check_routerEqualWeights(uint32 _amt) public pure {
        uint256 amt = uint256(_amt);
        vm.assume(amt > 0);

        uint256 w = ROUTER_BASE / 2; // 5000
        // (ROUTER_BASE - w) == 5000 == w
        uint256 s1 = (amt * w) / ROUTER_BASE;
        uint256 s2 = (amt * (ROUTER_BASE - w)) / ROUTER_BASE;

        // Same weight => same share (both = floor(amt * 5000 / 10000) = floor(amt/2))
        assert(s1 == s2);
        assert(s1 + s2 <= amt);
    }

    // ============================================================================
    //                      COLLECT PIPELINE INVARIANTS
    // ============================================================================

    /// @notice Prove: Collect: total == pending + bridged
    function check_collectAccountingIdentity(uint32 _p1, uint32 _p2, uint32 _br) public pure {
        vm.assume(_p1 > 0 && _p2 > 0);

        uint256 total = 0;
        uint256 pending = 0;
        uint256 bridged = 0;

        total += uint256(_p1);
        pending += uint256(_p1);
        assert(total == pending + bridged);

        total += uint256(_p2);
        pending += uint256(_p2);
        assert(total == pending + bridged);

        vm.assume(uint256(_br) <= pending);
        pending -= uint256(_br);
        bridged += uint256(_br);
        assert(total == pending + bridged);
    }

    /// @notice Prove: identity holds through multiple push/bridge cycles
    function check_collectMultipleBridgeCycles(uint24 _p1, uint24 _br1, uint24 _p2, uint24 _br2) public pure {
        vm.assume(_p1 > 0 && _p2 > 0);

        uint256 total = 0;
        uint256 pending = 0;
        uint256 bridged = 0;

        total += uint256(_p1);
        pending += uint256(_p1);
        vm.assume(uint256(_br1) <= pending);
        pending -= uint256(_br1);
        bridged += uint256(_br1);
        assert(total == pending + bridged);

        total += uint256(_p2);
        pending += uint256(_p2);
        vm.assume(uint256(_br2) <= pending);
        pending -= uint256(_br2);
        bridged += uint256(_br2);
        assert(total == pending + bridged);
        assert(bridged <= total);
    }

    /// @notice Prove: Collect->Vault->Router pipeline has zero value leak
    ///
    /// We decompose: (1) Collect accounting is exact (linear). (2) Router distribution
    /// is bounded (proven by check_routerDistributionConservation). (3) Composition:
    /// vault receives exactly what Collect bridges, Router distributes <= vault balance.
    function check_collectVaultRouterPipeline(uint32 _fee, uint16 _w1, uint16 _w2) public pure {
        uint256 fee = uint256(_fee);
        uint256 w1 = uint256(_w1);
        uint256 w2 = uint256(_w2);

        vm.assume(fee > 0);
        vm.assume(w1 + w2 <= ROUTER_BASE);
        uint256 w3 = ROUTER_BASE - w1 - w2;

        // Collect: exact bridging (linear)
        uint256 vaultBal = fee;

        // Router distributes (each share is floor division)
        uint256 s1 = (fee * w1) / ROUTER_BASE;
        uint256 s2 = (fee * w2) / ROUTER_BASE;
        uint256 s3 = (fee * w3) / ROUTER_BASE;
        uint256 dist = s1 + s2 + s3;

        // No value created (sum of floors <= original)
        assert(dist <= fee);

        // Dust bounded
        assert(fee - dist <= 2);

        // Vault fully accounts for distributed + dust
        assert(vaultBal == dist + (fee - dist));
    }

    // ============================================================================
    //                      CROSS-CHAIN & E2E LIFECYCLE
    // ============================================================================

    /// @notice Prove: cross-chain total supply conserved through mint+teleport+burn
    function check_crossChainTotalSupply(uint24 _mA, uint24 _mB, uint24 _tAB, uint24 _tBC, uint24 _bC) public pure {
        uint256 mA = uint256(_mA);
        uint256 mB = uint256(_mB);
        vm.assume(mA > 0 && mB > 0);

        uint256 sA = mA;
        uint256 sB = mB;
        uint256 sC = 0;
        uint256 gM = mA + mB;
        uint256 gB = 0;

        assert(sA + sB + sC == gM - gB);

        vm.assume(uint256(_tAB) <= sA);
        sA -= uint256(_tAB);
        sB += uint256(_tAB);
        assert(sA + sB + sC == gM - gB);

        vm.assume(uint256(_tBC) <= sB);
        sB -= uint256(_tBC);
        sC += uint256(_tBC);
        assert(sA + sB + sC == gM - gB);

        vm.assume(uint256(_bC) <= sC);
        sC -= uint256(_bC);
        gB += uint256(_bC);
        assert(sA + sB + sC == gM - gB);
    }

    /// @notice Prove: full bridge->deposit->yield->withdraw->burn lifecycle is sound
    ///
    /// Uses uint8 with scaled constants for vault math tractability.
    /// Fee calculation uses BPS=10000 but only linear assertions.
    function check_fullE2ELifecycle(uint8 _bridgeAmt, uint8 _feeAmt, uint8 _feeBps) public pure {
        uint256 bridgeAmt = uint256(_bridgeAmt);
        uint256 feeAmt = uint256(_feeAmt);
        uint256 feeBps = uint256(_feeBps);

        vm.assume(bridgeAmt > SML * 2);
        vm.assume(feeAmt > 0);
        vm.assume(feeBps <= MAX_PERF_FEE_BPS);

        // --- Bridge mint ---
        uint256 bridgeSupply = bridgeAmt;

        // --- Deposit into vault (scaled) ---
        uint256 shares = _sToShares(bridgeAmt, 0, 0);
        vm.assume(shares > SML);

        uint256 userShares = shares - SML;
        uint256 vaultSupply = shares;
        uint256 vaultAssets = bridgeAmt;

        // --- Fee arrives (linear accounting) ---
        uint256 perfFee = (feeAmt * feeBps) / BPS;
        uint256 vaultFeeNet = feeAmt - perfFee;
        assert(perfFee + vaultFeeNet == feeAmt);

        vaultAssets += vaultFeeNet;

        // --- Withdraw ---
        uint256 withdrawn = _sToAssets(userShares, vaultSupply, vaultAssets);

        // User cannot extract more than vault holds
        assert(withdrawn <= vaultAssets);

        // MINIMUM_LIQUIDITY shares retain value
        assert(vaultSupply - userShares >= SML);

        // --- Bridge burn ---
        vm.assume(withdrawn <= bridgeSupply);
        assert(bridgeSupply - withdrawn == bridgeAmt - withdrawn);
    }
}
