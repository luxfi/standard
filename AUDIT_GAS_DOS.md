# Gas Optimization and DoS Attack Vector Audit

## Executive Summary

This audit analyzes the Lux Standard contracts for gas optimization opportunities and Denial of Service (DoS) attack vectors. Several critical and high-severity issues were identified, primarily involving unbounded loops that iterate over user-controlled array sizes.

**Risk Summary:**
- Critical: 4 issues
- High: 5 issues
- Medium: 8 issues
- Low/Informational: 6 issues

---

## Critical Severity

### C-01: Unbounded Loop in `Bond.getActiveBonds()`

**File:** `/contracts/treasury/Bond.sol` (Lines 227-240)

**Description:**
The `getActiveBonds()` function iterates twice over all bonds ever created, without any bounds:

```solidity
function getActiveBonds() external view returns (uint256[] memory ids) {
    uint256 count = 0;
    for (uint256 i = 0; i < nextBondId; i++) {      // First loop
        if (bonds[i].active) count++;
    }

    ids = new uint256[](count);
    uint256 j = 0;
    for (uint256 i = 0; i < nextBondId; i++) {      // Second loop
        if (bonds[i].active) {
            ids[j++] = i;
        }
    }
}
```

**Attack Vector:**
- An attacker with owner privileges (or compromised owner) can create thousands of bonds
- Even if bonds are closed, they remain in storage and must be iterated
- Each iteration performs an SLOAD (~2100 gas cold, ~100 gas warm)
- With 1000 bonds: ~2.1M gas minimum, potentially exceeding block gas limit

**Impact:** Complete DoS of view function; any off-chain integrations relying on this function will fail

**Recommendation:**
- Maintain a separate array of active bond IDs
- Implement pagination: `getActiveBonds(uint256 offset, uint256 limit)`
- Use an EnumerableSet for active bonds

---

### C-02: Unbounded Loop in `ProtocolLiquidity.claimAll()`

**File:** `/contracts/treasury/ProtocolLiquidity.sol` (Lines 360-376)

**Description:**
```solidity
function claimAll() external nonReentrant {
    uint256 total = 0;
    uint256 count = userPositionCount[msg.sender];

    for (uint256 i = 0; i < count; i++) {           // Unbounded loop
        VestingPosition storage pos = positions[msg.sender][i];
        uint256 claimable = _claimable(pos);
        if (claimable > 0) {
            pos.claimed += claimable;               // SSTORE per position
            total += claimable;
            emit Claimed(msg.sender, i, claimable); // Event per position
        }
    }
    // ...
}
```

**Attack Vector:**
- User creates many small positions via `bondLP()` or `depositSingleSided()`
- Each iteration: ~5000 gas (SLOAD) + ~20000 gas (SSTORE if claimable) + ~2000 gas (event)
- 200 positions = ~5.4M gas, exceeding most block gas limits
- User's funds become permanently locked as `claimAll()` always fails

**Impact:** Permanent fund lockup for affected users

**Recommendation:**
- Implement batch claiming with pagination: `claimBatch(uint256[] calldata positionIds)`
- Add maximum positions per user limit
- Allow individual position claims (already exists via `claim(positionId)`)

---

### C-03: Unbounded Loop in `LiquidBond.claimAll()`

**File:** `/contracts/treasury/LiquidBond.sol` (Lines 333-350)

**Description:**
Identical vulnerability pattern to C-02:

```solidity
function claimAll() external nonReentrant {
    Purchase[] storage purchases = userPurchases[msg.sender];
    uint256 totalClaimable = 0;

    for (uint256 i = 0; i < purchases.length; i++) {  // Unbounded
        uint256 claimable = _claimable(purchases[i]);
        if (claimable > 0) {
            purchases[i].ashaClaimed += claimable;     // SSTORE
            totalClaimable += claimable;
            emit Claimed(msg.sender, i, claimable);
        }
    }
    // ...
}
```

**Attack Vector:** Same as C-02

**Impact:** Permanent fund lockup

**Recommendation:** Same as C-02

---

### C-04: Unbounded Loop in `LiquidBond.getClaimable()`

**File:** `/contracts/treasury/LiquidBond.sol` (Lines 520-529)

**Description:**
```solidity
function getClaimable(address user) external view returns (uint256) {
    Purchase[] storage purchases = userPurchases[user];
    uint256 total = 0;

    for (uint256 i = 0; i < purchases.length; i++) {
        total += _claimable(purchases[i]);
    }
    return total;
}
```

**Impact:** DoS of view function for users with many positions

---

## High Severity

### H-01: Unbounded Loop in `GaugeController.updateWeights()`

**File:** `/contracts/governance/GaugeController.sol` (Lines 230-257)

**Description:**
```solidity
function updateWeights() external {
    require(block.timestamp >= lastWeightUpdate + WEEK, "Too soon");

    uint256 newTotalWeight = 0;

    for (uint256 i = 1; i < gauges.length; i++) {      // Unbounded
        int256 delta = pendingWeightChanges[i];
        if (delta != 0) {
            // ... update logic with multiple SSTOREs
        }
        newTotalWeight += gaugeWeights[i];
    }
    // ...
}
```

**Attack Vector:**
- Admin creates many gauges over time
- With 500+ gauges, `updateWeights()` may exceed gas limit
- Weekly weight updates become impossible, breaking governance

**Impact:** Governance mechanism failure

**Recommendation:**
- Implement batch updates: `updateWeights(uint256 startIdx, uint256 endIdx)`
- Limit maximum gauges or use lazy evaluation

---

### H-02: Unbounded Loop in `GaugeController.getAllWeights()`

**File:** `/contracts/governance/GaugeController.sol` (Lines 278-285)

```solidity
function getAllWeights() external view returns (uint256[] memory weights) {
    weights = new uint256[](gauges.length);
    for (uint256 i = 0; i < gauges.length; i++) {
        if (totalWeight > 0) {
            weights[i] = (gaugeWeights[i] * BPS) / totalWeight;
        }
    }
}
```

**Impact:** DoS of view function

---

### H-03: Unbounded Loop in `GaugeController.voteMultiple()`

**File:** `/contracts/governance/GaugeController.sol` (Lines 195-227)

**Description:**
```solidity
function voteMultiple(
    uint256[] calldata gaugeIds_,
    uint256[] calldata weights
) external nonReentrant {
    require(gaugeIds_.length == weights.length, "Length mismatch");
    // ...
    for (uint256 i = 0; i < gaugeIds_.length; i++) {
        // Multiple SSTOREs per iteration
    }
}
```

**Attack Vector:**
- Malicious caller passes extremely large arrays
- Transaction fails with out-of-gas
- No explicit limit on array length

**Impact:** Gas griefing, potential DoS

**Recommendation:** Add maximum array length check

---

### H-04: Unbounded Loop in `ProtocolLiquidity.totalClaimable()`

**File:** `/contracts/treasury/ProtocolLiquidity.sol` (Lines 392-397)

```solidity
function totalClaimable(address user) external view returns (uint256 total) {
    uint256 count = userPositionCount[user];
    for (uint256 i = 0; i < count; i++) {
        total += _claimable(positions[user][i]);
    }
}
```

**Impact:** DoS of view function for users with many positions

---

### H-05: Unbounded Loop in `ProtocolLiquidity.getStats()`

**File:** `/contracts/treasury/ProtocolLiquidity.sol` (Lines 422-437)

```solidity
function getStats() external view returns (...) {
    // ...
    for (uint256 i = 0; i < nextPoolId; i++) {
        if (pools[i].active) activePools++;
    }
    for (uint256 i = 0; i < nextSingleSidedId; i++) {
        if (singleSided[i].active) activeSingleSided++;
    }
}
```

**Impact:** DoS of view function as pools grow

---

## Medium Severity

### M-01: Unbounded Loop in `GenesisNFTs.luxLockedForAddress()`

**File:** `/contracts/nft/GenesisNFTs.sol` (Lines 520-526)

```solidity
function luxLockedForAddress(address holder) external view returns (uint256 total) {
    uint256 balance = balanceOf(holder);
    for (uint256 i = 0; i < balance; i++) {
        uint256 tokenId = tokenOfOwnerByIndex(holder, i);  // Gas-heavy enumeration
        total += tokenMeta[tokenId].luxLocked;
    }
}
```

**Impact:** DoS for whale addresses with many NFTs

---

### M-02: Unbounded Loop in `GenesisNFTs.migrateTokens()`

**File:** `/contracts/nft/GenesisNFTs.sol` (Lines 347-383)

```solidity
function migrateTokens(
    address[] calldata holders,
    // ... many arrays
) external onlyRole(MINTER_ROLE) {
    // ...
    for (uint256 i = 0; i < len; i++) {
        _migrateToken(...);  // Heavy operation with multiple SSTOREs
    }
}
```

**Impact:** Migration may fail if batch is too large

**Recommendation:** Add explicit batch size limit (e.g., 50 tokens per tx)

---

### M-03: Unbounded Loop in `Streams.createStreamBatch()`

**File:** `/contracts/streaming/Streams.sol` (Lines 184-191)

```solidity
function createStreamBatch(
    CreateParams[] calldata params
) external nonReentrant whenNotPaused returns (uint256[] memory streamIds) {
    streamIds = new uint256[](params.length);
    for (uint256 i = 0; i < params.length; i++) {
        streamIds[i] = _createStream(params[i]);  // Token transfer + NFT mint
    }
}
```

**Impact:** Transaction failure for large batches

**Recommendation:** Limit batch size to 20-50 streams

---

### M-04: Unbounded Loop in `Streams.withdrawBatch()`

**File:** `/contracts/streaming/Streams.sol` (Lines 283-307)

Similar pattern - no limit on `streamIds.length`

---

### M-05: Unbounded Loop in `BatchSender.send()`

**File:** `/contracts/perps/peripherals/BatchSender.sol` (Lines 42-50)

```solidity
function _send(
    IERC20 _token,
    address[] memory _accounts,
    uint256[] memory _amounts,
    uint256 _typeId
) private {
    for (uint256 i = 0; i < _accounts.length; i++) {
        _token.transferFrom(msg.sender, _accounts[i], _amounts[i]);
    }
}
```

**Impact:** Transaction failure for large batches; no explicit limit

---

### M-06: Unbounded Loop in `RewardRouter.batchStakeLPXForAccount()`

**File:** `/contracts/perps/staking/RewardRouter.sol` (Lines 133-138)

```solidity
function batchStakeLPXForAccount(
    address[] memory _accounts,
    uint256[] memory _amounts
) external nonReentrant onlyGov {
    for (uint256 i = 0; i < _accounts.length; i++) {
        _stakeLPX(msg.sender, _accounts[i], _lpx, _amounts[i]);
    }
}
```

**Impact:** Transaction failure for large batches

---

### M-07: Unbounded Loop in `RewardRouter.batchCompoundForAccounts()`

**File:** `/contracts/perps/staking/RewardRouter.sol` (Lines 307-311)

```solidity
function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
    for (uint256 i = 0; i < _accounts.length; i++) {
        _compound(_accounts[i]);  // Multiple external calls per iteration
    }
}
```

**Impact:** Transaction failure for large batches

---

### M-08: Unbounded Loop in `DIDRegistry._isController()`

**File:** `/contracts/identity/DIDRegistry.sol` (Lines 516-526)

```solidity
function _isController(bytes32 didHash, address account) internal view returns (bool) {
    DIDDocument storage doc = _documents[didHash];

    if (doc.controller == account) return true;

    for (uint256 i = 0; i < doc.additionalControllers.length; i++) {
        if (doc.additionalControllers[i] == account) return true;
    }

    return false;
}
```

**Mitigating Factor:** Bounded by `MAX_VERIFICATION_METHODS = 20`
**Impact:** Low - acceptable with current bounds

---

## Low / Informational

### L-01: Newton's Method Iteration in StableSwap

**Files:** `/contracts/amm/StableSwap.sol` (Lines 655-674, 708-720)

The `_getD()` and `_getY()` functions iterate up to 255 times for convergence. While bounded, this is gas-heavy (~50-100k gas per call).

**Recommendation:** Consider caching D value when balances haven't changed

---

### L-02: Storage vs Memory Inefficiency in Multiple Functions

**Examples:**
- `Bond.sol` Line 130: `BondConfig storage bond = bonds[bondId]` - good
- `ProtocolLiquidity.sol` Line 265: `PoolConfig storage pool = pools[poolId]` - good

Most contracts correctly use `storage` for frequently accessed structs.

---

### L-03: Multiple SLOADs in DAO.execute()

**File:** `/contracts/governance/DAO.sol` (Lines 230-253)

```solidity
function execute(uint256 proposalId) external payable nonReentrant {
    // ...
    for (uint256 i = 0; i < proposal.targets.length; i++) {
        proposal.targets[i]    // SLOAD
        proposal.values[i]     // SLOAD
        proposal.calldatas[i]  // SLOAD
    }
}
```

**Recommendation:** Cache array lengths and consider caching arrays to memory for small proposals

---

### L-04: Event Emission in Loops

Multiple contracts emit events inside loops, adding ~2000 gas per emission:
- `ProtocolLiquidity.claimAll()` - Line 370
- `LiquidBond.claimAll()` - Line 342
- `GaugeController.voteMultiple()` - Line 222

**Recommendation:** Emit single summary event after loop completion

---

### L-05: Redundant Active Check in Bond.getActiveBonds()

Both loops check `bonds[i].active`, causing double SLOAD for each bond.

---

### L-06: Missing Batch Size Constants

No contracts define explicit `MAX_BATCH_SIZE` constants.

**Recommendation:** Add constants like:
```solidity
uint256 public constant MAX_BATCH_SIZE = 50;
```

---

## State Bloat Attack Vectors

### SB-01: Unlimited Position Creation

**Files:** `ProtocolLiquidity.sol`, `LiquidBond.sol`

Users can create unlimited vesting positions with minimum amounts. Each position consumes storage slots:
- `VestingPosition`: 4 slots (~80,000 gas to write)
- `Purchase`: 7 slots (~140,000 gas to write)

**Attack Cost:** With small minimum bonds, attacker can bloat state cheaply.

**Recommendation:**
- Enforce meaningful minimum deposit amounts
- Limit positions per user
- Consider position consolidation mechanism

---

### SB-02: Unlimited Bond/Pool Creation (Admin)

**Files:** `Bond.sol`, `ProtocolLiquidity.sol`

Compromised admin can create unlimited bonds/pools, bloating state and making iteration-based functions fail.

**Recommendation:** Add maximum limits for total bonds/pools

---

## Gas Optimization Opportunities

### GO-01: Pack Struct Fields

**File:** `Bond.sol` - `BondConfig` struct

```solidity
struct BondConfig {
    address paymentToken;      // 20 bytes
    uint256 targetRaise;       // 32 bytes - could be uint128
    uint256 tokensToMint;      // 32 bytes - could be uint128
    uint256 discount;          // 32 bytes - could be uint16 (basis points)
    uint256 vestingPeriod;     // 32 bytes - could be uint32 (seconds)
    uint256 startTime;         // 32 bytes - could be uint40
    uint256 endTime;           // 32 bytes - could be uint40
    uint256 minPurchase;       // 32 bytes - could be uint128
    uint256 maxPurchase;       // 32 bytes - could be uint128
    bool active;               // 1 byte
}
```

**Current:** 9 storage slots
**Optimized:** Could fit in 4-5 slots with proper packing

---

### GO-02: Use Unchecked Math Where Safe

**Example:** Loop counters with known bounds:
```solidity
for (uint256 i = 0; i < length;) {
    // ...
    unchecked { ++i; }
}
```

Saves ~50 gas per iteration.

---

### GO-03: Cache Array Lengths

```solidity
// Before
for (uint256 i = 0; i < tokens.length; i++) { ... }

// After
uint256 len = tokens.length;
for (uint256 i = 0; i < len; i++) { ... }
```

Saves ~3 gas per iteration.

---

## Recommendations Summary

### Immediate (Critical):
1. Add pagination to all `get*` view functions
2. Implement `claimBatch(uint256[] positionIds)` pattern
3. Add maximum limits to user positions

### Short-term (High):
1. Add `MAX_BATCH_SIZE` constants to all batch functions
2. Implement lazy weight calculation in GaugeController
3. Add explicit array length validation

### Medium-term:
1. Optimize struct packing for storage efficiency
2. Use unchecked math in bounded loops
3. Consider EnumerableSet for active items
4. Emit summary events instead of per-item events

### Architecture:
1. Consider off-chain indexing for complex queries
2. Implement pull-over-push patterns where applicable
3. Add circuit breakers for gas-heavy operations

---

## Appendix: Affected Functions by Contract

| Contract | Function | Severity | Issue |
|----------|----------|----------|-------|
| Bond | getActiveBonds() | Critical | Unbounded double loop |
| ProtocolLiquidity | claimAll() | Critical | Unbounded loop, state writes |
| ProtocolLiquidity | totalClaimable() | High | Unbounded loop |
| ProtocolLiquidity | getStats() | High | Double unbounded loop |
| LiquidBond | claimAll() | Critical | Unbounded loop, state writes |
| LiquidBond | getClaimable() | Critical | Unbounded loop |
| GaugeController | updateWeights() | High | Unbounded loop, state writes |
| GaugeController | getAllWeights() | High | Unbounded loop |
| GaugeController | voteMultiple() | High | No batch limit |
| GenesisNFTs | luxLockedForAddress() | Medium | Unbounded loop |
| GenesisNFTs | migrateTokens() | Medium | No batch limit |
| Streams | createStreamBatch() | Medium | No batch limit |
| Streams | withdrawBatch() | Medium | No batch limit |
| BatchSender | send() | Medium | No batch limit |
| RewardRouter | batchStakeLPXForAccount() | Medium | No batch limit |
| RewardRouter | batchCompoundForAccounts() | Medium | No batch limit |
| DIDRegistry | _isController() | Low | Bounded by MAX constant |
| StableSwap | _getD(), _getY() | Low | 255 iteration Newton's method |

---

*Audit completed: 2025-01-30*
*Auditor: AI Security Analysis*
*Scope: Gas optimization and DoS vectors in /contracts/*
