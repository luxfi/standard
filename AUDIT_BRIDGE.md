# Lux Bridge Security Audit Report

**Auditor**: Trail of Bits-Level Independent Review
**Date**: 2025-01-30
**Scope**: `/contracts/bridge/` directory
**Severity Ratings**: Critical | High | Medium | Low | Informational

---

## Executive Summary

This audit covers the Lux Bridge smart contract system, including cross-chain token bridging, MPC oracle signature verification, vault management, and yield strategy integration. The codebase contains multiple bridge implementations with varying security postures.

**Overall Assessment**: The bridge system has several critical and high-severity vulnerabilities that require immediate attention before production deployment.

| Severity | Count |
|----------|-------|
| Critical | 4 |
| High | 8 |
| Medium | 12 |
| Low | 9 |
| Informational | 6 |

---

## Critical Findings

### C-01: XChainVault Burn Proof Verification is Effectively Disabled

**File**: `/contracts/bridge/XChainVault.sol` (Lines 304-312)

**Description**: The `_verifyBurnProof` function contains a critical vulnerability where burn proof verification is completely bypassed. The function returns `true` if any proof data is provided, regardless of content.

```solidity
function _verifyBurnProof(
    bytes32 vaultId,
    uint256 amount,
    bytes calldata proof
) private view returns (bool) {
    // Verify Warp message signature
    // This would call the Warp precompile to verify the BLS signature
    // For now, simplified verification
    return proof.length > 0;  // CRITICAL: No actual verification!
}
```

**Impact**: An attacker can drain all vaulted tokens by providing any non-empty bytes as proof. Total loss of funds.

**Recommendation**: Implement proper Warp precompile verification:
```solidity
function _verifyBurnProof(...) private view returns (bool) {
    (IWarp.WarpMessage memory message, bool valid) =
        IWarp(WARP_PRECOMPILE).getVerifiedWarpMessage(0);
    if (!valid) return false;
    // Decode and verify message content matches expected burn
    return _validateBurnMessage(message, vaultId, amount);
}
```

---

### C-02: ecrecover Without Zero Address Check

**Files**:
- `/contracts/bridge/Bridge.sol` (Lines 319-328, legacy)
- `/contracts/bridge/Teleport.sol` (Lines 271-273)

**Description**: The `recoverSigner` function uses raw `ecrecover` without checking for the zero address return value. When signature recovery fails, `ecrecover` returns `address(0)` rather than reverting.

```solidity
function recoverSigner(bytes32 message_, bytes memory sig_) internal pure returns (address) {
    (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig_);
    return ecrecover(message_, v, r, s);  // May return address(0)
}
```

**Impact**: If `MPCOracleAddrMap[address(0)]` is ever set (intentionally or through upgrade mishap), arbitrary minting becomes possible. Additionally, malformed signatures could cause unexpected behavior.

**Recommendation**:
```solidity
address signer = ecrecover(message_, v, r, s);
require(signer != address(0), "Invalid signature");
return signer;
```

---

### C-03: Chain ID Not Validated in Teleporter Message Signatures

**File**: `/contracts/bridge/teleport/Teleporter.sol` (Lines 228-234)

**Description**: The `mintDeposit` function's message hash does not include the destination chain ID (Lux chain), only the source chain ID. This allows cross-chain replay attacks.

```solidity
bytes32 messageHash = keccak256(abi.encodePacked(
    "DEPOSIT",
    srcChainId,        // Source chain
    depositNonce,
    recipient,
    amount
    // MISSING: block.chainid (destination chain)
));
```

**Impact**: A valid signature for minting on one Lux fork/testnet can be replayed on another chain with the same contract address and nonce state.

**Recommendation**: Include destination chain ID in message hash:
```solidity
bytes32 messageHash = keccak256(abi.encodePacked(
    "DEPOSIT",
    srcChainId,
    block.chainid,     // Destination chain
    depositNonce,
    recipient,
    amount
));
```

---

### C-04: Withdraw Nonce Predictability Enables Front-Running

**File**: `/contracts/bridge/teleport/Teleporter.sol` (Lines 318-325)

**Description**: The `burnForWithdraw` function generates withdraw nonces using predictable on-chain values:

```solidity
withdrawNonce = uint256(keccak256(abi.encodePacked(
    block.timestamp,
    msg.sender,
    amount,
    srcChainId,
    block.number
)));
```

**Impact**: An attacker can predict the nonce before transaction confirmation, potentially enabling:
1. Front-running to claim the withdrawal on the source chain before the legitimate user
2. Denial of service by pre-processing the nonce

**Recommendation**: Use a monotonically increasing counter:
```solidity
withdrawNonce = ++_withdrawNonceCounter;
```

---

## High Severity Findings

### H-01: Missing Reentrancy Protection in Legacy Bridge Contract

**File**: `/contracts/bridge/Teleport.sol` (Lines 197-246)

**Description**: The `bridgeMintStealth` function lacks reentrancy protection despite minting tokens (which could trigger callbacks via hooks in some token implementations).

```solidity
function bridgeMintStealth(...) public returns (address) {  // No nonReentrant
    // ... validation ...
    varStruct.token.mint(payoutAddr, feeAmount);     // External call
    varStruct.token.mint(varStruct.toTargetAddr, netAmount);  // External call
    addMappingStealth(signedTXInfo);  // State update AFTER external calls
    // ...
}
```

**Impact**: If the token implements ERC777 or has receive hooks, a malicious actor could reenter and potentially double-mint.

**Recommendation**: Add `nonReentrant` modifier and follow checks-effects-interactions pattern.

---

### H-02: TeleportProposalBridge Allows Message Execution After Expiry

**File**: `/contracts/bridge/TeleportProposalBridge.sol` (Lines 405-422)

**Description**: The `executeMessage` function marks expired messages as executed before reverting:

```solidity
if (block.timestamp > message.timestamp + MESSAGE_EXPIRY) {
    message.executed = true; // Mark as executed (expired)
    emit MessageExpired(messageId);
    revert MessageExpiredError();
}
```

**Impact**: While the transaction reverts, the state change persists if this is called via a try/catch block, permanently blocking legitimate re-execution attempts.

**Recommendation**: Do not modify state before reverting:
```solidity
if (block.timestamp > message.timestamp + MESSAGE_EXPIRY) {
    revert MessageExpiredError();
}
```

---

### H-03: Unbounded MPC Oracle Set

**Files**:
- `/contracts/bridge/Bridge.sol` (Lines 115-118)
- `/contracts/bridge/teleport/Teleporter.sol` (Lines 404-416)

**Description**: MPC oracles can be added without bound and cannot be fully revoked (mapping entries persist as `false` rather than being deleted). There's also no mechanism to enumerate or audit current oracles.

```solidity
function setMPCOracle(address MPCO_) public onlyAdmin {
    addMPCMapping(MPCO_);  // Only sets to true, no way to enumerate or remove
}
```

**Impact**:
1. Stale or compromised oracle addresses may remain in mappings
2. No audit trail of oracle changes
3. Potential for validator collusion attacks if too many oracles are added

**Recommendation**: Implement bounded oracle set with enumeration:
```solidity
address[] public oracleList;
uint256 public constant MAX_ORACLES = 10;
mapping(address => uint256) public oracleIndex;

function addOracle(address oracle) external onlyAdmin {
    require(oracleList.length < MAX_ORACLES, "Max oracles");
    require(!mpcOracles[oracle], "Already oracle");
    oracleIndex[oracle] = oracleList.length;
    oracleList.push(oracle);
    mpcOracles[oracle] = true;
}
```

---

### H-04: ETHVault Withdrawal Allowance Bypass

**File**: `/contracts/bridge/ETHVault.sol` (Lines 47-61)

**Description**: The withdrawal function has a typo in the error message and potentially allows withdrawal without sufficient allowance due to ordering:

```solidity
function withdraw(uint256 amount_, address receiver_, address owner_) external {
    require(amount_ <= address(this).balance, "Insufficient balance");
    if (msg.sender != owner_) {
        uint256 allowed = allowance(owner_, msg.sender);
        require(allowed >= amount_, "Invalid alowance");  // Typo, but functional
    }
    _burn(owner_, amount_);  // Burns shares
    (bool success, ) = payable(receiver_).call{value: amount_}("");
```

**Impact**: The allowance is checked but not decremented for non-owner withdrawals, enabling unlimited withdrawals once any allowance is granted.

**Recommendation**: Decrement allowance for non-owner:
```solidity
if (msg.sender != owner_) {
    _spendAllowance(owner_, msg.sender, amount_);
}
```

---

### H-05: LiquidVault Strategy Manipulation via Timestamp

**File**: `/contracts/bridge/teleport/LiquidVault.sol` (Lines 187-214)

**Description**: Strategy allocation and deallocation signatures include `block.timestamp`:

```solidity
bytes32 messageHash = keccak256(abi.encodePacked(
    "ALLOCATE",
    strategyIndex,
    amount,
    block.timestamp  // Timestamp dependency
));
```

**Impact**: MPC oracle must sign messages with exact timestamp matching. This creates a race condition where valid signatures become invalid after the block containing them is mined. Miners can also manipulate timestamps within bounds.

**Recommendation**: Use nonce-based signatures instead of timestamps:
```solidity
bytes32 messageHash = keccak256(abi.encodePacked(
    "ALLOCATE",
    strategyIndex,
    amount,
    allocationNonce++
));
```

---

### H-06: YieldBridgeVault Missing Access Control on Harvest

**File**: `/contracts/bridge/yield/YieldBridgeVault.sol` (Lines 216-236)

**Description**: The `harvestYield` function is publicly callable without access control:

```solidity
function harvestYield(address asset) external assetSupported(asset) returns (uint256 totalYield) {
    // No access control modifier
```

**Impact**: Anyone can trigger harvests, potentially:
1. Front-running yield distribution for MEV extraction
2. Griefing by triggering unnecessary gas expenditure
3. Timing manipulation for arbitrage

**Recommendation**: Add access control or keeper pattern:
```solidity
function harvestYield(address asset) external onlyKeeper assetSupported(asset) {...}
```

---

### H-07: Stale Backing Attestation Bypass

**File**: `/contracts/bridge/teleport/Teleporter.sol` (Lines 484-499)

**Description**: The `_checkBackingRatio` function silently bypasses backing verification when attestation is stale:

```solidity
if (block.timestamp - attestation.timestamp > 24 hours) {
    // Stale attestation, allow minting but log warning
    // In production, might want stricter enforcement
    return;  // SILENTLY ALLOWS UNBACKED MINTING
}
```

**Impact**: If MPC fails to update backing attestation for >24 hours, unlimited unbacked tokens can be minted, breaking the core invariant `totalMinted <= totalBackingOnSourceChain`.

**Recommendation**: Revert on stale attestation in production:
```solidity
if (block.timestamp - attestation.timestamp > 24 hours) {
    revert StaleBackingAttestation();
}
```

---

### H-08: LiquidETH Yield Index Integer Overflow

**File**: `/contracts/bridge/teleport/LiquidETH.sol` (Lines 303-314)

**Description**: The yield index calculation can overflow in edge cases:

```solidity
uint256 yieldPerDebt = amount * 1e18 / totalDebt;
yieldIndex += yieldPerDebt;  // Can overflow if many small yields accumulate
```

**Impact**: If `yieldIndex` overflows, all user debt calculations become incorrect, potentially allowing debt escape or incorrect liquidations.

**Recommendation**: Use checked math with upper bound:
```solidity
require(yieldIndex + yieldPerDebt >= yieldIndex, "Yield index overflow");
require(yieldIndex + yieldPerDebt < type(uint128).max, "Yield index too large");
```

---

## Medium Severity Findings

### M-01: Signature Malleability Not Prevented

**Files**: All contracts using raw ECDSA

**Description**: The signature splitting functions don't enforce low-S values, enabling signature malleability (two valid signatures for same message).

```solidity
function splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
    // No check for s <= secp256k1n/2
}
```

**Impact**: While replay protection uses the full signature as key (mitigating direct replay), malleability can cause issues with off-chain systems expecting unique signatures.

**Recommendation**: Use OpenZeppelin's ECDSA library which enforces low-S.

---

### M-02: Bridge.sol Fee Rate Unbounded

**File**: `/contracts/bridge/Bridge.sol` (Lines 26, 87-93)

**Description**: Fee rate can be set to any value without upper bound:

```solidity
uint256 public feeRate = 100; // 1%
// ...
function setpayoutAddressess(address payoutAddress_, uint256 feeRate_) public onlyAdmin {
    payoutAddress = payoutAddress_;
    feeRate = feeRate_;  // No upper bound check
}
```

**Impact**: Admin can set 100% fee, effectively stealing all bridge transfers.

**Recommendation**: Add maximum fee cap:
```solidity
require(feeRate_ <= 1000, "Fee exceeds 10%");  // Max 10%
```

---

### M-03: Missing Zero Address Validation

**Files**: Multiple contracts

**Locations**:
- `Bridge.sol:setpayoutAddressess` - payoutAddress
- `BridgeVault.sol:_addNewERC20Vault` - asset validation only checks not zero for vault
- `XChainVault.sol:releaseFromVault` - recipient

**Impact**: Setting critical addresses to zero can lock funds or cause reverts.

---

### M-04: TeleportBridge.sol Missing Chain ID in Claim ID

**File**: `/contracts/bridge/teleport/TeleportBridge.sol` (Lines 213-224)

**Description**: The claim ID calculation doesn't include `block.chainid`:

```solidity
claimId = keccak256(abi.encode(
    claim.burnTxHash,
    claim.logIndex,
    claim.token,
    claim.amount,
    claim.toChainId,
    // Missing: block.chainid
    // ...
));
```

**Impact**: Same claim ID on different chains with same bridge deployment could cause confusion in monitoring/accounting systems.

---

### M-05: BridgeVault Approve Max Pattern Risk

**File**: `/contracts/bridge/BridgeVault.sol` (Lines 85)

**Description**: Infinite approval to newly created vaults:

```solidity
IERC20(asset_).approve(newVaultAddress, type(uint256).max);
```

**Impact**: If vault contract is compromised, infinite tokens can be drained.

**Recommendation**: Use incremental approvals or approve only needed amounts.

---

### M-06: Teleporter Peg Check Uses Hardcoded Value

**File**: `/contracts/bridge/teleport/Teleporter.sol` (Lines 449-453)

**Description**: `getCurrentPeg()` returns hardcoded BASIS_POINTS:

```solidity
function getCurrentPeg() public view returns (uint256) {
    // In a real implementation, this would query a DEX oracle
    // For now, we assume 1:1 peg
    return BASIS_POINTS;  // Always returns 10000
}
```

**Impact**: Peg protection is ineffective. Bridge continues operating during de-peg events.

---

### M-07: LiquidVault Strategy Array Not Bounded on Iteration

**File**: `/contracts/bridge/teleport/LiquidVault.sol` (Lines 262-267)

**Description**: Harvest iterates all strategies without gas limit consideration:

```solidity
for (uint256 i = 0; i < strategies.length; i++) {
    if (strategies[i].active) {
        IYieldStrategy(strategies[i].adapter).harvest();
```

**Impact**: With MAX_STRATEGIES=10, if each harvest is gas-intensive, function could exceed block gas limit.

---

### M-08: ProposalBridge pendingMessageIds Array Grows Unbounded

**File**: `/contracts/bridge/TeleportProposalBridge.sol` (Lines 118, 378-380)

**Description**: Messages are added to `pendingMessageIds` but never removed:

```solidity
bytes32[] public pendingMessageIds;
// ...
pendingMessageIds.push(messageId);  // Only grows
```

**Impact**: Over time, view functions iterating this array will exceed gas limits.

---

### M-09: Missing Events for Critical State Changes

**Files**: Multiple

**Locations**:
- `Bridge.sol:setWithdrawalEnabled` - no event
- `ETHVault.sol` - no event for allowance changes
- `LiquidVault.sol:setBufferBps` - has event but could be front-run

---

### M-10: Teleporter mintYield Missing Backing Check

**File**: `/contracts/bridge/teleport/Teleporter.sol` (Lines 260-293)

**Description**: `mintYield` doesn't call `_checkBackingRatio`:

```solidity
function mintYield(...) external nonReentrant whenNotPaused {
    // No checkPeg modifier
    // No _checkBackingRatio call
```

**Impact**: Yield minting could violate backing invariant during stress conditions.

---

### M-11: LRC20B Burns From Arbitrary Accounts

**File**: `/contracts/bridge/LRC20B.sol` (Lines 82-89)

**Description**: Admin can burn from any account without approval:

```solidity
function bridgeBurn(address account, uint256 amount) public onlyAdmin returns (bool) {
    _burn(account, amount);  // No approval check
```

**Impact**: While intended for bridge operations, this is a centralization risk. Admin can burn user tokens arbitrarily.

---

### M-12: YieldBridgeVault Strategy Weight Validation

**File**: `/contracts/bridge/yield/YieldBridgeVault.sol` (Lines 327-348)

**Description**: Strategy weights aren't validated to sum to 100%:

```solidity
require(targetWeight <= BASIS_POINTS, "YieldBridgeVault: invalid weight");
// No check that sum of all weights == BASIS_POINTS
```

**Impact**: Under-allocated funds remain idle, over-allocated causes revert on rebalance.

---

## Low Severity Findings

### L-01: Floating Pragma

All contracts use `^0.8.31` or similar. Pin to exact version for reproducible builds.

### L-02: Missing NatSpec Documentation

Many functions lack @param and @return documentation.

### L-03: Unused Imports

`Bridge.sol` imports Strings twice (line 14, 17).

### L-04: Magic Numbers

Fee calculations use raw numbers like `10 ** 4`, `10 ** 18`. Define named constants.

### L-05: Inconsistent Naming

- `setpayoutAddressess` (typo, should be `setPayoutAddresses`)
- Mixed camelCase and snake_case in parameters

### L-06: Shadow Variables

`TeleportVault.withdrawNonce` shadows state with parameter `_withdrawNonce`.

### L-07: State Variables Visibility

`withdrawalEnabled` in Bridge.sol lacks explicit visibility (defaults to internal).

### L-08: Missing Return Value Check

ERC20 transfers in legacy Bridge.sol don't use SafeERC20:
```solidity
IERC20(tokenAddr_).transferFrom(msg.sender, address(vault), amount_);
```

### L-09: Gas Inefficient Storage Reads

Multiple storage reads in loops without caching in memory.

---

## Informational Findings

### I-01: Consider Using EIP-712 Typed Signatures Everywhere

TeleportBridge.sol uses EIP-712 properly. Extend this to all signature verification for better UX and replay protection.

### I-02: Centralization Risks

- Single admin can pause all operations
- MPC oracle set controlled by admin
- Fee rates controlled by admin

Consider timelock and multi-sig for admin functions.

### I-03: Lack of Emergency Functions

No circuit breaker for individual functions. Consider granular pause controls.

### I-04: Missing Getter Functions

- No way to enumerate all MPC oracles
- No way to get all pending messages efficiently

### I-05: Upgrade Path Not Defined

Contracts are not upgradeable. Plan migration path for critical fixes.

### I-06: Test Coverage Unknown

No test files visible in scope. Recommend >95% coverage for bridge contracts.

---

## Validator Collusion Analysis

The MPC-based bridge architecture relies on threshold signatures from validators. Analysis:

### Attack Vectors

1. **Colluding Majority**: If threshold validators collude, they can mint arbitrary tokens or sign fraudulent messages.

2. **Key Compromise**: Single validator key compromise allows signing share, combined with social engineering of others.

3. **Slashing Absent**: No economic penalty for malicious signing.

### Mitigations Observed

- Threshold requirement in TeleportProposalBridge
- Role-based access control
- Nonce-based replay protection

### Recommendations

1. Implement validator bond/slash mechanism
2. Add time delays for large value transfers
3. Implement fraud proof system
4. Consider optimistic rollup pattern for additional security layer

---

## Double-Spend Scenario Analysis

### Identified Vectors

1. **Cross-Chain Race Condition**: Burn on Lux + claim on source chain. If source chain release is faster than burn finality, double-spend possible.

2. **Reorg Vulnerability**: Deep reorg on source chain after Lux mint could result in double-spend.

3. **Nonce Prediction**: Predictable withdraw nonces (Teleporter) enable front-running.

### Mitigations Required

1. Wait for sufficient block confirmations before minting
2. Implement challenge period for withdrawals
3. Use monotonic counters instead of hash-based nonces

---

## Recommendations Summary

### Immediate Actions (Before Mainnet)

1. Fix XChainVault burn proof verification (C-01)
2. Add ecrecover zero address check (C-02)
3. Include destination chain ID in all signatures (C-03)
4. Replace predictable nonces with counters (C-04)
5. Add reentrancy guards to all state-modifying functions (H-01)
6. Fix ETHVault allowance handling (H-04)
7. Remove stale attestation bypass (H-07)

### Short-Term (Next Release)

1. Implement bounded oracle management (H-03)
2. Add fee rate caps (M-02)
3. Implement proper peg oracle (M-06)
4. Add comprehensive events (M-09)

### Long-Term

1. Add economic security (validator staking/slashing)
2. Implement fraud proofs
3. Consider upgradeability pattern
4. Add formal verification for core invariants

---

## Files Reviewed

| File | Lines | Critical | High | Medium | Low |
|------|-------|----------|------|--------|-----|
| Bridge.sol | 582 | 1 | 1 | 2 | 3 |
| Teleport.sol | 284 | 1 | 1 | 1 | 1 |
| Teleporter.sol | 521 | 2 | 2 | 2 | 1 |
| TeleportBridge.sol | 384 | 0 | 0 | 1 | 0 |
| BridgeVault.sol | 221 | 0 | 0 | 1 | 0 |
| XChainVault.sol | 358 | 1 | 0 | 0 | 0 |
| TeleportVault.sol | 300 | 0 | 0 | 0 | 1 |
| LiquidVault.sol | 432 | 0 | 2 | 1 | 1 |
| ETHVault.sol | 62 | 0 | 1 | 0 | 0 |
| LRC20B.sol | 97 | 0 | 0 | 1 | 0 |
| LiquidETH.sol | 571 | 0 | 1 | 0 | 1 |
| YieldBridgeVault.sol | 556 | 0 | 1 | 1 | 0 |
| TeleportProposalBridge.sol | 586 | 0 | 1 | 2 | 1 |

---

**Audit Completed**: 2025-01-30
**Next Review Recommended**: After all critical/high issues addressed
