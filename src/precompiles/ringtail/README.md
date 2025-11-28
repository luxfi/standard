# Ringtail Threshold Signature Precompile

Post-quantum threshold signature verification precompile for Lux EVM, implementing the LWE-based two-round threshold signature scheme from [Ringtail (ePrint 2024/1113)](https://eprint.iacr.org/2024/1113).

## Overview

The Ringtail Threshold precompile enables verification of lattice-based threshold signatures on-chain, providing post-quantum security for multi-party consensus protocols. This is a critical component of the Quasar quantum consensus mechanism.

**Precompile Address**: `0x020000000000000000000000000000000000000B`

## Features

- **Post-Quantum Security**: Based on Learning With Errors (LWE) lattice problem
- **Threshold Signatures**: Supports t-of-n threshold schemes
- **Two-Round Protocol**: Efficient distributed signing
- **Quasar Integration**: Native support for quantum consensus validators
- **Flexible Thresholds**: Configurable from 1-of-n to n-of-n

## Algorithm

Ringtail implements a threshold signature scheme based on:
- **Lattice Cryptography**: LWE problem hardness
- **Ring Learning With Errors**: Polynomial ring operations
- **Threshold Secret Sharing**: Shamir's secret sharing over rings
- **Two-Round Protocol**: Efficient distributed key generation and signing

### Parameters

From `ringtail/sign/config.go`:

| Parameter | Value | Description |
|-----------|-------|-------------|
| M | 8 | Matrix rows |
| N | 7 | Matrix columns |
| Dbar | 48 | Signature dimension |
| Q | 0x1000000004A01 | Prime modulus (48-bit) |
| LogN | 8 | Ring dimension log (256) |
| SigmaE | 6.108 | Error distribution |
| SigmaStar | 1.73e11 | Masking distribution |

### Security Level

- **Classical**: >128-bit security
- **Quantum**: Resistant to Shor's algorithm
- **Hardness**: Based on LWE with modulus Q and dimension 256

## Gas Costs

| Operation | Formula | Example |
|-----------|---------|---------|
| Base Cost | 150,000 | Fixed cost |
| Per Party | 10,000 × n | Cost per party |
| **2 parties** | 150,000 + 20,000 | **170,000 gas** |
| **3 parties** | 150,000 + 30,000 | **180,000 gas** |
| **5 parties** | 150,000 + 50,000 | **200,000 gas** |
| **10 parties** | 150,000 + 100,000 | **250,000 gas** |

## Input Format

```
Offset  | Size | Field
--------|------|------------------
0-4     | 4    | threshold (uint32)
4-8     | 4    | totalParties (uint32)
8-40    | 32   | messageHash (bytes32)
40-...  | ~4KB | signature (variable)
```

### Signature Components

The signature consists of serialized lattice elements:
- **c**: Challenge polynomial (256 bytes)
- **z**: Response vector (N × 256 bytes = 1,792 bytes)
- **Delta**: Difference vector (M × 256 bytes = 2,048 bytes)
- **A**: Public matrix (M × N × 256 bytes = 14,336 bytes)
- **bTilde**: Rounded vector (M × 256 bytes = 2,048 bytes)

**Total**: ~20KB per signature

## Usage

### Solidity

```solidity
import "./IRingtailThreshold.sol";

contract MyContract is RingtailThresholdVerifier {
    function verifyConsensus(
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool) {
        // 2-of-3 threshold
        return verifyThresholdSignature(
            2,  // threshold
            3,  // total parties
            messageHash,
            signature
        );
    }

    function processSignedData(
        bytes32 messageHash,
        bytes calldata signature
    ) external {
        // Revert if invalid
        RingtailThresholdLib.verifyOrRevert(
            2, 3, messageHash, signature
        );

        // Process data - signature is valid
    }
}
```

### TypeScript/ethers.js

```typescript
import { ethers } from 'ethers';

const RINGTAIL_THRESHOLD = '0x020000000000000000000000000000000000000B';

const abi = [
    'function verifyThreshold(uint32,uint32,bytes32,bytes) view returns(bool)'
];

const precompile = new ethers.Contract(RINGTAIL_THRESHOLD, abi, provider);

// Verify 2-of-3 threshold signature
const isValid = await precompile.verifyThreshold(
    2,                    // threshold
    3,                    // total parties
    messageHash,          // bytes32
    signatureBytes        // bytes
);
```

### Go

```go
import (
    "ringtail/sign"
    "github.com/luxfi/lattice/v6/ring"
)

// Generate threshold signature (off-chain)
threshold := 2
totalParties := 3

// Initialize rings
r, _ := ring.NewRing(1<<sign.LogN, []uint64{sign.Q})
r_xi, _ := ring.NewRing(1<<sign.LogN, []uint64{sign.QXi})
r_nu, _ := ring.NewRing(1<<sign.LogN, []uint64{sign.QNu})

// Run threshold signing protocol
// ... (see ringtail/main.go for full example)

// Verify signature
valid := sign.Verify(r, r_xi, r_nu, z, A, mu, bTilde, c, Delta)
```

## Protocol Flow

### Setup Phase
1. Trusted dealer generates keys using `sign.Gen()`
2. Secret shares distributed to n parties
3. Public parameters (A, b) published

### Signing Phase (Two Rounds)

**Round 1**: Each party generates masking polynomials
```go
D_i, MACs_i := party.SignRound1(A, sid, PRFKey, T)
```

**Round 2 Preprocess**: Verify MACs and combine D matrices
```go
valid, DSum, hash := party.SignRound2Preprocess(A, b, D, MACs, sid, T)
```

**Round 2**: Each party generates signature share
```go
z_i := party.SignRound2(A, bTilde, DSum, sid, mu, T, PRFKey, hash)
```

**Finalize**: Combiner aggregates shares
```go
c, z_sum, Delta := party.SignFinalize(z, A, bTilde)
```

### Verification
```go
valid := sign.Verify(r, r_xi, r_nu, z, A, mu, bTilde, c, Delta)
```

## Quasar Consensus Integration

The Ringtail threshold precompile is designed for Quasar consensus:

```solidity
contract QuasarConsensus {
    uint32 constant VALIDATORS = 5;
    uint32 constant THRESHOLD = 4; // 4-of-5 for finality

    function finalizeBlock(
        bytes32 blockHash,
        bytes calldata validatorSignature
    ) external {
        // Verify 4-of-5 validators signed
        RingtailThresholdLib.verifyOrRevert(
            THRESHOLD,
            VALIDATORS,
            blockHash,
            validatorSignature
        );

        // Block is finalized with quantum-resistant proof
        emit BlockFinalized(blockHash);
    }
}
```

## Security Considerations

### Post-Quantum Security
- **Quantum Attacks**: Resistant to Shor's algorithm
- **Classical Attacks**: >128-bit security under LWE assumption
- **Side Channels**: Constant-time operations in lattice library

### Threshold Properties
- **Unforgeability**: Cannot forge signature without t parties
- **Robustness**: Works with any subset of size t
- **Non-interactivity**: After setup, signing is non-interactive per party

### Network Security
- **MAC Protection**: Message authentication codes prevent tampering
- **Replay Protection**: Session IDs prevent signature replay
- **Rank Checks**: Full rank verification prevents malicious matrices

## Performance

### Benchmarks (Apple M1 Max)

| Operation | Time | Gas |
|-----------|------|-----|
| 2-of-3 verify | ~2.5ms | 170,000 |
| 3-of-5 verify | ~3.8ms | 200,000 |
| 5-of-7 verify | ~5.2ms | 220,000 |

### Comparison with Other Schemes

| Scheme | Signature Size | Verify Time | Quantum Secure |
|--------|---------------|-------------|----------------|
| ECDSA (secp256k1) | 65 bytes | ~88μs | ❌ |
| BLS | 96 bytes | ~2.1ms | ❌ |
| **Ringtail** | **~20KB** | **~3.8ms** | **✅** |
| ML-DSA-65 | 3.3KB | ~108μs | ✅ |
| SLH-DSA | 7.9KB | ~4.2ms | ✅ |

**Trade-offs**:
- ✅ Post-quantum security
- ✅ Threshold signatures
- ✅ Two-round protocol
- ⚠️ Large signature size (~20KB)
- ⚠️ Higher verification time

## Testing

```bash
# Run tests
cd /Users/z/work/lux/standard/src/precompiles/ringtail-threshold
go test -v

# Run benchmarks
go test -bench=. -benchmem

# Test with specific threshold
go test -run TestRingtailThresholdVerify_3of5
```

### Test Coverage

- ✅ 2-of-3 threshold signature
- ✅ 3-of-5 threshold signature
- ✅ Full threshold (n-of-n)
- ✅ Invalid signature rejection
- ✅ Wrong message rejection
- ✅ Threshold not met rejection
- ✅ Input validation
- ✅ Gas cost calculation

## Migration from Classical Signatures

### From ECDSA
```solidity
// Before (ECDSA)
function verify(bytes32 hash, bytes memory sig) public view {
    address signer = ECDSA.recover(hash, sig);
    require(isAuthorized(signer), "Unauthorized");
}

// After (Ringtail Threshold)
function verify(bytes32 hash, bytes memory sig) public view {
    RingtailThresholdLib.verifyOrRevert(
        THRESHOLD,
        TOTAL_SIGNERS,
        hash,
        sig
    );
}
```

### From BLS
```solidity
// Before (BLS aggregate)
function verify(bytes32 hash, bytes memory sig) public view {
    require(BLS.verify(aggregateKey, hash, sig), "Invalid");
}

// After (Ringtail Threshold)
function verify(bytes32 hash, bytes memory sig) public view {
    require(
        verifyThresholdSignature(THRESHOLD, N, hash, sig),
        "Invalid"
    );
}
```

## References

- [Ringtail Paper (ePrint 2024/1113)](https://eprint.iacr.org/2024/1113)
- [Lattice Library](https://github.com/luxfi/lattice)
- [Ringtail Implementation](/Users/z/work/lux/ringtail/)
- [Quasar Consensus](/Users/z/work/lux/node/consensus/protocol/quasar/)

## License

Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
