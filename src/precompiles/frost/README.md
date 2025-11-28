# FROST Threshold Signature Precompile

## Overview

The FROST (Flexible Round-Optimized Schnorr Threshold) precompile enables efficient threshold signature verification for Schnorr-based signatures. FROST allows any t-of-n parties to collaboratively produce a signature that appears to be from a single signer.

**Address**: `0x020000000000000000000000000000000000000C`

## Features

- **Threshold Signatures**: Any t out of n parties can sign
- **Schnorr-Based**: Compatible with Ed25519 and secp256k1 Schnorr
- **Bitcoin Taproot**: Used for Bitcoin BIP-340/341 multisig
- **Efficient**: Lower gas cost than ECDSA threshold (CGGMP21)
- **Standardized**: Based on IETF FROST specification

## Algorithm

FROST is a threshold signature scheme where:
- **n** total parties hold shares of a private key
- Any **t** parties can collaborate to produce a valid signature
- The signature is indistinguishable from a single-party Schnorr signature
- Compatible with BIP-340 (Bitcoin Taproot) and Ed25519

### Key Properties

- **Non-Interactive**: After setup, signing requires minimal rounds
- **Compact Signatures**: 64 bytes (standard Schnorr)
- **Flexible Threshold**: Configurable t-of-n threshold
- **Efficient Verification**: Standard Schnorr verification

## Specifications

### Input Format

Total size: **136 bytes** (minimum)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0-3 | 4 bytes | threshold | Minimum signers required (t) |
| 4-7 | 4 bytes | totalSigners | Total number of parties (n) |
| 8-39 | 32 bytes | publicKey | Aggregated public key |
| 40-71 | 32 bytes | messageHash | SHA-256 hash of message |
| 72-135 | 64 bytes | signature | Schnorr signature (R \|\| s) |

### Output Format

**32 bytes**: Boolean result as uint256
- `0x0000...0001` = Valid signature
- `0x0000...0000` = Invalid signature

### Gas Costs

| Operation | Base Gas | Per-Signer Gas |
|-----------|----------|----------------|
| FROST Verify | 50,000 | 5,000 |

**Examples**:
- 2-of-3 threshold: 50,000 + (3 × 5,000) = **65,000 gas**
- 3-of-5 threshold: 50,000 + (5 × 5,000) = **75,000 gas**
- 10-of-15 threshold: 50,000 + (15 × 5,000) = **125,000 gas**

## Usage Examples

### Solidity

```solidity
import "./IFROST.sol";

contract MyContract is FROSTVerifier {
    function processThresholdSignedData(
        uint32 threshold,
        uint32 totalSigners,
        bytes32 publicKey,
        bytes32 messageHash,
        bytes calldata signature
    ) external {
        // Verify FROST threshold signature
        verifyFROSTSignature(
            threshold,
            totalSigners,
            publicKey,
            messageHash,
            signature
        );

        // Process data - signature is valid
    }
}
```

### TypeScript (ethers.js)

```typescript
const FROST = new ethers.Contract(
    '0x020000000000000000000000000000000000000C',
    [
        'function verify(uint32,uint32,bytes32,bytes32,bytes) view returns(bool)'
    ],
    provider
);

// Verify 3-of-5 threshold signature
const isValid = await FROST.verify(
    3,              // threshold
    5,              // totalSigners
    publicKey,      // 32 bytes
    messageHash,    // 32 bytes
    signature       // 64 bytes
);
```

### Go

```go
import (
    "github.com/luxfi/threshold/protocols/frost"
    "github.com/luxfi/threshold/pkg/math/curve"
)

// Generate FROST keys (3-of-5 threshold)
group := curve.Secp256k1{}
threshold := 3
parties := []party.ID{"party1", "party2", "party3", "party4", "party5"}

// Each party runs keygen
config, err := frost.Keygen(group, "party1", parties, threshold)

// Later, any 3 parties can sign
signers := []party.ID{"party1", "party2", "party3"}
sig, err := frost.Sign(config, signers, messageHash)

// Verify on-chain via precompile
```

## Use Cases

### Bitcoin Taproot Multisig

```solidity
contract TaprootMultisig {
    using FROSTLib for *;

    bytes32 public taprootPublicKey;
    uint32 public constant THRESHOLD = 2;
    uint32 public constant TOTAL_SIGNERS = 3;

    function spendBitcoin(
        bytes32 messageHash,
        bytes calldata signature
    ) external {
        FROSTLib.verifyOrRevert(
            THRESHOLD,
            TOTAL_SIGNERS,
            taprootPublicKey,
            messageHash,
            signature
        );

        // Execute Bitcoin spend
    }
}
```

### Multi-Chain Governance

```solidity
contract CrossChainGovernance is FROSTVerifier {
    struct Proposal {
        bytes32 proposalHash;
        uint256 votesFor;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;

    function executeProposal(
        uint256 proposalId,
        bytes calldata thresholdSignature
    ) external {
        Proposal storage proposal = proposals[proposalId];

        // Verify threshold signature from governance committee
        verifyFROSTSignature(
            GOVERNANCE_THRESHOLD,
            GOVERNANCE_TOTAL,
            GOVERNANCE_PUBLIC_KEY,
            proposal.proposalHash,
            thresholdSignature
        );

        // Execute proposal
        proposal.executed = true;
    }
}
```

## Security Considerations

### Threshold Selection

- **2-of-3**: Common for small multisig wallets
- **3-of-5**: Standard for governance
- **5-of-7** or **7-of-10**: High-security applications
- Never use 1-of-n (defeats the purpose)

### Message Hashing

Always hash messages before signing:

```solidity
bytes32 messageHash = keccak256(abi.encodePacked(data));
```

### Public Key Management

- Store aggregated public keys securely on-chain
- Validate threshold parameters (t ≤ n)
- Use events to track configuration changes

## Performance

Benchmarks on Apple M1 Max:

| Configuration | Gas Cost | Verify Time |
|--------------|----------|-------------|
| 2-of-3 | 65,000 | ~45 μs |
| 3-of-5 | 75,000 | ~55 μs |
| 5-of-7 | 85,000 | ~65 μs |
| 10-of-15 | 125,000 | ~95 μs |

## Comparison with Other Schemes

| Algorithm | Signature Size | Gas Cost | Quantum Safe |
|-----------|---------------|----------|--------------|
| FROST (this) | 64 bytes | 50k-125k | ❌ |
| CGGMP21 | 65 bytes | 75k-175k | ❌ |
| Ringtail | 4KB | 150k-300k | ✅ |
| BLS (Warp) | 96 bytes | 120k | ❌ |

## Integration with Lux Threshold

This precompile integrates with `/Users/z/work/lux/threshold/protocols/frost`:

```go
import "github.com/luxfi/threshold/protocols/frost"

// The threshold library provides:
// - frost.Keygen() - Distributed key generation
// - frost.Sign() - Threshold signing
// - frost.Refresh() - Share refreshing
// - frost.KeygenTaproot() - Bitcoin Taproot keys
```

## Standards Compliance

- **IETF FROST**: [draft-irtf-cfrg-frost](https://datatracker.ietf.org/doc/draft-irtf-cfrg-frost/)
- **BIP-340**: Bitcoin Schnorr signatures
- **BIP-341**: Bitcoin Taproot

## References

- [FROST Paper (ePrint 2020/852)](https://eprint.iacr.org/2020/852.pdf)
- [Lux Threshold Library](https://github.com/luxfi/threshold)
- [Bitcoin BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
