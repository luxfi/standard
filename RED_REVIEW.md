# Red Team Review — Private Contracts (lux/standard)

Review date: 2026-04-12

## Fixed Findings

| # | Severity | Title | Status |
|---|----------|-------|--------|
| 1 | CRITICAL | Disclosure.registerVerifier has no access control | FIXED: onlyOwner modifier, immutable _owner |
| 7 | MEDIUM | submitShare allows same party to submit multiple shares | FIXED: _submittedShare mapping, ShareAlreadySubmitted error |
| 11 | LOW | PrivateStore unbounded ct size | FIXED: maxCtSize immutable, CiphertextTooLarge error |
| 12 | LOW | CRDTAnchor opCount gap attack | FIXED: maxOpCountJump immutable, OpCountJumpTooLarge error |

## INFO Findings (not fixed, documented)

### INFO-1: Disclosure contract is monolithic

All three primitives (viewing keys, threshold, selective) share one
contract. A vulnerability in one section risks the storage of all three.

Mitigation: accepted tradeoff for deployment simplicity. Each primitive
uses independent storage slots (no cross-contamination). Can be split
into separate contracts if audit scope grows.

### INFO-2: PrivateStore has no global storage cap

While individual ciphertext size is now capped, there is no limit on the
total number of blobs a single address can store. An attacker can fill
contract storage by writing many small blobs.

Mitigation: economic — each write costs gas proportional to storage used.
The EVM's gas model is the rate limiter. For application-layer caps, use
the gateway/ATS permission system.

### INFO-3: CRDTAnchor does not verify stateRoot correctness

The contract stores whatever root the caller provides. It cannot verify
that the root matches an actual CRDT snapshot because the snapshot is
encrypted off-chain.

Mitigation: by design. The anchor provides tamper evidence and rollback
prevention, not data validation. Validators cross-check roots during
threshold disclosure workflows.
