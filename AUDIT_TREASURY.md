# Treasury Contracts Security Audit

**Audit Date:** 2026-01-30
**Auditor:** Trail of Bits-level security review
**Scope:** /contracts/treasury/ (10 contracts)
**Solidity Version:** ^0.8.31

---

## Executive Summary

This audit identifies **6 Critical**, **8 High**, **12 Medium**, and **9 Low** severity findings across the treasury contract suite. The most severe issues involve missing access control, oracle manipulation vectors, and potential fund loss through rounding errors.

| Severity | Count | Fixed | Acknowledged |
|----------|-------|-------|--------------|
| Critical | 6     | -     | -            |
| High     | 8     | -     | -            |
| Medium   | 12    | -     | -            |
| Low      | 9     | -     | -            |
| Info     | 5     | -     | -            |

---

## Critical Findings

### [C-01] CollateralRegistry.recordBond() lacks access control - Arbitrary bond inflation

**File:** CollateralRegistry.sol:266-278
**Severity:** Critical
**Impact:** Fund Loss

```solidity
function recordBond(address token, uint256 amount) external {
    // Note: Should add access control for only authorized bond contracts
    CollateralConfig storage config = collaterals[token];
    if (!config.whitelisted) revert NotWhitelisted(token);
    // ...
    config.totalBonded += amount;
}
```

**Description:** The `recordBond()` function has no access control. Any address can call it to artificially inflate `totalBonded`, potentially exhausting capacity limits and blocking legitimate bonds.

**Attack Vector:**
1. Attacker calls `recordBond(token, maxCapacity)` repeatedly
2. `totalBonded` reaches `maxCapacity`
3. Legitimate users cannot bond (CapacityExceeded revert)
4. DoS on bonding mechanism

**Recommendation:** Add access control modifier:
```solidity
mapping(address => bool) public authorizedBonders;

function recordBond(address token, uint256 amount) external {
    require(authorizedBonders[msg.sender], "Unauthorized");
    // ...
}
```

---

### [C-02] Vault.init() one-time setup has no access control - Permanent router hijack

**File:** Vault.sol:87-92
**Severity:** Critical
**Impact:** Fund Loss (permanent)

```solidity
function init(address _router) external {
    if (router != address(0)) revert Invalid();
    if (_router == address(0)) revert Zero();
    router = _router;
}
```

**Description:** The `init()` function can be called by anyone before the legitimate owner sets the router. An attacker can front-run deployment and set a malicious router address.

**Attack Vector:**
1. Monitor mempool for Vault deployment
2. Front-run to call `init(attackerControlledRouter)`
3. All `flush()` and `flushAll()` operations now require attacker's approval
4. Attacker can permanently block fee distribution

**Recommendation:** Restrict to deployer or use constructor initialization:
```solidity
constructor(address _token, address _router) {
    token = IERC20(_token);
    router = _router;
}
```

---

### [C-03] LiquidBond oracle manipulation via stale price - Arbitrage attack

**File:** LiquidBond.sol:362-388
**Severity:** Critical
**Impact:** Fund Loss

```solidity
function _getValueInSats(address token, uint256 amount) internal view returns (uint256) {
    // ...
    (, int256 tokenPrice,,,) = IPriceFeed(config.priceFeed).latestRoundData();
    // No staleness check on updatedAt
    (, int256 btcPrice,,,) = IPriceFeed(btcPriceFeed).latestRoundData();
    // No staleness check
}
```

**Description:** The oracle price fetching ignores `updatedAt` timestamp. Stale prices enable arbitrage attacks.

**Attack Vector:**
1. Oracle stops updating (network congestion, oracle failure)
2. Real price moves significantly
3. Attacker bonds at favorable stale rate
4. Claims ASHA at discount far exceeding intended parameters

**Recommendation:** Add staleness checks:
```solidity
uint256 public constant MAX_PRICE_STALENESS = 1 hours;

(, int256 tokenPrice,, uint256 updatedAt,) = IPriceFeed(config.priceFeed).latestRoundData();
if (block.timestamp - updatedAt > MAX_PRICE_STALENESS) revert StalePrice();
```

---

### [C-04] ProtocolLiquidity LP valuation vulnerable to manipulation

**File:** ProtocolLiquidity.sol:463-480
**Severity:** Critical
**Impact:** Fund Loss

```solidity
function _getLPValue(address lpToken, uint256 lpAmount) internal view returns (uint256) {
    (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
    uint256 totalSupply = pool.totalSupply();

    uint256 price0 = oracle.getPrice(pool.token0());
    uint256 price1 = oracle.getPrice(pool.token1());

    uint256 value0 = uint256(reserve0) * price0 / 1e18;
    uint256 value1 = uint256(reserve1) * price1 / 1e18;
    uint256 totalPoolValue = value0 + value1;

    return (totalPoolValue * lpAmount) / totalSupply;
}
```

**Description:** LP token valuation using spot reserves is manipulable via flash loans. Attacker can inflate reserves, bond LP, and extract value.

**Attack Vector:**
1. Flash loan large amounts of both tokens
2. Add liquidity to inflate reserves
3. Call `bondLP()` at inflated LP valuation
4. Receive excessive ASHA
5. Remove liquidity and repay flash loan
6. Profit from arbitrage

**Recommendation:** Use TWAP oracles or fair LP pricing:
```solidity
// Fair LP price = 2 * sqrt(reserve0 * reserve1) * sqrt(price0 * price1) / totalSupply
function _getLPValueFair(address lpToken, uint256 lpAmount) internal view returns (uint256) {
    (uint112 r0, uint112 r1,) = ILiquidityPool(lpToken).getReserves();
    uint256 sqrtK = Math.sqrt(uint256(r0) * uint256(r1));
    uint256 p0 = oracle.getPrice(pool.token0());
    uint256 p1 = oracle.getPrice(pool.token1());
    uint256 sqrtP = Math.sqrt(p0 * p1);
    return (2 * sqrtK * sqrtP * lpAmount) / (pool.totalSupply() * 1e18);
}
```

---

### [C-05] Recall.sol executeRecall uses safeTransferFrom incorrectly

**File:** Recall.sol:175
**Severity:** Critical
**Impact:** Fund Loss / DoS

```solidity
function executeRecall(uint256 recallId) external onlyParent {
    // ...
    IERC20(request.token).safeTransferFrom(childSafe, parentSafe, request.amount);
}
```

**Description:** `safeTransferFrom()` requires prior approval from `childSafe` to `Recall` contract. If approval is not set, all recalls will fail permanently.

**Attack Vector:**
1. Child DAO does not approve Recall contract
2. Parent initiates recall
3. Grace period passes
4. `executeRecall()` reverts on missing approval
5. Funds remain locked (DoS on recall mechanism)

**Recommendation:** The comment mentions this requires Safe module integration. Either:
1. Document clearly that Recall must be a Safe module
2. Use different transfer pattern (pull from Safe via module exec)

---

### [C-06] ValidatorVault reward distribution precision loss

**File:** ValidatorVault.sol:134-148
**Severity:** Critical
**Impact:** Fund Loss (dust accumulation)

```solidity
function _distributeRewards(uint256 amount) internal {
    if (amount == 0 || totalDelegated == 0) return;

    uint256 toReserve = (amount * slashingReserveBps) / BPS;
    slashingReserve += toReserve;

    uint256 toDistribute = amount - toReserve;

    // Precision loss: if toDistribute < totalDelegated, this rounds to 0
    accRewardPerShare += (toDistribute * 1e18) / totalDelegated;
}
```

**Description:** When `toDistribute * 1e18 < totalDelegated`, the division rounds to zero. Small reward amounts become permanently stuck.

**Attack Vector:**
1. Delegator stakes very large amount (e.g., 1e30)
2. Small rewards (< 1e12) contribute 0 to accRewardPerShare
3. These funds remain in contract, never distributed
4. Over time, significant dust accumulation

**Recommendation:** Track undistributed dust:
```solidity
uint256 public undistributedRewards;

function _distributeRewards(uint256 amount) internal {
    // ...
    uint256 distributedPerShare = (toDistribute * 1e18) / totalDelegated;
    uint256 actualDistributed = (distributedPerShare * totalDelegated) / 1e18;
    undistributedRewards += toDistribute - actualDistributed;
    accRewardPerShare += distributedPerShare;
}
```

---

## High Findings

### [H-01] Bond.sol token calculation can overflow with extreme parameters

**File:** Bond.sol:142
**Severity:** High
**Impact:** Incorrect token allocation

```solidity
uint256 tokensOwed = (amount * bond.tokensToMint * (10000 + bond.discount)) / (bond.targetRaise * 10000);
```

**Description:** With large `amount`, `tokensToMint`, and `discount`, the multiplication can exceed uint256.

**PoC:**
- amount = 1e24 (1M tokens with 18 decimals)
- tokensToMint = 1e26
- discount = 9000 (90%)
- Multiplication: 1e24 * 1e26 * 19000 = 1.9e54 (overflow)

**Recommendation:** Use intermediate calculations or mulDiv:
```solidity
uint256 discountMultiplier = 10000 + bond.discount;
uint256 tokensOwed = (amount * discountMultiplier).mulDiv(bond.tokensToMint, bond.targetRaise * 10000);
```

---

### [H-02] LiquidBond._swapCollateral approves without checking existing approval

**File:** LiquidBond.sol:401-414
**Severity:** High
**Impact:** Approval race condition

```solidity
function _swapCollateral(...) internal returns (address, uint256) {
    // ...
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenIn).approve(router, amountIn);  // Does not reset to 0 first
    // ...
}
```

**Description:** Some tokens (USDT) require approval to be set to 0 before changing. This can cause swap to revert.

**Recommendation:** Use `forceApprove` or reset:
```solidity
IERC20(tokenIn).forceApprove(router, amountIn);
// After swap:
IERC20(tokenIn).forceApprove(router, 0);
```

---

### [H-03] Router weight changes during pending distribution cause fund mismatch

**File:** Router.sol:78-90, 122-145
**Severity:** High
**Impact:** Incorrect distribution

```solidity
function set(address recipient, uint256 _weight) external onlyOwner {
    // Can change weight anytime
    weight[recipient] = _weight;
}

function distribute(bytes32[] calldata chains) external returns (uint256 amount) {
    // Uses current weights
    uint256 share = (amount * w) / BASE;
    owed[recipient] += share;
}
```

**Description:** If weights are changed between `distribute()` calls, the total distributed may not equal the total received due to rounding with different weight distributions.

**Attack Vector:**
1. Funds flush, waiting to distribute
2. Governance changes weights mid-epoch
3. Some funds distributed at old weights, some at new
4. Total `owed` does not match actual balance

**Recommendation:** Checkpoint weights per distribution cycle or require weights sum validation before distribution.

---

### [H-04] Router.setBatch does not remove old recipients

**File:** Router.sol:95-115
**Severity:** High
**Impact:** Incorrect weight distribution

```solidity
function setBatch(address[] calldata recipients, uint256[] calldata weightValues) external onlyOwner {
    // Only validates new recipients sum to 10000
    // Old recipients in list still have non-zero weights
}
```

**Description:** `setBatch` requires weights sum to BASE but does not zero out previous recipients. Old recipients retain their weights.

**Recommendation:** Zero all weights before setting new ones:
```solidity
function setBatch(...) external onlyOwner {
    // Zero existing weights
    for (uint256 i = 0; i < list.length; i++) {
        weight[list[i]] = 0;
    }
    // Set new weights
    // ...
}
```

---

### [H-05] Collect.sol sync() lacks Warp verification - Fake settings injection

**File:** Collect.sol:70-80
**Severity:** High
**Impact:** Arbitrary fee rate manipulation

```solidity
function sync(uint16 _rate, uint32 _version) external {
    // TODO: Verify Warp proof from C-Chain FeeGov
    // WarpLib.verifyFrom(cchain, abi.encode(_rate, _version));

    if (_version <= version) revert Stale();
    rate = _rate;
}
```

**Description:** The TODO indicates Warp verification is not implemented. Anyone can call `sync()` with arbitrary rates.

**Attack Vector:**
1. Attacker calls `sync(0, currentVersion + 1)`
2. Fee rate set to 0%
3. Protocol loses all fee revenue

**Recommendation:** Implement Warp verification before deployment or add temporary access control.

---

### [H-06] ValidatorVault.forwardRewardsToLiquidLUX is permissionless

**File:** ValidatorVault.sol:157-180
**Severity:** High
**Impact:** Timing manipulation

```solidity
function forwardRewardsToLiquidLUX() external nonReentrant {
    // Anyone can call
}
```

**Description:** Permissionless forwarding allows MEV bots to front-run reward accumulation, potentially affecting LiquidLUX share pricing.

**Attack Vector:**
1. Large reward deposit incoming
2. Attacker front-runs with `forwardRewardsToLiquidLUX()` at bad timing
3. Manipulates LiquidLUX reward distribution timing

**Recommendation:** Add keeper role or minimum accumulation threshold:
```solidity
uint256 public minForwardAmount = 1e18;

function forwardRewardsToLiquidLUX() external nonReentrant {
    uint256 forwardable = ...;
    require(forwardable >= minForwardAmount, "Below minimum");
}
```

---

### [H-07] Bond.sol AlreadyPurchased prevents legitimate second purchases

**File:** Bond.sol:138
**Severity:** High
**Impact:** Functionality limitation

```solidity
if (purchases[bondId][msg.sender].paymentAmount > 0) revert AlreadyPurchased();
```

**Description:** Users cannot purchase additional bonds in the same offering, even if under maxPurchase limit.

**Recommendation:** Allow multiple purchases up to maxPurchase:
```solidity
uint256 totalPurchased = purchases[bondId][msg.sender].paymentAmount + amount;
if (totalPurchased > bond.maxPurchase) revert AmountTooHigh();
```

---

### [H-08] LiquidBond epoch limit bypass via contract deployment

**File:** LiquidBond.sol:267-271
**Severity:** High
**Impact:** Rate limit bypass

```solidity
uint256 userEpochTotal = userEpochBonds[currentEpoch][msg.sender] + collateralValueSats;
if (userEpochTotal > maxBondPerAddress) {
    revert ExceedsMaxBond(userEpochTotal, maxBondPerAddress);
}
```

**Description:** Sybil attack via multiple addresses or contracts bypasses per-address limits.

**Recommendation:** This is a known limitation. Consider:
- Whitelist-only bonding
- KYC integration
- Time-weighted bonding limits

---

## Medium Findings

### [M-01] Bond.sol getActiveBonds() unbounded loop - DoS

**File:** Bond.sol:227-240
**Severity:** Medium
**Impact:** DoS on view functions

```solidity
function getActiveBonds() external view returns (uint256[] memory ids) {
    for (uint256 i = 0; i < nextBondId; i++) {
        if (bonds[i].active) count++;
    }
    // Second loop
    for (uint256 i = 0; i < nextBondId; i++) {
        if (bonds[i].active) {
            ids[j++] = i;
        }
    }
}
```

**Description:** Two unbounded loops over all bonds. Gas cost grows linearly with total bonds ever created.

**Recommendation:** Maintain active bond list separately or paginate.

---

### [M-02] Recall balance tracking desync from actual Safe balance

**File:** Recall.sol:101-128
**Severity:** Medium
**Impact:** Accounting mismatch

**Description:** `allocatedBalance` and `bondedBalance` are manually updated via `recordFunding()` and `recordSpending()`. If the Safe executes transactions not through this interface, balances desync.

**Recommendation:** Consider reading actual token balance or implementing as Safe Guard module.

---

### [M-03] FeeGov version overflow after ~4B updates

**File:** FeeGov.sol:69
**Severity:** Medium
**Impact:** Staleness check bypass

```solidity
unchecked { version++; }
```

**Description:** uint32 overflows after 4,294,967,295 updates. After overflow, new versions appear "stale."

**Recommendation:** Use uint64 or add overflow check.

---

### [M-04] ProtocolLiquidity position index collision

**File:** ProtocolLiquidity.sol:282, 321
**Severity:** Medium
**Impact:** Position management confusion

```solidity
positionId = userPositionCount[msg.sender]++;
```

**Description:** Position IDs increment globally per user across LP and single-sided deposits. This is not inherently wrong but may cause confusion.

**Recommendation:** Use separate counters or encode position type in ID.

---

### [M-05] Vault.receive_ permissionless relay without Warp verification

**File:** Vault.sol:65-82
**Severity:** Medium
**Impact:** Fake fee inflation (with token requirement)

```solidity
function receive_(bytes32 chain, uint256 amount, bytes32 warpId) external {
    // TODO: Verify Warp proof via precompile
    token.safeTransferFrom(msg.sender, address(this), amount);
}
```

**Description:** While requiring actual tokens mitigates fake inflation, accounting per chain can be manipulated without Warp verification.

**Recommendation:** Implement Warp verification.

---

### [M-06] ValidatorVault slash() incomplete implementation

**File:** ValidatorVault.sol:378-382
**Severity:** Medium
**Impact:** Slashing non-functional

```solidity
function slash(bytes32 validatorId, uint256 amount) external onlyOwner {
    require(amount <= slashingReserve, "Insufficient reserve");
    slashingReserve -= amount;
    // Slashing logic - redistribute to affected delegators
}
```

**Description:** Slashing deducts from reserve but does not redistribute to affected delegators as commented.

**Recommendation:** Implement full slashing logic or remove function.

---

### [M-07] LiquidBond.claimAll unbounded loop

**File:** LiquidBond.sol:333-350
**Severity:** Medium
**Impact:** DoS for users with many purchases

```solidity
function claimAll() external nonReentrant {
    for (uint256 i = 0; i < purchases.length; i++) {
        // ...
    }
}
```

**Description:** Users with many purchases may hit gas limits.

**Recommendation:** Add pagination or limit claims per tx.

---

### [M-08] Router distribute() rounding loss

**File:** Router.sol:137
**Severity:** Medium
**Impact:** Dust accumulation

```solidity
uint256 share = (amount * w) / BASE;
```

**Description:** Division truncation leaves dust in router. Over time, this accumulates.

**Recommendation:** Track and redistribute dust:
```solidity
uint256 distributed;
for (...) {
    uint256 share = (amount * w) / BASE;
    owed[recipient] += share;
    distributed += share;
}
uint256 dust = amount - distributed;
// Add dust to highest weight recipient or reserve
```

---

### [M-09] CollateralRegistry tier discount can exceed 100%

**File:** CollateralRegistry.sol:104-107, 301
**Severity:** Medium
**Impact:** Excessive discounts

```solidity
tierBaseDiscount[RiskTier.TIER_1] = 2500;  // 25%
// Plus discountBonus with no cap

function getDiscount(address token) external view returns (uint256) {
    return tierBaseDiscount[config.tier] + config.discountBonus;
}
```

**Description:** Total discount (tierBase + bonus) can exceed 10000 BPS (100%), resulting in undefined behavior in bond calculations.

**Recommendation:** Cap total discount:
```solidity
function getDiscount(address token) external view returns (uint256) {
    uint256 total = tierBaseDiscount[config.tier] + config.discountBonus;
    return total > MAX_TOTAL_DISCOUNT ? MAX_TOTAL_DISCOUNT : total;
}
```

---

### [M-10] Bond.sol no mechanism to recover unminted tokens

**File:** Bond.sol
**Severity:** Medium
**Impact:** Stuck value

**Description:** If `IMintable(identityToken).mint()` reverts (e.g., max supply reached), users cannot claim tokens. No recovery mechanism exists.

**Recommendation:** Add emergency claim mechanism or pre-validate mintability.

---

### [M-11] ProtocolLiquidity oracle address(0) check missing in constructor

**File:** ProtocolLiquidity.sol:150-159
**Severity:** Medium
**Impact:** Deployment failure mode

```solidity
constructor(...) {
    oracle = IPriceOracle(oracle_);  // No zero check
}
```

**Recommendation:** Add validation:
```solidity
require(oracle_ != address(0), "Invalid oracle");
```

---

### [M-12] ValidatorVault commission can be changed after delegation

**File:** ValidatorVault.sol:232-245
**Severity:** Medium
**Impact:** Unexpected fee changes

```solidity
function updateValidator(bytes32 validatorId, uint256 commissionBps, bool active) external onlyOwner {
    v.commissionBps = commissionBps;  // Applies to existing delegators
}
```

**Description:** Commission changes affect existing delegators retroactively.

**Recommendation:** Apply commission changes only to new delegations or with time delay.

---

## Low Findings

### [L-01] Missing zero-address checks in constructors

**Files:** Multiple contracts
**Severity:** Low

Bond.sol, LiquidBond.sol, Vault.sol constructors accept addresses without validation.

---

### [L-02] Events emitted before state changes

**File:** Bond.sol:159, ValidatorVault.sol:268
**Severity:** Low

Events should be emitted after all state changes for consistency.

---

### [L-03] Magic numbers without constants

**File:** Multiple
**Severity:** Low

Values like `10000`, `1e18` should be named constants.

---

### [L-04] Lack of two-step ownership transfer

**Files:** All Ownable contracts
**Severity:** Low

Single-step ownership transfer risks losing control if wrong address specified.

---

### [L-05] FeeGov list never shrinks

**File:** FeeGov.sol:89-93
**Severity:** Low

`remove()` sets `chains[id] = false` but does not remove from `list[]`. Gas cost increases over time.

---

### [L-06] ValidatorVault delegations array never shrinks efficiently

**File:** ValidatorVault.sol:298-300
**Severity:** Low

Swap-and-pop changes array order, potentially confusing off-chain indexers.

---

### [L-07] Missing natspec on public functions

**Files:** Multiple
**Severity:** Low

Many public functions lack documentation.

---

### [L-08] Inconsistent error naming conventions

**Files:** Multiple
**Severity:** Low

Some errors are single words (`Zero`, `Invalid`), others are descriptive (`BondNotActive`).

---

### [L-09] No event for LiquidBond epoch advancement

**File:** LiquidBond.sol:435-441
**Severity:** Low

Event exists but is only emitted on manual advancement, not automatic.

---

## Informational

### [I-01] TODO comments in production code

**Files:** Vault.sol:69-70, Collect.sol:71-72, FeeGov.sol:104

TODO comments indicate incomplete Warp verification. Remove or implement before mainnet.

---

### [I-02] Unused imports

Multiple files import but do not use all symbols.

---

### [I-03] Consider using custom errors throughout

Some contracts mix `require()` strings with custom errors.

---

### [I-04] Gas optimization: use `unchecked` for safe increments

Multiple loops use checked arithmetic for iterator increment.

---

### [I-05] Consider EIP-712 for off-chain signatures

For future features requiring signatures, implement EIP-712.

---

## Recommendations Summary

1. **Immediate (pre-deployment):**
   - Implement Warp verification in Vault, Collect, FeeGov
   - Add access control to CollateralRegistry.recordBond()
   - Fix Vault.init() access control
   - Add oracle staleness checks in LiquidBond
   - Fix LP valuation in ProtocolLiquidity (use fair pricing)

2. **High Priority:**
   - Review Recall.sol transfer mechanism (Safe module integration)
   - Add precision loss tracking in ValidatorVault
   - Fix Router weight management

3. **Medium Priority:**
   - Add pagination to unbounded loops
   - Implement complete slashing logic
   - Add dust recovery mechanisms

4. **Best Practices:**
   - Two-step ownership transfers
   - Comprehensive natspec documentation
   - Remove TODO comments
   - Consistent error naming

---

## Appendix: Attack Scenarios

### Scenario A: Bond Protocol Drain via Oracle Manipulation

1. Attacker identifies stale oracle price
2. Real ETH price: $3000, Oracle price: $2000 (stale)
3. Attacker bonds 100 ETH at $2000 valuation
4. Receives ASHA worth $200,000 + discount
5. Real value contributed: $300,000
6. Loss to protocol: $100,000+ per bond

### Scenario B: LP Valuation Attack

1. Flash loan 10M USDC and 3000 ETH
2. Add liquidity to ASHA/ETH pool (massive reserve increase)
3. Bond LP at inflated valuation
4. Remove liquidity
5. Repay flash loan
6. Net profit: difference in ASHA received vs fair value

### Scenario C: Router Privilege Escalation

1. Monitor for Vault deployment
2. Front-run init() with attacker-controlled router
3. Attacker can now:
   - Block all fee distribution (DoS)
   - Redirect fees via malicious weight setting

---

**End of Audit Report**
