# Lux Standard Protocol Specification

**Version**: 1.0.0
**Status**: FROZEN FOR AUDIT
**Date**: 2026-04-06
**Authors**: Lux Industries Inc.
**Scope**: Asset taxonomy, bridge semantics, solvency invariants, failure behavior

This document defines the normative protocol semantics for the Lux Standard
smart contract stack. All claims are machine-checkable where noted. Auditors
SHOULD treat any deviation between this specification and deployed bytecode as
a finding.

---

## 1. Asset Taxonomy

The protocol recognizes exactly three asset classes. Contracts, registries, and
accounting state MUST NOT mix classes. A single contract MUST NOT issue assets
from more than one class.

### 1.1 Class 1: Credit Assets

**Canonical tokens**: LETH, LBTC, LUSD (and all LRC20B-derived bridge tokens).

**Definition**: An overcollateralized, in-kind redeemable liability minted
against vault-backed base assets, subject to a hard loan-to-value (LTV) cap.

**Properties**:

| Property | Constraint |
|----------|-----------|
| Issuance | Minted only when MPC attests to recognized backing on a source chain |
| Redemption | Redeemable 1:1 in kind (burn LETH, receive ETH on source chain) |
| LTV cap | Off-chain enforcement by MPC nodes: signers MUST NOT sign mint proofs when `totalMinted > LTV_CAP * totalBacking`. On-chain enforcement via daily mint limits and auto-pause at 98.5% backing ratio. |
| Yield | Credit holders have NO claim on strategy yield; yield accrues to protocol surplus (xLUX) |
| Rights | No governance rights, no profit-share, no equity characteristics |
| Daily limit | Per-token daily mint cap enforced via rolling 24-hour window |
| Exit guarantee | `burnForWithdrawal` is ALWAYS callable, including during pause states |

**Contract**: `OmnichainRouter.mintDeposit` (issuance), `OmnichainRouter.burnForWithdrawal` (redemption).
**Base contract**: `contracts/bridge/LRC20B.sol` with `MINTER_ROLE` and daily mint tracking.

### 1.2 Class 2: Yield/Equity Instruments

**Canonical token**: xLUX (LiquidLUX vault shares).

**Definition**: A claim on protocol surplus, not on redemption principal.

**Properties**:

| Property | Constraint |
|----------|-----------|
| Yield source | Absorbs fee income from DEX, bridge, lending, perps, NFT AMM, and validator rewards |
| Loss absorption | May absorb losses after slashing reserve buffer is exhausted |
| Collateral equivalence | xLUX is NEVER treated as collateral-equivalent for credit redemptions unless explicitly approved by governance vote and timelock |
| Governance | xLUX balances are checkpointed (ERC20Votes) and contribute to vLUX voting power |
| Performance fee | 10% of fee income to treasury; validator rewards exempt (0% fee) |

**Contract**: `contracts/liquid/LiquidLUX.sol`.

### 1.3 Class 3: Security Assets

**Definition**: Tokens issued under an Alternative Trading System (ATS) or
equivalent compliance layer. Not fungible with credit liabilities.

**Properties**:

| Property | Constraint |
|----------|-----------|
| Transfer restrictions | Whitelist-enforced; every `transfer` and `transferFrom` checks compliance registry |
| Lockup | Configurable per-token lockup periods enforced on-chain |
| Jurisdictional controls | Transfer blocked if sender or recipient fails jurisdiction check |
| Bridge wrapping | When bridged, MUST use restricted wrapper that preserves all transfer restrictions at the wrapper level |
| DeFi composability | Limited by design; AMM/lending integration requires explicit compliance adapter |

**Contracts**: `contracts/securities/token/`, `contracts/securities/compliance/`, `contracts/securities/registry/`.

---

## 2. Canonical Bridge Message Schema

### 2.1 Message Types

| Type | Direction | Semantics |
|------|-----------|-----------|
| `DEPOSIT_V1` | Source chain -> Router | MPC attests that collateral was deposited on source chain; router mints credit token |
| `BURN_V1` | Router -> Source chain | User burned credit token; source chain SHOULD release collateral |
| `RELEASE_V1` | Source chain -> User | Collateral released to user after finality delay |
| `BACKING_V1` | MPC -> Router | Periodic attestation of total collateral held per token on source chains |

### 2.2 DEPOSIT_V1 Envelope

```
digest = keccak256(abi.encodePacked(
    "DEPOSIT",          // fixed prefix (7 bytes)
    dstChainId,         // uint64  — destination chain (this router's chainId)
    srcChainId,         // uint64  — source chain where deposit occurred
    nonce,              // uint64  — deposit nonce, unique per (srcChainId, router)
    token,              // address — registered bridge token on destination
    recipient,          // address — mint recipient
    amount              // uint256 — amount in token's smallest unit
))
```

The digest is wrapped with `toEthSignedMessageHash` (EIP-191 prefix) before
`ecrecover` against the MPC group address.

### 2.3 BURN_V1 Envelope

Emitted as the `Burned` event:

```
event Burned(
    uint64 indexed destChain,      // where user wants collateral released
    uint64 indexed nonce,          // outboundNonce (monotonically increasing)
    address indexed token,         // credit token burned
    address sender,                // who burned
    bytes32 recipient,             // destination-chain recipient (bytes32 for non-EVM)
    uint256 amount                 // amount burned
)
```

No on-chain signature required. The burn is self-authenticating (user signs the
transaction). MPC nodes observe the event and initiate release on the source chain.

### 2.4 BACKING_V1 Envelope

```
digest = keccak256(abi.encodePacked(
    "BACKING",          // fixed prefix
    chainId,            // uint64  — this router's chain
    token,              // address — token being attested
    totalBacking,       // uint256 — total collateral held across all source chains
    timestamp           // uint256 — attestation timestamp (must be > last update)
))
```

### 2.5 Domain Separation

Each digest is chain-bound by including `chainId` (the destination router's
immutable chain identifier). Cross-chain replay is prevented because:

1. `dstChainId` in DEPOSIT_V1 MUST equal `chainId` of the receiving router.
2. Nonce is scoped to `(srcChainId, router)` — reuse across chains is impossible.
3. `ecrecover` returns the MPC group address, which is verified against the
   router's current `signers.mpcGroupAddress`.

### 2.6 Receive-Side Verification

Every `mintDeposit` call MUST pass ALL of the following checks:

| # | Check | Failure mode |
|---|-------|-------------|
| 1 | `!autoPaused && !manualPaused` | Revert — system is paused |
| 2 | `registeredTokens[token]` | Revert — unknown token |
| 3 | `!processedDeposits[srcChainId][nonce]` | Revert — replay |
| 4 | `amount > 0` | Revert — zero mint |
| 5 | `recovered == signers.mpcGroupAddress` (or individual signer) | Revert — invalid signature |
| 6 | Daily mint limit not exceeded | Revert — rate limit |

Burns (`burnForWithdrawal`) skip checks 1 and 6. Burns are ALWAYS allowed.

---

## 3. Invariants

All invariants in this section are machine-checkable. An invariant violation at
any point during contract execution constitutes a critical finding.

### 3.1 Supply/Backing Invariant

For every registered credit token `t`:

```
INV-1: totalMinted[t] == sum of all bridgeMint calls - sum of all bridgeBurn calls
```

```
INV-2: MPC nodes enforce off-chain: totalMinted[t] + mintAmount <= LTV_CAP * totalBacking[t]
       On-chain: autoPause triggers when backing ratio < 9850 bps (98.5%)
       On-chain: daily mint limits cap issuance rate per token
```

```
INV-3: For every burn of amount x:
       The protocol MUST release x units of the underlying asset on the source
       chain, subject only to:
       (a) finality delay (minFinalityConfirmations[srcChainId])
       (b) compliance hold (ATS tokens only)
       (c) source chain liveness
```

```
INV-4: redeemable principal per unit credit token = 1 underlying
       (LETH:ETH = 1:1, LBTC:BTC = 1:1, LUSD:USD = 1:1)
```

### 3.2 Equity Invariant

```
INV-5: E(t) = totalBacking[t] - totalMinted[t]
       Equity MUST be non-negative in HEALTHY state.
       Equity < 0 triggers EMERGENCY state.
```

### 3.3 Nonce Invariant

```
INV-6: For every (srcChainId, nonce) pair, processedDeposits[srcChainId][nonce]
       transitions from false to true EXACTLY ONCE and NEVER reverts to false.
```

```
INV-7: outboundNonce is monotonically increasing.
       outboundNonce(tx_n) > outboundNonce(tx_{n-1}) for all sequential burns.
```

### 3.4 Signer Invariant

```
INV-8: signers.mpcGroupAddress != address(0) at all times.
       No code path sets it to zero.
```

```
INV-9: Signer rotation requires a valid MPC threshold signature from the
       CURRENT signer set. No single entity can rotate signers.
```

---

## 4. Solvency State Machine

### 4.1 States

| State | Code | Entry condition |
|-------|------|----------------|
| HEALTHY | 0 | `totalBacking[t] >= totalMinted[t]` AND `backing ratio >= 1/LTV_CAP` for all t |
| RESTRICTED_MINT | 1 | `totalBacking[t] < totalMinted[t] / LTV_CAP` BUT `totalBacking[t] >= totalMinted[t]` |
| EMERGENCY | 2 | `backing ratio < 9850 bps (98.5%)` — auto-triggered by `updateBacking` |
| RECOVERY | 3 | `backing ratio >= 9900 bps (99%)` after EMERGENCY — auto-cleared by `updateBacking` |

### 4.2 Transition Table

```
From              To                  Trigger                              Who
─────────────────────────────────────────────────────────────────────────────────
HEALTHY           RESTRICTED_MINT     updateBacking: ratio < 1/LTV_CAP    MPC attestation
HEALTHY           EMERGENCY           updateBacking: ratio < 9850 bps     MPC attestation (autoPaused = true)
RESTRICTED_MINT   EMERGENCY           updateBacking: ratio < 9850 bps     MPC attestation (autoPaused = true)
RESTRICTED_MINT   HEALTHY             updateBacking: ratio >= 1/LTV_CAP   MPC attestation
EMERGENCY         RECOVERY            updateBacking: ratio >= 9900 bps    MPC attestation (autoPaused = false)
RECOVERY          HEALTHY             Governance confirms recapitalized   Governor
RECOVERY          EMERGENCY           updateBacking: ratio drops again    MPC attestation
Any               MANUAL_PAUSE        pauseBySigners (MPC signature)      MPC threshold
MANUAL_PAUSE      Previous state      unpauseBySigners (MPC signature)    MPC threshold
```

### 4.3 Operations Per State

| Operation | HEALTHY | RESTRICTED_MINT | EMERGENCY | RECOVERY |
|-----------|---------|-----------------|-----------|----------|
| mintDeposit | YES | NO (would exceed LTV) | NO (autoPaused) | NO (mint gradually re-enabled) |
| batchMintDeposit | YES | NO | NO | NO |
| burnForWithdrawal | YES | YES | YES | YES |
| updateBacking | YES | YES | YES | YES |
| Signer rotation | YES | YES | YES (critical) | YES |
| Governor config | YES | YES | LIMITED | LIMITED |
| Strategy deposits | YES | REDUCED | NO | NO |
| Strategy withdrawals | NORMAL | FORCED unwind | FORCED unwind | HALTED until recap |

### 4.4 Events

Each state transition MUST emit:

```
event BackingUpdated(address indexed token, uint256 totalBacking, uint256 timestamp)
```

The `autoPaused` boolean is the on-chain encoding of EMERGENCY state. The
`manualPaused` boolean is orthogonal (MPC can pause/unpause independently).

---

## 5. Failure Behavior

### 5.1 MPC Halt

**Scenario**: All MPC signers become unavailable. No new signatures are produced.

**Behavior**: Mode B — user-executable fallback.

- Burns (`burnForWithdrawal`) remain callable unconditionally.
- After timeout `T` (configurable, default 72 hours) without a new backing
  attestation, the protocol enters stale-backing mode (Section 5.2).
- Users who burned can self-relay their burn proof to the source chain. The
  burn event on-chain serves as the proof. Source chain release logic MUST
  accept burn proofs older than `T` without requiring fresh MPC co-signature.
- No new mints are possible without MPC signatures.

**Rationale**: The exit path (burn) is unconditional. Users are never trapped.

### 5.2 Stale Backing

**Scenario**: `block.timestamp - lastBackingUpdate[token] > maxBackingReportAge`.

**Behavior**:

- `maxBackingReportAge` is configurable per chain (default: 24 hours).
- When backing is stale, `mintDeposit` MUST revert for the affected token.
- Burns and releases remain functional.
- The protocol does NOT auto-pause for stale backing alone — it only disables
  new issuance.

**Implementation note**: The current contract uses `autoPaused` for
undercollateralization. Stale-backing mint disablement is a separate check on
`lastBackingUpdate[token]` enforced in the mint path.

### 5.3 Strategy Loss Waterfall

When yield strategy losses reduce backing:

```
1. Protocol surplus buffer absorbs first losses (equity E > 0)
2. If surplus exhausted → RESTRICTED_MINT (no new issuance)
3. If backing < 98.5% of minted → EMERGENCY (autoPaused = true)
4. Governor + MPC must decide: recapitalize, socialize loss, or wind down
5. Strategy deployment HALTED until backing fully restored
```

Loss socialization (if any) applies to xLUX holders (Class 2), NEVER to credit
token holders (Class 1). Credit tokens maintain 1:1 redemption.

### 5.4 Chain Reorganization

**Per-chain finality thresholds** (not a global constant):

```
minFinalityConfirmations[chainId]
```

| Chain | Minimum confirmations | Approximate time |
|-------|----------------------|-----------------|
| Ethereum | 64 blocks | ~13 minutes |
| Bitcoin | 6 blocks | ~60 minutes |
| Lux C-Chain | 1 block (instant finality) | ~2 seconds |
| Lux Subnets | 1 block (instant finality) | ~2 seconds |

MPC nodes MUST NOT sign a DEPOSIT_V1 message until the source chain deposit
has reached `minFinalityConfirmations[srcChainId]`.

If a reorg invalidates a deposit after mint, the backing attestation
(`BACKING_V1`) will reflect the reduced backing, triggering the solvency state
machine (Section 4).

### 5.5 Oracle Failure

The bridge does not use external price oracles for credit token operations.
Credit tokens are redeemed 1:1 in kind (not at a price).

For the broader DeFi stack (perps, lending, AMM) which depends on the price
oracle (`contracts/oracle/Oracle.sol`):

- Oracle has circuit breaker: max 10% price change with 5-minute cooldown.
- If all price sources fail, `health()` returns `(false, 0)`.
- Affected protocols MUST freeze minting/opening for the affected asset.
- Like-for-like redemption (exit existing positions) remains allowed.

---

## 6. ATS Boundary

### 6.1 Wrapper Model

Security assets (Class 3) are issued under an ATS compliance layer. When
bridged to other chains, the protocol uses a strict wrapper model:

```
ATS Security Token  ->  Restricted Wrapped Security Token
```

The wrapper contract MUST:

1. Check the compliance registry on every `transfer` and `transferFrom`.
2. Enforce lockup periods: `block.timestamp >= lockupEnd[tokenId]`.
3. Enforce whitelist: both sender and recipient MUST be on the approved list.
4. Enforce jurisdictional controls: blocked jurisdictions reject transfers.
5. Emit compliance events for off-chain auditing.

### 6.2 DeFi Composability

Security tokens are NOT composable with unrestricted DeFi protocols. A
restricted wrapped security token CANNOT be deposited into an AMM pool,
lending market, or perps vault unless that protocol has been explicitly
approved in the compliance registry and implements the required transfer
restriction checks.

### 6.3 Contracts

- `contracts/securities/compliance/` — compliance registry, jurisdiction checks
- `contracts/securities/registry/` — investor whitelist, lockup tracking
- `contracts/securities/token/` — restricted ERC20 with transfer hooks
- `contracts/securities/bridge/` — restricted wrapper for cross-chain bridging

---

## 7. LETH Canonical Definition

> LETH is a protocol-issued, fully collateralized, in-kind redeemable credit
> token backed by ETH vault assets and minted subject to a hard maximum
> loan-to-value ratio of 90%, with strategy yield accruing to protocol surplus
> (xLUX) rather than to LETH holders.

This definition applies mutatis mutandis to LBTC (backed by BTC) and LUSD
(backed by USD-equivalent stablecoins).

**Regulatory classification**: LETH is a collateralized credit instrument, not
an equity, not a security, and not a deposit. It confers no governance rights,
no profit participation, and no claim on yield. It is redeemable 1:1 for the
underlying asset.

---

## 8. System Classification

The Lux Standard is an **omnichain collateralized credit and settlement
protocol** comprising four subsystems:

### 8.1 Collateral Custody (Vaults)

Source-chain vaults hold deposited collateral. Custody is MPC-controlled
(threshold signature). No single key can move vaulted assets.

### 8.2 Credit Issuance (Router)

`OmnichainRouter` on each destination chain mints credit tokens against MPC-
attested deposits. Issuance is rate-limited (daily caps) and LTV-bounded.

### 8.3 Transport and Finality (MPC + Warp)

Cross-chain message transport uses two mechanisms:

- **MPC signatures**: CGGMP21 or FROST threshold signatures for cross-ecosystem
  bridges (Ethereum, Bitcoin, Solana, etc.).
- **Lux Warp Messaging**: BLS-aggregated validator signatures for intra-Lux
  cross-chain operations (C-Chain to subnets).

Finality guarantees are per-chain (Section 5.4).

### 8.4 Surplus Allocation (Yield + Governance)

Protocol surplus (backing minus liabilities) flows through:

1. `FeeSplitter` collects fees from all DeFi protocols.
2. `LiquidLUX` (xLUX) receives 90% of fees; treasury receives 10%.
3. `ValidatorVault` forwards validator rewards (0% performance fee).
4. `GaugeController` governs fee allocation weights.
5. `Governor` + `Timelock` control protocol parameters.

---

## 9. Trust Assumptions

### 9.1 MPC Threshold

The MPC threshold (t-of-n) IS the trust model. The current default is 2-of-3.

**What the MPC group CAN do**:

- Sign DEPOSIT_V1 messages (mint credit tokens)
- Sign BACKING_V1 attestations (report collateral levels)
- Pause the bridge (manual pause)
- Propose signer rotation (with operational delay)

**What the MPC group CANNOT do**:

- Mint without a valid deposit on the source chain (the signature attests to
  an observed event; the MPC nodes verify source-chain state before signing).
- Bypass nonce checks (replay prevention is on-chain).
- Prevent burns (exit guarantee; burns skip pause checks).

### 9.2 No Single Entity

No single MPC signer can produce a valid threshold signature. The threshold
parameter `t` MUST be `>= 2`. A 1-of-n configuration is rejected at
deployment.

### 9.3 Signer Rotation

Signer rotation is subject to an operational delay (`signerRotationDelay`,
default 24 hours, governor-configurable, max 7 days). This delay is for
cross-chain coordination (updating all 18+ chain deployments atomically), NOT
a security parameter. The security guarantee comes from the threshold
requirement: the current signer set must produce a valid t-of-n signature to
approve any rotation.

Rotation lifecycle:

```
1. proposeSignerRotation(newSigners, mpcSignature)
   — validates threshold signature from current signers
   — sets pendingSigners, pendingSignersActivateAt = now + delay
2. Wait signerRotationDelay
3. executeSignerRotation()
   — replaces signers with pendingSigners
   — emits SignerRotationExecuted
```

### 9.4 Governor Capabilities

The governor (typically a DAO timelock) controls:

- Bridge fee rate (max 1% hard cap, immutable)
- Stakeholder share of fees
- Daily mint limits per token
- Token registration
- Shariah compliance mode
- Signer rotation delay (max 7 days)
- Stakeholder vault address (48-hour timelock)

The governor CANNOT:

- Mint tokens
- Move vaulted collateral
- Bypass MPC signature verification
- Disable burn functionality
- Set fees above the immutable 1% cap
- Rotate MPC signers (requires MPC threshold signature)

### 9.5 On-Chain Verification

MPC group address is verified on-chain via `ecrecover`:

```solidity
address recovered = digest.toEthSignedMessageHash().recover(mpcSignature);
require(_isAuthorizedSigner(recovered), "Invalid MPC signature");
```

`_isAuthorizedSigner` checks against `signers.mpcGroupAddress` (the aggregate
threshold key) only. Individual signer addresses in the `SignerSet` struct are
stored for accountability and display purposes only — they are never used in
signature verification. This is by design: the MPC threshold protocol produces
a single aggregate signature that can only exist if t-of-n signers cooperated.

### 9.6 Exit Guarantee

Burns (`burnForWithdrawal`) are ALWAYS callable:

- No pause check.
- No daily limit check.
- No MPC signature required.
- No governor approval required.

The burn event serves as an irrevocable proof of destruction. The user's exit
right is unconditional.

---

## Appendix A: Contract Addresses (Reference)

See `DEPLOYMENTS.md` for per-network deployed addresses.

## Appendix B: Glossary

| Term | Definition |
|------|-----------|
| Credit token | Class 1 asset (LETH, LBTC, LUSD) — collateralized, redeemable 1:1 |
| xLUX | LiquidLUX vault share — Class 2 yield/equity instrument |
| LTV cap | Maximum ratio of minted supply to attested backing |
| MPC group address | The aggregate public key of the threshold signer set |
| Backing ratio | `totalBacking[t] / totalMinted[t]` expressed in basis points |
| autoPaused | Boolean set when backing ratio < 9850 bps; cleared when >= 9900 bps |
| manualPaused | Boolean set/cleared by MPC threshold signature; orthogonal to autoPaused |
| Signer rotation | Replacement of the MPC signer set; requires current-set threshold signature + delay |
| Exit guarantee | Burns are always allowed regardless of system state |

## Appendix C: Revision History

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-04-06 | Initial frozen specification for audit |
