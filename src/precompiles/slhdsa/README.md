# SLH-DSA Signature Verification Precompile

## Overview

This precompile implements **SLH-DSA (Stateless Hash-Based Digital Signature Algorithm)** signature verification as specified in [FIPS 205](https://csrc.nist.gov/pubs/fips/205/final).

**Address**: `0x0200000000000000000000000000000000000007`

## FIPS 205 - SLH-DSA

SLH-DSA (formerly SPHINCS+) is a **post-quantum digital signature scheme** based on hash functions. It provides:

- **Quantum Resistance**: Secure against attacks by quantum computers
- **Stateless Operation**: No state management required (unlike XMSS)
- **Minimal Assumptions**: Security based only on collision-resistant hash functions
- **Conservative Security**: Well-understood hash-based construction

## Parameter Sets

SLH-DSA supports 12 parameter sets across 3 security levels:

### Category 1 (128-bit security)
| Parameter Set | Hash Function | Signature Size | Sign Speed | Verify Speed |
|--------------|---------------|----------------|------------|--------------|
| SHA2-128s | SHA-256 | 7,856 bytes | Slow | Fast |
| SHA2-128f | SHA-256 | 17,088 bytes | Fast | Fast |
| SHAKE-128s | SHAKE256 | 7,856 bytes | Slow | Fast |
| SHAKE-128f | SHAKE256 | 17,088 bytes | Fast | Fast |

### Category 3 (192-bit security)
| Parameter Set | Hash Function | Signature Size | Sign Speed | Verify Speed |
|--------------|---------------|----------------|------------|--------------|
| SHA2-192s | SHA-256/512 | 16,224 bytes | Slow | Fast |
| SHA2-192f | SHA-256/512 | 35,664 bytes | Fast | Fast |
| SHAKE-192s | SHAKE256 | 16,224 bytes | Slow | Fast |
| SHAKE-192f | SHAKE256 | 35,664 bytes | Fast | Fast |

### Category 5 (256-bit security)
| Parameter Set | Hash Function | Signature Size | Sign Speed | Verify Speed |
|--------------|---------------|----------------|------------|--------------|
| SHA2-256s | SHA-512 | 29,792 bytes | Slow | Fast |
| SHA2-256f | SHA-512 | 49,856 bytes | Fast | Fast |
| SHAKE-256s | SHAKE256 | 29,792 bytes | Slow | Fast |
| SHAKE-256f | SHAKE256 | 49,856 bytes | Fast | Fast |

**Trade-offs**:
- **"s" (small)**: Smaller signatures, slower signing (~300-600ms)
- **"f" (fast)**: Larger signatures, faster signing (~10-50ms)
- Verification speed is similar for both variants (~300-600μs)

## Performance Benchmarks

**Apple M1 Max Results**:

| Operation | SHA2-128s | SHA2-256s |
|-----------|-----------|-----------|
| Sign | ~309ms | ~603ms |
| Verify | ~286μs | ~593μs |
| KeyGen | ~35ms | ~71ms |

**Verification Throughput**:
- SHA2-128s: ~3,500 signatures/second
- SHA2-256s: ~1,700 signatures/second

## Gas Costs

```
Gas = BaseGas + (MessageLength * PerByteGas)
BaseGas = 15,000
PerByteGas = 10
```

**Examples**:
- Empty message: 15,000 gas
- 100-byte message: 16,000 gas
- 1KB message: 25,240 gas
- 10KB message: 115,000 gas

## Usage

### Solidity Interface

```solidity
interface ISLHDSA {
    function verify(
        bytes calldata publicKey,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool valid);
}
```

### Example Contract

```solidity
import {SLHDSAVerifier} from "./ISLHDSA.sol";

contract MyContract is SLHDSAVerifier {
    function processSignedData(
        bytes calldata publicKey,
        bytes calldata data,
        bytes calldata signature
    ) external {
        // Verify signature with automatic revert on failure
        require(
            verifySLHDSASignature(publicKey, data, signature),
            "Invalid signature"
        );
        
        // Process data - signature is valid
        // ...
    }
}
```

### Using the Library

```solidity
import {SLHDSALib} from "./ISLHDSA.sol";

contract Example {
    function verifyWithRevert(
        bytes memory publicKey,
        bytes memory message,
        bytes memory signature
    ) public view {
        // Automatically reverts if signature is invalid
        SLHDSALib.verifyOrRevert(publicKey, message, signature);
    }
    
    function estimateVerificationGas(uint256 messageLength) 
        public 
        pure 
        returns (uint256) 
    {
        return SLHDSALib.estimateGas(messageLength);
    }
}
```

### TypeScript/ethers.js

```typescript
const SLHDSA_ADDRESS = '0x0200000000000000000000000000000000000007';
const SLHDSA = new ethers.Contract(
    SLHDSA_ADDRESS,
    ['function verify(bytes,bytes,bytes) view returns(bool)'],
    provider
);

const isValid = await SLHDSA.verify(publicKey, message, signature);
console.log('Signature valid:', isValid);
```

## Input Format

The precompile expects input in the following format:

```
[mode(1 byte)] [pubKeyLen(2 bytes)] [publicKey] [msgLen(2 bytes)] [message] [signature]
```

**Fields**:
1. `mode` (1 byte): Parameter set identifier (0-11)
   - 0: SHA2-128s, 1: SHAKE-128s, 2: SHA2-128f, 3: SHAKE-128f
   - 4: SHA2-192s, 5: SHAKE-192s, 6: SHA2-192f, 7: SHAKE-192f
   - 8: SHA2-256s, 9: SHAKE-256s, 10: SHA2-256f, 11: SHAKE-256f
2. `pubKeyLen` (2 bytes, big-endian): Length of public key
3. `publicKey` (32, 48, or 64 bytes): The SLH-DSA public key
4. `msgLen` (2 bytes, big-endian): Length of message
5. `message` (variable): The message that was signed
6. `signature` (7856-49856 bytes): The SLH-DSA signature

## Output Format

Single byte indicating verification result:
- `0x01`: Signature is valid
- `0x00`: Signature is invalid

## Security Considerations

### Post-Quantum Security

SLH-DSA provides security against quantum computer attacks because:
1. Based on hash functions (no algebraic structure to exploit)
2. No known quantum algorithm for breaking collision resistance
3. Conservative security assumptions

### Hash Function Requirements

- **SHA-2**: Industry standard, widely deployed
- **SHAKE**: SHA-3 based, newer but standardized

### Signature Size Trade-offs

Large signatures are a characteristic of hash-based schemes:
- **Small variants** ("s"): More efficient for storage
- **Fast variants** ("f"): Better for high-throughput signing

### Recommended Parameter Sets

- **General use**: SHA2-128s or SHA2-256s
  - Smaller signatures, acceptable signing speed for most applications
  
- **High-throughput signing**: SHA2-128f or SHA2-256f
  - When signing speed is critical and storage is available
  
- **Conservative security**: SHA2-256s
  - Maximum security level, reasonable signature size

## Comparison with Other Schemes

| Scheme | Type | Signature Size | Verify Time | Quantum Secure |
|--------|------|----------------|-------------|----------------|
| ECDSA | Elliptic Curve | 65 bytes | ~88μs | ❌ |
| ML-DSA-65 | Lattice | 3,309 bytes | ~108μs | ✅ |
| SLH-DSA-SHA2-128s | Hash-based | 7,856 bytes | ~286μs | ✅ |
| SLH-DSA-SHA2-256s | Hash-based | 29,792 bytes | ~593μs | ✅ |

**Trade-offs**:
- SLH-DSA has larger signatures than ML-DSA
- SLH-DSA has slower verification than ML-DSA
- SLH-DSA has more conservative security assumptions
- SLH-DSA requires no state management

## Implementation Details

- **Library**: Cloudflare CIRCL v1.6.1
- **Standard**: FIPS 205 (Final)
- **Algorithm**: SPHINCS+ with FIPS 205 parameters
- **Hash Functions**: SHA-256, SHA-512, SHAKE256
- **Security Levels**: 128-bit, 192-bit, 256-bit

## Error Handling

The precompile returns `0x00` (invalid) for:
- Invalid mode identifier
- Incorrect public key size
- Incorrect signature size
- Failed signature verification
- Malformed input

No exceptions are thrown - all errors result in `0x00` output.

## Gas Optimization Tips

1. **Batch Verification**: Group multiple verifications to amortize overhead
2. **Off-chain Verification**: Verify off-chain when possible, only verify on-chain when necessary
3. **Signature Aggregation**: Use BLS or other aggregatable schemes when applicable
4. **Parameter Selection**: Use 128-bit security when 256-bit is not required

## Migration from Classical Signatures

When migrating from ECDSA to SLH-DSA:

1. **Storage**: Account for larger signatures in data structures
2. **Gas Costs**: Budget for higher verification costs
3. **Signing Infrastructure**: Update to support SLH-DSA key generation
4. **Backwards Compatibility**: Support both schemes during transition

## Testing

```bash
cd /Users/z/work/lux/standard
forge test --match-path "**/slhdsa/**"
```

## References

- [FIPS 205: Stateless Hash-Based Digital Signature Standard](https://csrc.nist.gov/pubs/fips/205/final)
- [SPHINCS+ Website](https://sphincs.org/)
- [Cloudflare CIRCL Library](https://github.com/cloudflare/circl)
- [NIST PQC Standardization](https://csrc.nist.gov/projects/post-quantum-cryptography)

## License

Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
See the file LICENSE for licensing terms.
