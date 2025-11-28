# Lux Precompiled Contracts

This directory contains all precompiled contracts (precompiles) for the Lux blockchain ecosystem. Precompiles are special smart contracts implemented natively in the node software for performance-critical operations that would be too expensive or slow to implement in Solidity.

## Overview

Precompiles are located at deterministic addresses starting from `0x0200000000000000000000000000000000000000`. They provide optimized implementations for cryptographic operations, cross-chain messaging, and chain configuration.

## Precompile Addresses

| Address | Name | Description | LP |
|---------|------|-------------|-----|
| `0x0200000000000000000000000000000000000001` | **DeployerAllowList** | Access control for contract deployment | LP-315 |
| `0x0200000000000000000000000000000000000002` | **TxAllowList** | Access control for transaction execution | LP-316 |
| `0x0200000000000000000000000000000000000003` | **FeeManager** | Dynamic fee configuration and management | LP-314 |
| `0x0200000000000000000000000000000000000004` | **NativeMinter** | Mint and burn native LUX tokens | LP-317 |
| `0x0200000000000000000000000000000000000005` | **RewardManager** | Validator reward distribution | LP-318 |
| `0x0200000000000000000000000000000000000006` | **ML-DSA** | Post-quantum signature verification (FIPS 204) | LP-311 |
| `0x0200000000000000000000000000000000000007` | **SLH-DSA** | Hash-based signature verification (FIPS 205) | LP-312 |
| `0x0200000000000000000000000000000000000008` | **Warp** | Cross-chain messaging and attestation | LP-313 |
| `0x0200000000000000000000000000000000000009` | **PQCrypto** | General post-quantum cryptography operations | LP-310 |
| `0x020000000000000000000000000000000000000A` | **Quasar** | Advanced consensus operations | LP-99 |
| `0x020000000000000000000000000000000000000B` | **Ringtail** | Lattice-based threshold signatures (LWE) | LP-320 |
| `0x020000000000000000000000000000000000000C` | **FROST** | Schnorr/EdDSA threshold signatures | LP-321 |
| `0x020000000000000000000000000000000000000D` | **CGGMP21** | ECDSA threshold signatures with aborts | LP-322 |
| `0x020000000000000000000000000000000000000E` | **Bridge** | Cross-chain bridge verification | LP-323 (Reserved) |

## Categories

### 1. Access Control Precompiles

These precompiles manage permissions for critical blockchain operations:

#### DeployerAllowList (`0x...0001`)
- **Purpose**: Control which addresses can deploy smart contracts
- **Use Case**: Enterprise/private chains with deployment restrictions
- **Gas Cost**: Minimal (configuration reads)
- **Documentation**: [deployerallowlist/](./deployerallowlist/)

#### TxAllowList (`0x...0002`)
- **Purpose**: Control which addresses can submit transactions
- **Use Case**: Permissioned blockchains, compliance requirements
- **Gas Cost**: Minimal (configuration reads)
- **Documentation**: [txallowlist/](./txallowlist/)

### 2. Economic Precompiles

These precompiles manage blockchain economics and tokenomics:

#### FeeManager (`0x...0003`)
- **Purpose**: Configure gas fees, base fees, and EIP-1559 parameters
- **Use Case**: Dynamic fee adjustment, custom fee models
- **Gas Cost**: Varies by operation
- **Documentation**: [feemanager/](./feemanager/)
- **LP**: [LP-314](../../lps/LPs/lp-314.md)

#### NativeMinter (`0x...0004`)
- **Purpose**: Mint and burn native LUX tokens
- **Use Case**: Bridging, wrapping/unwrapping, supply management
- **Gas Cost**: Proportional to amount
- **Documentation**: [nativeminter/](./nativeminter/)

#### RewardManager (`0x...0005`)
- **Purpose**: Distribute staking and validation rewards
- **Use Case**: Validator compensation, staking yields
- **Gas Cost**: Proportional to recipient count
- **Documentation**: [rewardmanager/](./rewardmanager/)

### 3. Post-Quantum Cryptography Precompiles

These precompiles provide quantum-resistant cryptographic operations per NIST FIPS standards:

#### ML-DSA (`0x...0006`)
- **Purpose**: Verify ML-DSA-65 signatures (FIPS 204 - Dilithium)
- **Security Level**: NIST Level 3 (192-bit equivalent)
- **Key Sizes**:
  - Public Key: 1,952 bytes
  - Signature: 3,309 bytes
- **Performance**: ~108μs verification on Apple M1
- **Gas Cost**: 100,000 base + 10 gas/byte of message
- **Use Cases**:
  - Quantum-safe transaction authorization
  - Cross-chain message authentication
  - Post-quantum multisig wallets
- **Documentation**: [mldsa/](./mldsa/)
- **LP**: [LP-311](../../lps/LPs/lp-311.md)
- **Solidity Interface**: [mldsa/IMLDSA.sol](./mldsa/IMLDSA.sol)

#### SLH-DSA (`0x...0007`)
- **Purpose**: Verify SLH-DSA signatures (FIPS 205 - SPHINCS+)
- **Security Level**: NIST Level 1-5 (128-256 bit)
- **Key Sizes** (SLH-DSA-128s):
  - Public Key: 32 bytes
  - Signature: 7,856 bytes
- **Performance**: ~286μs verification on Apple M1
- **Gas Cost**: 15,000 base + 10 gas/byte of message
- **Use Cases**:
  - Hash-based quantum-safe signatures
  - Long-term signature validity (archival)
  - Conservative post-quantum security
  - Firmware update verification
- **Documentation**: [slhdsa/](./slhdsa/)
- **LP**: [LP-312](../../lps/LPs/lp-312.md)
- **Solidity Interface**: [slhdsa/ISLHDSA.sol](./slhdsa/ISLHDSA.sol)

#### PQCrypto (`0x...0009`)
- **Purpose**: General post-quantum cryptography operations
- **Operations**:
  - ML-KEM-768 key encapsulation (FIPS 203)
  - Hybrid classical+PQ operations
  - Quantum-safe key exchange
- **Documentation**: [pqcrypto/](./pqcrypto/)
- **LP**: [LP-310](../../lps/LPs/lp-310.md) *(to be created)*

### 4. Interoperability Precompiles

These precompiles enable cross-chain communication and messaging:

#### Warp (`0x...0008`)
- **Purpose**: Cross-chain message signing and verification
- **Features**:
  - BLS signature aggregation
  - Validator attestations
  - Cross-chain asset transfers
- **Performance**: ~1.5ms per BLS verification
- **Gas Cost**: Variable based on validator set size
- **Use Cases**:
  - Cross-chain token transfers
  - Multi-chain contract calls
  - Subnet synchronization
- **Documentation**: [warp/](./warp/)
- **LP**: [LP-313](../../lps/LPs/lp-313.md) *(to be created)*

### 5. Threshold Signature Precompiles

Multi-party computation and threshold signatures for custody and consensus:

#### Ringtail (`0x...000B`)
- **Purpose**: Lattice-based threshold signature verification
- **Algorithm**: LWE-based two-round threshold scheme
- **Security**: Post-quantum (Ring Learning With Errors)
- **Gas Cost**: 150,000 base + 10,000 per party
- **Use Cases**:
  - Quantum-safe threshold wallets
  - Distributed validator signing
  - Post-quantum consensus
  - Multi-party custody
- **Documentation**: [ringtail/](./ringtail/)
- **LP**: [LP-320](../../lps/LPs/lp-320.md)

#### FROST (`0x...000C`)
- **Purpose**: Schnorr/EdDSA threshold signature verification
- **Algorithm**: FROST (Flexible Round-Optimized Schnorr Threshold)
- **Standards**: IETF FROST, BIP-340/341 (Taproot)
- **Gas Cost**: 50,000 base + 5,000 per signer
- **Signature Size**: 64 bytes (compact Schnorr)
- **Use Cases**:
  - Bitcoin Taproot multisig
  - Ed25519 threshold (Solana, Cardano, TON)
  - Schnorr aggregate signatures
  - Lightweight threshold custody
- **Documentation**: [frost/](./frost/)
- **LP**: [LP-321](../../lps/LPs/lp-321.md)

#### CGGMP21 (`0x...000D`)
- **Purpose**: Modern ECDSA threshold signature verification
- **Algorithm**: CGGMP21 with identifiable aborts
- **Security**: Detects malicious parties
- **Gas Cost**: 75,000 base + 10,000 per signer
- **Signature Size**: 65 bytes (standard ECDSA)
- **Use Cases**:
  - Ethereum threshold wallets
  - Bitcoin threshold multisig
  - MPC custody solutions
  - Enterprise key management
- **Documentation**: [cggmp21/](./cggmp21/)
- **LP**: [LP-322](../../lps/LPs/lp-322.md)

### 6. Consensus Precompiles

Advanced consensus and validation operations:

#### Quasar (`0x...000A`)
- **Purpose**: Advanced consensus operations for Quasar hybrid consensus
- **Features**:
  - Dual certificate verification (classical + PQ)
  - BLS signature aggregation
  - Hybrid BLS+ML-DSA verification
  - Verkle witness verification
- **Documentation**: [quasar/](./quasar/)
- **LP**: [LP-99](../../lps/LPs/lp-99.md)

## Implementation Structure

Each precompile directory contains:

```
<precompile-name>/
├── module.go          # Precompile module registration
├── contract.go        # Core precompile implementation
├── contract_test.go   # Go test suite
├── config.go          # Configuration structures (if applicable)
├── config_test.go     # Configuration tests
├── I<Name>.sol        # Solidity interface
├── contract.abi       # ABI definition (if applicable)
└── README.md          # Detailed documentation
```

## Development Guidelines

### Adding a New Precompile

1. **Choose an Address**: Select next available address in sequence
2. **Create Directory**: `mkdir -p src/precompiles/<name>`
3. **Implement Interface**: Must implement `StatefulPrecompiledContract`
4. **Write Tests**: Minimum 80% code coverage
5. **Create Solidity Interface**: Include full documentation
6. **Write LP**: Document specification in lps/LPs/
7. **Update This README**: Add to address table and category

### Required Interfaces

All precompiles must implement:

```go
type StatefulPrecompiledContract interface {
    // Address returns the precompile address
    Address() common.Address
    
    // RequiredGas calculates gas cost for input
    RequiredGas(input []byte) uint64
    
    // Run executes the precompile logic
    Run(
        accessibleState AccessibleState,
        caller common.Address,
        addr common.Address,
        input []byte,
        suppliedGas uint64,
        readOnly bool,
    ) ([]byte, uint64, error)
}
```

### Module Registration

Each precompile must provide a module for registration:

```go
type module struct {
    address  common.Address
    contract StatefulPrecompiledContract
}

func (m *module) Address() common.Address { 
    return m.address 
}

func (m *module) Contract() StatefulPrecompiledContract { 
    return m.contract 
}
```

### Gas Calculation Guidelines

Gas costs should reflect:
1. **Computational complexity**: Higher for crypto operations
2. **Memory usage**: Larger for big inputs/outputs
3. **State access**: More for state reads/writes
4. **Benchmarks**: Based on real performance measurements

Example gas formulas:
- **Simple state read**: ~2,000 gas
- **Cryptographic verification**: 50,000 - 500,000 gas
- **Per-byte processing**: 10 - 50 gas/byte
- **State writes**: ~20,000 gas per slot

## Testing Requirements

All precompiles must have:

1. **Unit Tests** (`contract_test.go`):
   - Valid input cases
   - Invalid input cases
   - Edge cases
   - Gas calculation verification

2. **Solidity Tests**:
   - Interface usage examples
   - Integration with other contracts
   - Gas benchmarks

3. **Benchmarks**:
   - Performance measurements
   - Gas cost validation
   - Comparison with pure Solidity implementation

## Security Considerations

### Input Validation
- **Always** validate input length before parsing
- Check for buffer overflows
- Validate all parameters against constraints

### Gas Limits
- Ensure gas costs prevent DoS attacks
- Test with maximum-size inputs
- Verify gas calculations don't overflow

### State Access
- Only modify state in non-read-only calls
- Validate caller permissions for privileged operations
- Ensure atomic state updates

### Cryptographic Operations
- Use constant-time implementations when possible
- Validate all cryptographic inputs
- Check signature/key sizes match expected values
- Test against known attack vectors

## Performance Benchmarks

Performance targets on Apple M1 (reference hardware):

| Operation | Target | Current |
|-----------|--------|---------|
| ML-DSA-65 Verify | < 150μs | ~108μs ✓ |
| SLH-DSA-192s Verify | < 20ms | ~15ms ✓ |
| BLS Signature Verify | < 2ms | ~1.5ms ✓ |
| State Read | < 5μs | ~2μs ✓ |
| State Write | < 10μs | ~5μs ✓ |

## Documentation Standards

Each precompile must document:

1. **Purpose and Use Cases**: Why it exists, when to use it
2. **Input/Output Format**: Exact byte layouts with examples
3. **Gas Costs**: Formula and examples
4. **Error Conditions**: All possible failure modes
5. **Security Considerations**: Potential vulnerabilities
6. **Examples**: Both Go and Solidity usage

## References

- **Lux Precompile Standards (LPS)**: [../lps/](../../lps/)
- **EVM Precompiles**: [../evm/](../../evm/)
- **Solidity Interfaces**: [./*/I*.sol](.)
- **NIST PQC Standards**: https://csrc.nist.gov/projects/post-quantum-cryptography

## License

Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
See the file [LICENSE](../../LICENSE) for licensing terms.
