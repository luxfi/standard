# Cryptographic Operations Audit Report

**Repository:** `/Users/z/work/lux/standard/contracts/`
**Date:** 2026-01-30
**Auditor:** Automated Security Analysis

---

## Executive Summary

This audit examines all cryptographic operations across the Lux Standard contracts. The codebase implements a diverse set of cryptographic schemes including ECDSA, FROST Schnorr signatures, Lamport signatures, EIP-712 typed data, and Merkle proofs. While most implementations follow best practices, several findings require attention.

**Severity Summary:**
- CRITICAL: 2
- HIGH: 4
- MEDIUM: 6
- LOW: 8
- INFORMATIONAL: 5

---

## 1. Signature Verification (ecrecover)

### 1.1 Files Using ecrecover

| File | Line | Context |
|------|------|---------|
| `bridge/Teleport.sol` | 273 | MPC oracle signature verification |
| `bridge/Bridge.sol` | 327 | MPC oracle signature verification |
| `governance/DAO.sol` | 323 | Vote by signature |
| `safe/FROST.sol` | 15-26 | Schnorr signature via ecrecover trick |

### 1.2 Findings

#### CRITICAL: Missing Signature Malleability Protection in Bridge Contracts

**Files:** `bridge/Teleport.sol`, `bridge/Bridge.sol`

**Issue:** Both contracts use raw `ecrecover` without checking the `s` value is in the lower half of the curve order. ECDSA signatures are malleable: for any valid signature `(r, s, v)`, the signature `(r, n - s, v')` is also valid for the same message.

```solidity
// bridge/Teleport.sol:271-273
function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
    (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig);
    return ecrecover(message, v, r, s);  // No malleability check
}
```

**Impact:** An attacker could submit a malleable signature variant to bypass replay protection if the signature bytes themselves are used as the replay key (which they are in `transactionMap[signedTXInfo]`).

**Recommendation:** Use OpenZeppelin's `ECDSA.recover()` which enforces `s <= secp256k1n/2`, or add explicit check:
```solidity
require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0);
```

#### HIGH: No Zero Address Check After ecrecover

**Files:** `bridge/Teleport.sol`, `bridge/Bridge.sol`

**Issue:** `ecrecover` returns `address(0)` on invalid signatures rather than reverting. The bridge contracts do check the recovered address against `MPCOracleAddrMap`, but this relies on `address(0)` not being in the oracle map. An explicit check should be added.

```solidity
// bridge/Bridge.sol:445-451
address signer = recoverSigner(
    prefixed(keccak256(abi.encodePacked(message))),
    signedTXInfo_
);
// Missing: require(signer != address(0), "Invalid signature");
require(MPCOracleAddrMap[signer].exists, "Unauthorized Signature");
```

**Recommendation:** Add explicit zero address check immediately after recovery.

#### LOW: DAO.sol Uses Raw ecrecover (Acceptable)

**File:** `governance/DAO.sol:323`

The DAO contract uses `ecrecover` directly but the context is acceptable because:
1. The signature is used to identify the voter, not for replay protection
2. Invalid signatures (returning `address(0)`) are caught by subsequent `require(signer != address(0))`

---

## 2. Hash Functions (keccak256)

### 2.1 Hash Collision Risks

#### MEDIUM: abi.encodePacked with Multiple Dynamic Types

**Multiple Files**

Using `abi.encodePacked` with multiple dynamic-length arguments can lead to hash collisions:

```solidity
// bridge/Teleport.sol:183
return string(abi.encodePacked(amt, toTargetAddrStr, txid, tokenAddrStrHash, chainIdStr, vault));
```

**Example Collision:**
- `encodePacked("a", "bc")` = `encodePacked("ab", "c")` = `"abc"`

**Affected Locations:**
- `bridge/Teleport.sol:183` - Message construction
- `bridge/Bridge.sol:276-284` - Message construction
- `privacy/BulletproofVerifier.sol:166-167` - Challenge computation
- `account/Account.sol:206` - Session key message hash

**Recommendation:** Use `abi.encode` instead of `abi.encodePacked` for all security-critical hashing, or ensure at least one fixed-length element separates dynamic elements.

#### LOW: Proper Usage Patterns Observed

Several contracts correctly use `abi.encode` for EIP-712 structured data:
- `governance/DAO.sol:305-320` - Domain separator and struct hash
- `governance/Council.sol:224-243` - Transaction hashing
- `tokens/LRC20/extensions/LRC20Permit.sol:60-61` - Permit hash
- `router/IntentRouter.sol:444-459` - Order hash

---

## 3. Nonce Management

### 3.1 Files with Nonce Management

| File | Nonce Type | Implementation |
|------|------------|----------------|
| `account/Account.sol` | Session nonce | Incremented after use |
| `tokens/LRC20/extensions/LRC20Permit.sol` | EIP-2612 nonce | OpenZeppelin Nonces |
| `fhe/governance/ConfidentialLRC20Votes.sol` | Delegation nonce | Custom mapping |
| `router/IntentRouter.sol` | Order nonce | Invalidation mapping |
| `safe/SafeThresholdLamportModule.sol` | Lamport nonce | Incremented after use |
| `bridge/teleport/TeleportBridge.sol` | Burn nonce | Sequential counter |

### 3.2 Findings

#### HIGH: Nonce Not Validated Before Use in Account.sol

**File:** `account/Account.sol:206`

```solidity
function executeWithSession(...) external returns (bytes memory) {
    bytes32 hash = keccak256(abi.encodePacked(target, value, data, nonce));
    // ... signature verification ...
    nonce++;  // Nonce incremented AFTER use
}
```

**Issue:** The nonce is included in the hash but there's no validation that the signature was created with the current nonce. An attacker could potentially replay old signatures if the same `(target, value, data)` tuple recurs.

**Recommendation:** Include explicit nonce validation or use a nonce mapping per signer.

#### MEDIUM: Potential Nonce Desync in ConfidentialLRC20Votes

**File:** `fhe/governance/ConfidentialLRC20Votes.sol:137-139`

```solidity
if (nonce != nonces[delegator]++) {
    revert SignatureNonceInvalid();
}
```

**Issue:** The nonce is incremented even when the signature verification fails (due to the `++` operator in the condition). If `SignatureChecker.isValidSignatureNow` fails first (line 134), the nonce is not affected, but the order of checks could lead to inconsistent state if reordered.

**Recommendation:** Separate nonce validation from nonce increment for clarity.

#### LOW: Good Practice - TeleportBridge Nonce Management

**File:** `bridge/teleport/TeleportBridge.sol:156`

```solidity
uint256 currentNonce = burnNonce++;
```

Good pattern: sequential nonce incremented atomically, included in canonical burn ID computation.

---

## 4. Randomness Sources

### 4.1 Analysis of block.timestamp/block.number Usage

#### MEDIUM: block.timestamp Used in Pool ID Generation

**File:** `mocks/MockZChainAMM.sol:36`

```solidity
poolId = keccak256(abi.encodePacked(assetA, assetB, block.timestamp));
```

**Issue:** Using `block.timestamp` for generating identifiers allows miners/validators to influence the outcome. This is a mock contract, but the pattern should not be used in production.

#### MEDIUM: Potential Time-Based Manipulation in Oracle Staleness

**File:** `precompile/interfaces/IOracle.sol:299`

```solidity
require(block.timestamp - p.timestamp <= maxAge, "Oracle: stale price");
```

**Issue:** Price staleness checks rely on `block.timestamp` which can be manipulated by validators within bounds (~15 seconds on Ethereum). For high-value transactions, this tolerance may be exploitable.

**Recommendation:** Consider using multiple oracle sources or implementing TWAP for price-sensitive operations.

---

## 5. EIP-712 Typed Data Signing

### 5.1 Implementation Review

| Contract | Domain Separator | Findings |
|----------|------------------|----------|
| `governance/DAO.sol` | Dynamic construction | Computed per-call (gas inefficient but correct) |
| `governance/Council.sol` | DOMAIN_SEPARATOR_TYPEHASH | Correctly typed |
| `tokens/LRC20/extensions/LRC20Permit.sol` | OpenZeppelin EIP712 | Best practice implementation |
| `router/IntentRouter.sol` | OpenZeppelin EIP712 | Best practice implementation |
| `bridge/teleport/TeleportBridge.sol` | OpenZeppelin EIP712 | Best practice implementation |
| `fhe/access/PermissionedV2.sol` | Modified EIP712 | Intentionally omits verifyingContract |
| `account/Account.sol` | Defined but unused | DOMAIN_TYPEHASH defined but EIP-712 not fully implemented |

### 5.2 Findings

#### HIGH: DAO.sol Domain Separator Lacks Version

**File:** `governance/DAO.sol:305-311`

```solidity
bytes32 domainSeparator = keccak256(
    abi.encode(
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
        keccak256(bytes("LuxDAO")),
        block.chainid,
        address(this)
    )
);
```

**Issue:** The domain separator is missing the `version` field that is standard in EIP-712. While functional, this deviates from the standard and may cause compatibility issues with signing libraries.

**Recommendation:** Add version field:
```solidity
keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
```

#### LOW: Domain Separator Not Cached in DAO.sol

**File:** `governance/DAO.sol`

The domain separator is recomputed on every `castVoteBySig` call. While correct (handles chain forks), it's gas inefficient. Consider caching with fork detection like OpenZeppelin's implementation.

#### INFORMATIONAL: PermissionedV2 Intentionally Omits verifyingContract

**File:** `fhe/access/PermissionedV2.sol`

This is intentional design to allow single signatures to work across multiple contracts. The access control is handled via the `contracts` and `projects` arrays in the permission struct. This is documented and acceptable.

---

## 6. Permit Signatures (ERC-2612)

### 6.1 Implementations

| Contract | Base Implementation |
|----------|---------------------|
| `tokens/LRC20/extensions/LRC20Permit.sol` | Custom (follows standard) |
| `governance/Stake.sol` | OpenZeppelin ERC20Permit |
| `liquid/LiquidLUX.sol` | OpenZeppelin ERC20Permit |
| `tokens/LRC4626/LRC4626.sol` | OpenZeppelin ERC20Permit |
| `tokens/LRC20/LRC20.sol` | OpenZeppelin ERC20Permit |

### 6.2 Findings

#### LOW: LRC20Permit Uses ECDSA.recover Correctly

**File:** `tokens/LRC20/extensions/LRC20Permit.sol:65`

```solidity
address signer = ECDSA.recover(hash, v, r, s);
```

Good: Uses OpenZeppelin's ECDSA library which includes malleability protection.

#### INFORMATIONAL: All Permit Implementations Follow ERC-2612

All permit implementations correctly:
- Use sequential nonces via `_useNonce()`
- Include deadline validation
- Use EIP-712 typed data hashing
- Validate signer matches owner

---

## 7. Merkle Proof Verification

### 7.1 Implementations Found

| Contract | Purpose |
|----------|---------|
| `privacy/ZNote.sol` | Note commitment tree |
| `privacy/ShieldedTreasury.sol` | Commitment tree |
| `privacy/Poseidon2Commitments.sol` | ZK commitment tree |
| `privacy/PrivateBridge.sol` | Cross-chain commitment |
| `precompile/interfaces/IZK.sol` | Precompile interface |
| `precompile/interfaces/IHash.sol` | Hash precompile interface |

### 7.2 Findings

#### MEDIUM: Second Preimage Attack Risk in Custom Merkle Implementations

**Files:** `privacy/ZNote.sol`, `privacy/ShieldedTreasury.sol`

```solidity
// privacy/ZNote.sol:382-385
if (pathIndices[i] == 0) {
    currentHash = keccak256(abi.encodePacked(currentHash, proof[i]));
} else {
    currentHash = keccak256(abi.encodePacked(proof[i], currentHash));
}
```

**Issue:** Without domain separation between leaf and internal nodes, second preimage attacks may be possible. An attacker could potentially construct a proof where a leaf hash equals an internal node hash.

**Recommendation:** Use different hash domains for leaves vs internal nodes:
```solidity
// For leaves:
keccak256(abi.encodePacked(bytes1(0x00), leafData))
// For internal nodes:
keccak256(abi.encodePacked(bytes1(0x01), left, right))
```

#### INFORMATIONAL: OpenZeppelin MerkleProof Not Used

The contracts implement custom Merkle verification rather than using OpenZeppelin's audited `MerkleProof` library. Custom implementations are acceptable for specific use cases (e.g., incremental Merkle trees) but increase audit surface.

---

## 8. Commitment Schemes

### 8.1 Implementations

| Contract | Scheme Type |
|----------|-------------|
| `safe/SafeLSSSigner.sol` | LSS commitment |
| `privacy/Poseidon2Commitments.sol` | Pedersen-style |
| `privacy/PrivateTeleport.sol` | Note commitments |
| `precompile/interfaces/IZK.sol` | KZG, FRI commitments |

### 8.2 Findings

#### LOW: Commitment Binding in SafeLSSSigner

**File:** `safe/SafeLSSSigner.sol:134`

```solidity
commitment: keccak256(abi.encodePacked(_threshold, _totalSigners, _publicKey))
```

The commitment binds threshold parameters to public key. This is a good pattern for preventing parameter manipulation.

---

## 9. FROST Schnorr Signatures

### 9.1 Implementation Analysis

**File:** `safe/FROST.sol`

The FROST library implements RFC 9591 FROST(secp256k1, SHA-256) Schnorr signatures using the `ecrecover` precompile trick for mul-mul-add operations.

### 9.2 Findings

#### INFORMATIONAL: Signature Malleability Handled

**File:** `safe/FROST.sol:294-311`

```solidity
// TODO(nlordell): I don't think this is required for Schnorr
// signatures, but do it anyway just in case.
{
    bool pOk = isValidPublicKey(px, py);
    bool rOk = _isOnCurve(rx, ry);
    bool zOk = _isScalar(z);
    // ...
}
```

Good: The implementation validates that `z` is a valid scalar (in range `(0, N)`), preventing trivial malleability via `z` manipulation.

#### LOW: Public Key Restriction Documented

**File:** `safe/FROST.sol:228-230**

```solidity
/// @dev Note that public key's x-coordinate `px` must be smaller than the
/// curve order for the math trick with `ecrecover` to work.
```

The restriction that `px < N` is documented and enforced in `isValidPublicKey()`. This is a known limitation of the ecrecover trick approach.

---

## 10. Lamport Signatures

### 10.1 Implementation Analysis

**File:** `safe/SafeThresholdLamportModule.sol`

Implements one-time Lamport signatures for post-quantum security with T-Chain MPC threshold control.

### 10.2 Findings

#### INFORMATIONAL: Proper One-Time Key Rotation

**File:** `safe/SafeThresholdLamportModule.sol:197-202`

```solidity
bytes32 oldPkh = pkh;
pkh = nextPKH;
lamportNonce++;

emit LamportKeyRotated(oldPkh, nextPKH);
```

Good: Key rotation is enforced as part of the execution flow, ensuring one-time property of Lamport signatures.

#### LOW: Domain Separation Properly Implemented

**File:** `safe/SafeThresholdLamportModule.sol:180-185**

```solidity
uint256 m = uint256(keccak256(abi.encodePacked(
    safeTxHash,
    nextPKH,
    address(this),   // Prevent cross-contract replay
    block.chainid    // Prevent cross-chain replay
)));
```

Good: Domain separation includes contract address and chain ID to prevent replay attacks across chains and contracts.

---

## 11. Replay Attack Vectors

### 11.1 Analysis

#### CRITICAL: Signature-Based Replay Protection in Legacy Bridges

**Files:** `bridge/Teleport.sol`, `bridge/Bridge.sol`

```solidity
// bridge/Bridge.sol:441-443
require(
    !transactionMap[signedTXInfo_].exists,
    "Duplicated Transaction Hash"
);
```

**Issue:** Replay protection uses the raw signature bytes as the key. Due to ECDSA signature malleability (see Section 1.2), an attacker can derive an alternative valid signature for the same message and bypass replay protection.

**Attack Scenario:**
1. User submits valid bridge mint with signature `(r, s, v)`
2. Attacker computes malleable signature `(r, n-s, v')` for same message
3. Attacker replays with malleable signature, passing replay check
4. Tokens minted twice

**Recommendation:**
1. Use message hash (not signature) as replay key, OR
2. Enforce `s` is in lower half of curve order before storing

#### LOW: Proper Replay Protection Examples

- `bridge/teleport/TeleportBridge.sol`: Uses `claimId` computed from claim data, not signature
- `router/IntentRouter.sol`: Uses `filledAmounts[orderHash]` where orderHash is from order data
- `governance/DAO.sol`: Uses `receipt.hasVoted` mapping keyed by voter address

---

## 12. Front-Running Considerations

### 12.1 Analysis

#### MEDIUM: Bridge Mints Susceptible to Front-Running

**Files:** `bridge/Teleport.sol`, `bridge/Bridge.sol`

Once an MPC oracle signature is observed in the mempool, anyone can submit the mint transaction. The recipient is fixed in the signed message, but gas price wars could occur.

**Mitigation:** The contracts use `nonReentrant` which prevents reentrancy but not front-running. Consider implementing commit-reveal or private mempool submission for high-value transfers.

#### LOW: Intent Router Has MEV Protection Documentation

**File:** `router/IntentRouter.sol`

The contract explicitly mentions "MEV protection via private mempools" in its documentation, indicating awareness of front-running concerns.

---

## 13. Recommendations Summary

### Critical Priority
1. **Fix signature malleability in bridge contracts** - Add `s` value validation or use OpenZeppelin ECDSA
2. **Change replay protection key from signature to message hash** in legacy bridges

### High Priority
3. **Add explicit `address(0)` check after ecrecover** in all signature verification
4. **Add version field to DAO.sol EIP-712 domain separator**
5. **Fix nonce validation in Account.sol** session key execution
6. **Review ConfidentialLRC20Votes nonce increment ordering**

### Medium Priority
7. **Replace `abi.encodePacked` with `abi.encode`** for security-critical hashing
8. **Add leaf/node domain separation** in custom Merkle implementations
9. **Review oracle staleness timing** for manipulation resistance
10. **Avoid block.timestamp in identifier generation** (even in mocks, as bad patterns propagate)

### Low Priority
11. Consider caching domain separator in DAO.sol
12. Document public key restrictions for FROST signatures in user-facing docs
13. Add comments explaining nonce patterns in complex flows

---

## 14. Positive Findings

The following patterns demonstrate good cryptographic practices:

1. **OpenZeppelin Usage**: Most newer contracts use audited OpenZeppelin libraries (ECDSA, EIP712, Nonces)
2. **EIP-712 Adoption**: Widespread use of typed data signing for user experience and security
3. **Domain Separation**: Most signature schemes include chain ID and contract address
4. **Sequential Nonces**: Proper sequential nonce patterns in permit and order systems
5. **One-Time Key Rotation**: Lamport implementation correctly enforces key rotation
6. **Snapshot Voting**: DAO uses checkpointed voting to prevent flash loan attacks

---

## 15. Files Reviewed

### Primary Cryptographic Contracts
- `bridge/Teleport.sol`
- `bridge/Bridge.sol`
- `bridge/teleport/TeleportBridge.sol`
- `governance/DAO.sol`
- `governance/Council.sol`
- `account/Account.sol`
- `safe/FROST.sol`
- `safe/SafeThresholdLamportModule.sol`
- `tokens/LRC20/extensions/LRC20Permit.sol`
- `router/IntentRouter.sol`
- `fhe/governance/ConfidentialLRC20Votes.sol`
- `fhe/access/PermissionedV2.sol`

### Supporting Files
- `privacy/ZNote.sol`
- `privacy/ShieldedTreasury.sol`
- `privacy/Poseidon2Commitments.sol`
- `precompile/interfaces/IZK.sol`
- `precompile/interfaces/IHash.sol`
- Various yield strategy and bridge token contracts

---

**End of Report**
