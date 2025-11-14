# ML-DSA Precompile (FIPS 204)

Post-quantum digital signature verification precompile for Lux EVM.

## Overview

The ML-DSA (Module-Lattice-Based Digital Signature Algorithm) precompile provides quantum-resistant signature verification based on the Dilithium algorithm and standardized in FIPS 204.

**Precompile Address**: `0x0200000000000000000000000000000000000006`

## Features

- **Quantum Resistant**: Secure against attacks from both classical and quantum computers
- **NIST Standardized**: Implements FIPS 204 (ML-DSA-65)
- **High Performance**: ~108μs verification time on Apple M1
- **Security Level 3**: Equivalent to AES-192 security

## Specifications

### ML-DSA-65 Parameters

| Parameter | Value |
|-----------|-------|
| Public Key Size | 1952 bytes |
| Signature Size | 3309 bytes |
| Security Level | NIST Level 3 |
| Quantum Security | ~192 bits |

### Gas Costs

| Operation | Cost |
|-----------|------|
| Base Cost | 100,000 gas |
| Per Message Byte | 10 gas |

**Examples:**
- Empty message: 100,000 gas
- 100-byte message: 101,000 gas
- 1KB message: 110,240 gas
- 10KB message: 202,400 gas

## Input Format

The precompile expects a specific binary input format:

```
[Offset] [Size]   [Description]
0        1952     ML-DSA-65 public key
1952     32       Message length (uint256, big-endian)
1984     3309     ML-DSA-65 signature
5293     variable Message bytes
```

## Output Format

Returns a 32-byte word:
- `0x0000...0001` - Signature is **valid**
- `0x0000...0000` - Signature is **invalid**

## Usage

### Solidity

```solidity
// Interface
IMLDSA mldsa = IMLDSA(0x0200000000000000000000000000000000000006);
bool isValid = mldsa.verify(publicKey, message, signature);
require(isValid, "Invalid signature");

// Using library
using MLDSALib for bytes;

function verifyData(
    bytes calldata publicKey,
    bytes calldata data,
    bytes calldata signature
) external view {
    MLDSALib.verifyOrRevert(publicKey, data, signature);
    // Signature is valid
}

// Gas estimation
uint256 estimatedGas = MLDSALib.estimateGas(message.length);
```

### TypeScript/ethers.js

```typescript
import { ethers } from 'ethers';

const MLDSA_ADDRESS = '0x0200000000000000000000000000000000000006';

// ABI for the verify function
const abi = [
  'function verify(bytes calldata publicKey, bytes calldata message, bytes calldata signature) external view returns (bool)'
];

const mldsa = new ethers.Contract(MLDSA_ADDRESS, abi, provider);

// Verify signature
const isValid = await mldsa.verify(publicKey, message, signature);
console.log('Signature valid:', isValid);
```

### Go

```go
import (
    "github.com/luxfi/node/crypto/mldsa"
    "github.com/luxfi/evm/precompile/contracts/mldsa"
)

// Generate key pair
seed := make([]byte, 32)
sk, _ := mldsa.NewSigningKey(mldsa.ModeML_DSA_65, seed)
pk := sk.PublicKey()

// Sign message
message := []byte("Hello, quantum world!")
signature := sk.Sign(message, nil)

// Verify via precompile
input := prepareMLDSAInput(pk, message, signature)
result, gas, err := mldsa.MLDSAVerifyPrecompile.Run(
    nil, addr, addr, input, 200000, false,
)

valid := result[31] == 1 // Check last byte
```

## Performance Benchmarks

Measured on Apple M1 Max:

| Message Size | Verification Time | Gas Used |
|--------------|-------------------|----------|
| 18 bytes (small) | ~170μs | 100,180 |
| 10KB (large) | ~218μs | 202,400 |

**Memory Usage:**
- 33,314 bytes per operation
- 6 allocations per operation

## Security Considerations

1. **Quantum Resistance**: ML-DSA-65 provides Level 3 security (~192-bit quantum security)
2. **Side-Channel Protection**: Implementation uses constant-time operations
3. **FIPS 204 Compliance**: Follows NIST's standardized algorithm
4. **No Context Support**: Current implementation doesn't support context strings (passes empty context)

## Comparison with Other Algorithms

| Algorithm | Type | Signature Size | Verify Time | Quantum Secure |
|-----------|------|----------------|-------------|----------------|
| ECDSA (secp256k1) | Classical | 65 bytes | ~88μs | ❌ No |
| ML-DSA-65 | Post-Quantum | 3,309 bytes | ~108μs | ✅ Yes |
| SLH-DSA-128s | Post-Quantum | 7,856 bytes | ~4.2ms | ✅ Yes |

## Migration Guide

### From ECDSA to ML-DSA

```solidity
// Old ECDSA verification
bytes32 hash = keccak256(message);
address signer = ecrecover(hash, v, r, s);
require(signer == expectedSigner, "Invalid signature");

// New ML-DSA verification
IMLDSA mldsa = IMLDSA(0x0200000000000000000000000000000000000006);
bool valid = mldsa.verify(mldsaPublicKey, message, mldsaSignature);
require(valid, "Invalid ML-DSA signature");
```

## Testing

```bash
# Run unit tests
cd /Users/z/work/lux/evm/precompile/contracts/mldsa
go test -v

# Run benchmarks
go test -bench=. -benchmem

# Test with different message sizes
go test -v -run TestMLDSAVerify_LargeMessage
```

## References

- [FIPS 204: Module-Lattice-Based Digital Signature Standard](https://csrc.nist.gov/pubs/fips/204/final)
- [Dilithium Specification](https://pq-crystals.org/dilithium/)
- [Cloudflare CIRCL Library](https://github.com/cloudflare/circl)

## Related Precompiles

- **SLH-DSA** (`0x0200000000000000000000000000000000000007`): Hash-based signatures
- **ML-KEM** (`0x0200000000000000000000000000000000000008`): Post-quantum key encapsulation
- **PQCrypto** (`0x0200000000000000000000000000000000000005`): General post-quantum operations

## License

Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
