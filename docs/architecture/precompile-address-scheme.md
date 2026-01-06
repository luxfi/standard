# Lux Precompile Address Scheme

**Version**: 2.0 (Structured Namespace)  
**Date**: 2026-01-03  
**Status**: Canonical

## Overview

All Lux-native precompiles live in a **64K address block** starting at:

```
BASE = 0x0000000000000000000000000000000000010000
```

Each address is `BASE + selector` where the **16-bit selector** encodes:

```
0x P C II
   │ │ └┴─ Item/function (8 bits, 256 items per family×chain)
   │ └──── Chain slot    (4 bits, 16 chains max, 11 assigned)
   └────── Family page   (4 bits, using Fibonacci-ish: 1,2,3,5,8,D,F)
```

## Chain Slots (C nibble)

| C | Chain | Type | Chain ID | Purpose |
|---|-------|------|----------|---------|
| 0 | P | Primary | - | Platform, validators, staking |
| 1 | X | Primary | - | UTXO asset exchange |
| 2 | C | Primary | 96369 | EVM smart contracts (main) |
| 3 | Q | Infra | - | Quantum finality (Quasar) |
| 4 | A | Infra | - | Attestation, AI mining |
| 5 | B | Infra | - | Bridge hub |
| 6 | Z | Privacy | - | Zero-knowledge, dark pools |
| 7 | M | Reserved | - | Future expansion |
| 8 | Zoo | Subnet | 200200 | DeFi/NFT apps |
| 9 | Hanzo | Subnet | 36963 | AI compute |
| A | SPC | Subnet | 36911 | Gaming/metaverse |
| B-F | - | Reserved | - | Future chains |

## Family Pages (P nibble)

Aligned 1:1 with LP numbering scheme (LP-0099):

| P | Family | Chain | Description | LP Range |
|---|--------|-------|-------------|----------|
| 0 | **Reserved** | - | Reserved for system | LP-0xxx |
| 1 | **Foundation** | P-Chain | Staking, validators, consensus | LP-1xxx |
| 2 | **PQ Identity** | Q-Chain | Post-quantum keys, signatures | LP-2xxx |
| 3 | **EVM** | C-Chain | Hashing, encryption, standards | LP-3xxx |
| 4 | **Privacy** | Z-Chain | ZK proofs, FHE, privacy protocols | LP-4xxx |
| 5 | **Threshold** | T-Chain | MPC, DKG, custody, secret sharing | LP-5xxx |
| 6 | **Bridges** | B-Chain | Cross-chain, Warp, teleport | LP-6xxx |
| 7 | **AI** | A-Chain | Attestation, inference, provenance | LP-7xxx |
| 8 | **Governance** | - | DAO, voting, ESG | LP-8xxx |
| 9 | **DEX/Markets** | - | AMM, orderbook, oracle | LP-9xxx |
| A-F | **Reserved** | - | Future expansion | - |

**Key Insight**: P nibble = LP range first digit. `0x4XXX` addresses → LP-4xxx docs.

---

## Page 2: PQ Identity - Q-Chain (0x2CII) → LP-2xxx

### Post-Quantum Signatures (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Standard |
|----|------|---------------|---------------|----------|
| 01 | ML-DSA | `0x12201` | `0x12301` | FIPS 204 |
| 02 | ML-KEM | `0x12202` | `0x12302` | FIPS 203 |
| 03 | SLH-DSA | `0x12203` | `0x12303` | FIPS 205 |
| 04 | Falcon | `0x12204` | `0x12304` | NIST Round 3 |
| 05 | Dilithium | `0x12205` | `0x12305` | CRYSTALS |

### PQ Key Exchange (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 10 | Kyber | `0x12210` | `0x12310` | CRYSTALS-Kyber |
| 11 | NTRU | `0x12211` | `0x12311` | NTRUEncrypt |
| 12 | McEliece | `0x12212` | `0x12312` | Code-based |

### Hybrid Modes (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 20 | HybridSign | `0x12220` | `0x12320` | ECDSA + ML-DSA |
| 21 | HybridKEM | `0x12221` | `0x12321` | X25519 + Kyber |
| 22 | HybridAddr | `0x12222` | `0x12322` | Dual address |

---

## Page 3: EVM/Crypto - C-Chain (0x3CII) → LP-3xxx

### Hashing (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 01 | Poseidon2 | `0x13201` | `0x13601` | ZK-friendly hash |
| 02 | Poseidon2Sponge | `0x13202` | `0x13602` | Variable-length |
| 03 | Blake3 | `0x13203` | `0x13603` | High-performance |
| 04 | Pedersen | `0x13204` | `0x13604` | BN254 commitment |
| 05 | MiMC | `0x13205` | `0x13605` | SNARK-friendly |
| 06 | Rescue | `0x13206` | `0x13606` | Rescue hash |

### Classical Signatures (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 10 | ECDSA | `0x13210` | `0x13310` | secp256k1 verify |
| 11 | Ed25519 | `0x13211` | `0x13311` | Edwards curve |
| 12 | BLS12-381 | `0x13212` | `0x13312` | Pairing-friendly |
| 13 | Schnorr | `0x13213` | `0x13313` | BIP-340 compatible |

### Encryption (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 20 | AES-GCM | `0x13220` | `0x13620` | Authenticated |
| 21 | ChaCha20-Poly1305 | `0x13221` | `0x13621` | Stream cipher |
| 22 | HPKE | `0x13222` | `0x13622` | Hybrid public key |
| 23 | ECIES | `0x13223` | `0x13623` | EC integrated |

---

## Page 4: Privacy/ZK - Z-Chain (0x4CII) → LP-4xxx

### SNARKs (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 01 | Groth16 | `0x14201` | `0x14601` | Smallest proofs |
| 02 | PLONK | `0x14202` | `0x14602` | Universal setup |
| 03 | fflonk | `0x14203` | `0x14603` | Fast verification |
| 04 | Halo2 | `0x14204` | `0x14604` | Recursive |
| 05 | Nova | `0x14205` | `0x14605` | Folding scheme |

### STARKs (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 10 | STARK | `0x14210` | `0x14610` | Single proof |
| 11 | STARKRecursive | `0x14211` | `0x14611` | Recursive |
| 12 | STARKBatch | `0x14212` | `0x14612` | Batch verify |
| 1F | STARKReceipts | `0x1421F` | `0x1461F` | Cross-chain |

### Commitments (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 20 | KZG | `0x14220` | `0x14620` | Polynomial (EIP-4844) |
| 21 | IPA | `0x14221` | `0x14621` | Inner product |
| 22 | FRI | `0x14222` | `0x14622` | Fast Reed-Solomon |

### Privacy Primitives (II = 0x30-0x3F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 30 | RangeProof | `0x14230` | `0x14630` | Bulletproofs |
| 31 | Nullifier | `0x14231` | `0x14631` | Double-spend |
| 32 | Commitment | `0x14232` | `0x14632` | Note commitment |
| 33 | MerkleProof | `0x14233` | `0x14633` | Membership |

### FHE (II = 0x40-0x4F)

| II | Name | C=2 (C-Chain) | C=6 (Z-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 40 | FHE | `0x14240` | `0x14640` | Core operations |
| 41 | TFHE | `0x14241` | `0x14641` | Fast bootstrapping |
| 42 | CKKS | `0x14242` | `0x14642` | Approximate |
| 43 | BGV | `0x14243` | `0x14643` | Exact integer |
| 44 | Gateway | `0x14244` | `0x14644` | Decryption oracle |
| 45 | TaskManager | `0x14245` | `0x14645` | Async FHE tasks |

---

## Page 5: Threshold/MPC - T-Chain (0x5CII) → LP-5xxx

### Threshold Signatures (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 01 | FROST | `0x15201` | `0x15301` | Schnorr threshold |
| 02 | CGGMP21 | `0x15202` | `0x15302` | ECDSA threshold |
| 03 | Ringtail | `0x15203` | `0x15303` | PQ lattice threshold |
| 04 | Doerner | `0x15204` | `0x15304` | 2-of-n OT-based |
| 05 | BLSThreshold | `0x15205` | `0x15305` | BLS t-of-n |

### Secret Sharing (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 10 | LSS | `0x15210` | `0x15310` | Lux Secret Sharing |
| 11 | Shamir | `0x15211` | `0x15311` | Shamir's scheme |
| 12 | Feldman | `0x15212` | `0x15312` | Verifiable SS |

### DKG/Custody (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=3 (Q-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 20 | DKG | `0x15220` | `0x15320` | Distributed keygen |
| 21 | Refresh | `0x15221` | `0x15321` | Key rotation |
| 22 | Recovery | `0x15222` | `0x15322` | Social recovery |

---

## Page 6: Bridges - B-Chain (0x6CII) → LP-6xxx

### Warp Messaging (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=5 (B-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 01 | WarpSend | `0x16201` | `0x16501` | Send message |
| 02 | WarpReceive | `0x16202` | `0x16502` | Receive/verify |
| 03 | WarpReceipts | `0x16203` | `0x16503` | Receipt proofs |

### Token Bridges (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=5 (B-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 10 | Bridge | `0x16210` | `0x16510` | Token bridge |
| 11 | Teleport | `0x16211` | `0x16511` | Fast finality |
| 12 | BridgeRouter | `0x16212` | `0x16512` | Multi-chain route |

### Fee Collection (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=5 (B-Chain) | Description |
|----|------|---------------|---------------|-------------|
| 20 | FeeCollect | `0x16220` | `0x16520` | Fee aggregation |
| 21 | FeeGov | `0x16221` | `0x16521` | Fee governance |

---

## Page 7: AI - A-Chain (0x7CII) → LP-7xxx

### Attestation (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=4 (A-Chain) | C=9 (Hanzo) |
|----|------|---------------|---------------|-------------|
| 01 | GPUAttest | `0x17201` | `0x17401` | `0x17901` |
| 02 | TEEVerify | `0x17202` | `0x17402` | `0x17902` |
| 03 | NVTrust | `0x17203` | `0x17403` | `0x17903` |
| 04 | SGXAttest | `0x17204` | `0x17404` | `0x17904` |
| 05 | TDXAttest | `0x17205` | `0x17405` | `0x17905` |

### Inference (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=4 (A-Chain) | C=9 (Hanzo) |
|----|------|---------------|---------------|-------------|
| 10 | Inference | `0x17210` | `0x17410` | `0x17910` |
| 11 | Provenance | `0x17211` | `0x17411` | `0x17911` |
| 12 | ModelHash | `0x17212` | `0x17412` | `0x17912` |

### Mining (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=4 (A-Chain) | C=9 (Hanzo) |
|----|------|---------------|---------------|-------------|
| 20 | Session | `0x17220` | `0x17420` | `0x17920` |
| 21 | Heartbeat | `0x17221` | `0x17421` | `0x17921` |
| 22 | Reward | `0x17222` | `0x17422` | `0x17922` |

---

## Page 9: DEX/Markets (0x9CII) → LP-9xxx

### Core AMM (II = 0x01-0x0F)

| II | Name | C=2 (C-Chain) | C=8 (Zoo) | Description |
|----|------|---------------|-----------|-------------|
| 01 | PoolManager | `0x19201` | `0x19801` | Uniswap v4 singleton |
| 02 | SwapRouter | `0x19202` | `0x19802` | Optimized routing |
| 03 | HooksRegistry | `0x19203` | `0x19803` | Hook contracts |
| 04 | FlashLoan | `0x19204` | `0x19804` | Flash accounting |

### Orderbook (II = 0x10-0x1F)

| II | Name | C=2 (C-Chain) | C=8 (Zoo) | Description |
|----|------|---------------|-----------|-------------|
| 10 | CLOB | `0x19210` | `0x19810` | Central limit |
| 11 | Orderbook | `0x19211` | `0x19811` | Order storage |
| 12 | Matching | `0x19212` | `0x19812` | Match engine |

### Oracle (II = 0x20-0x2F)

| II | Name | C=2 (C-Chain) | C=8 (Zoo) | Description |
|----|------|---------------|-----------|-------------|
| 20 | OracleHub | `0x19220` | `0x19820` | Price aggregator |
| 21 | TWAP | `0x19221` | `0x19821` | Time-weighted |
| 22 | FastPrice | `0x19222` | `0x19822` | Low-latency |

### Perps (II = 0x30-0x3F)

| II | Name | C=2 (C-Chain) | C=8 (Zoo) | Description |
|----|------|---------------|-----------|-------------|
| 30 | Vault | `0x19230` | `0x19830` | LLP vault |
| 31 | PositionRouter | `0x19231` | `0x19831` | Positions |
| 32 | PriceFeed | `0x19232` | `0x19832` | Perp oracle |

---

## Address Calculation

```solidity
// Calculate full address from (P, C, II)
function precompileAddress(uint8 P, uint8 C, uint8 II) pure returns (address) {
    require(P < 16 && C < 16, "Invalid nibble");
    uint256 selector = (uint256(P) << 12) | (uint256(C) << 8) | uint256(II);
    return address(uint160(0x10000 + selector));
}

// Examples:
// Poseidon2 on C-Chain:  P=1, C=2, II=01 → 0x11201
// FROST on Q-Chain:      P=3, C=3, II=01 → 0x13301
// PoolManager on C-Chain: P=8, C=2, II=01 → 0x18201
// WarpSend on B-Chain:   P=D, C=5, II=01 → 0x1D501
```

## Reserved Ranges

The full range `0x10000` to `0x1FFFF` is reserved for Lux precompiles:

```go
// In registerer.go
{
    Start: common.HexToAddress("0x0000000000000000000000000000000000010000"),
    End:   common.HexToAddress("0x000000000000000000000000000000000001ffff"),
}
```

## Legacy Allocations (Pre-v2)

The following address ranges were allocated before the v2 structured namespace. These are documented for migration planning and backwards compatibility.

### HIGH-BYTE Scheme (LP-9015)

Lux stateful precompiles using 20-byte prefix:

```
0x0200000000000000000000000000000000000XXX
```

| Address | Name | LP | Status |
|---------|------|-----|--------|
| `0x0200...0001` | DeployerAllowList | LP-9015 | Active |
| `0x0200...0002` | TxAllowList | LP-9015 | Active |
| `0x0200...0003` | FeeManager | LP-9015 | Active |
| `0x0200...0004` | NativeMinter | LP-9015 | Active |
| `0x0200...0005` | Warp | LP-9015 | Active |
| `0x0200...0006` | RewardManager | LP-9015 | Active |
| `0x0200...0007` | ML-DSA | LP-3520 | Active |
| `0x0200...0008` | SLH-DSA | LP-3520 | Active |
| `0x0200...0009` | PQCrypto | LP-3520 | Active |
| `0x0200...000A` | Quasar | LP-3520 | Active |
| `0x0200...000B` | Ringtail | LP-3520 | Active |
| `0x0200...000C` | FROST | LP-321 | Active |
| `0x0200...000D` | CGGMP21 | LP-322 | Active |
| `0x0200...0010` | DEX | LP-9010 | Active |

### LOW-BYTE Scheme (Per-Chain)

#### Standard Ethereum (0x01-0x11)

| Address | Name | EIP | Notes |
|---------|------|-----|-------|
| `0x01` | ecRecover | EIP-155 | ECDSA recovery |
| `0x02` | SHA256 | EIP-155 | SHA-256 |
| `0x03` | RIPEMD160 | EIP-155 | RIPEMD-160 |
| `0x04` | Identity | EIP-155 | Data copy |
| `0x05` | ModExp | EIP-198 | Modular exponentiation |
| `0x06` | ECADD | EIP-196 | BN254 add |
| `0x07` | ECMUL | EIP-196 | BN254 scalar mul |
| `0x08` | ECPAIRING | EIP-197 | BN254 pairing |
| `0x09` | Blake2F | EIP-152 | BLAKE2b compression |
| `0x0A` | Point Evaluation | EIP-4844 | KZG (Dencun) |
| `0x0B-0x11` | BLS12-381 | EIP-2537 | Prague (planned) |

#### FHE (0x0080-0x0083)

| Address | Name | LP | Notes |
|---------|------|-----|-------|
| `0x0080` | FHE | LP-3520 | Core FHE operations |
| `0x0081` | Cofhe | LP-3520 | Co-FHE processor |
| `0x0082` | FheOps | LP-3520 | FHE operations |
| `0x0083` | TaskManager | LP-3520 | Async FHE tasks |

#### ZK Hashes (0x0500+)

| Address | Name | LP | Notes |
|---------|------|-----|-------|
| `0x0501` | Poseidon2 | LP-3520 | ZK-friendly hash |
| `0x0502` | Poseidon2Sponge | LP-3520 | Variable-length |
| `0x0503` | Pedersen | LP-3520 | BN254 commitment |
| `0x0504` | Blake3 | LP-3520 | High-performance |

#### STARK Proofs (0x0510-0x051F)

| Address | Name | LP | Notes |
|---------|------|-----|-------|
| `0x0510` | STARKVerify | LP-4000 | Single proof |
| `0x0511` | STARKRecursive | LP-4000 | Recursive |
| `0x0512` | STARKBatch | LP-4000 | Batch verify |
| `0x051F` | STARKReceipts | LP-4000 | Cross-chain |

#### Z-Chain ZKVM (0x8000-0x8006) - LP-4000

| Address | Name | Gas | Notes |
|---------|------|-----|-------|
| `0x8000` | Groth16Verify | 200,000 | Smallest proofs |
| `0x8001` | PLONKVerify | 250,000 | Universal setup |
| `0x8002` | STARKVerify | 500,000 | PQ-safe |
| `0x8003` | PoseidonHash | 10,000 | ZK-friendly |
| `0x8004` | PedersenCommit | 20,000 | Commitment |
| `0x8005` | FHEAdd | 50,000 | Encrypted add |
| `0x8006` | FHEMul | 100,000 | Encrypted mul |

#### Z-Chain TEE/FHE (0xF020-0xF022) - LP-4045

| Address | Name | Notes |
|---------|------|-------|
| `0xF020` | TEEAttest | TEE attestation |
| `0xF021` | FHEGateway | Decryption oracle |
| `0xF022` | ConfidentialSwap | Private DEX |

### LP Numbering Scheme (Reference)

Per LP-0099, LP numbers follow this taxonomy:

| Range | Category | Example |
|-------|----------|---------|
| 0xxx | Meta/Process | LP-0099 (Numbering) |
| 1xxx | Core Protocol | LP-1001 (Consensus) |
| 2xxx | Virtual Machines | LP-2000 (AI Token) |
| 3xxx | Cryptography | LP-3520 (Precompiles) |
| 4xxx | Privacy | LP-4000 (Z-Chain) |
| 5xxx | Networking | LP-5xxx |
| 6xxx | Storage | LP-6xxx |
| 7xxx | Identity | LP-7xxx |
| 8xxx | Governance | LP-8xxx |
| 9xxx | Markets/DEX | LP-9010 (DEX Precompile) |

**Note**: LP-9xxx is the LP *number* for Markets/DEX documentation, not a precompile address range.

---

## Migration from Legacy Addresses

### Complete Migration Table

| Legacy Address | New Address | Name | Notes |
|----------------|-------------|------|-------|
| `0x0080` | `0x13210` | FHE | Core ops → C-Chain |
| `0x0081` | `0x13211` | Cofhe/TFHE | → C-Chain |
| `0x0082` | `0x13212` | CKKS | → C-Chain |
| `0x0083` | `0x13215` | TaskManager | → C-Chain |
| `0x0300` | `0x15401` | AI Mining | → A-Chain |
| `0x0400` | `0x18201` | DEX PoolManager | → C-Chain |
| `0x0501` | `0x11201` | Poseidon2 | → C-Chain |
| `0x0502` | `0x11202` | Poseidon2Sponge | → C-Chain |
| `0x0503` | `0x11204` | Pedersen | → C-Chain |
| `0x0504` | `0x11203` | Blake3 | → C-Chain |
| `0x0510` | `0x12210` | STARK | → C-Chain |
| `0x0511` | `0x12211` | STARKRecursive | → C-Chain |
| `0x0512` | `0x12212` | STARKBatch | → C-Chain |
| `0x051F` | `0x1261F` | STARKReceipts | → Z-Chain |
| `0x8000` | `0x12601` | Groth16 | → Z-Chain |
| `0x8001` | `0x12602` | PLONK | → Z-Chain |
| `0x8002` | `0x12610` | STARK | → Z-Chain |
| `0x8003` | `0x11601` | Poseidon | → Z-Chain |
| `0x8004` | `0x11604` | Pedersen | → Z-Chain |
| `0x8005` | `0x13610` | FHEAdd | → Z-Chain |
| `0x8006` | `0x13610` | FHEMul | → Z-Chain (same) |
| `0xF020` | `0x15602` | TEEAttest | → Z-Chain |
| `0xF021` | `0x13614` | FHEGateway | → Z-Chain |
| `0xF022` | `0x18601` | ConfidentialSwap | → Z-Chain |
| `0x0200...0001` | - | DeployerAllowList | Keep (system) |
| `0x0200...0005` | `0x1D201` | Warp | → C-Chain |
| `0x0200...000C` | `0x13201` | FROST | → C-Chain |
| `0x0200...000D` | `0x13202` | CGGMP21 | → C-Chain |
| `0x0200...0010` | `0x18201` | DEX | → C-Chain |

### Migration Strategy

1. **Phase 1 (Soft)**: New v2 addresses active, legacy forwarded
2. **Phase 2 (Deprecation)**: Legacy addresses emit warning events
3. **Phase 3 (Removal)**: Legacy addresses removed (hard fork)

### Backwards Compatibility

For smooth transition, a **LegacyRouter** can forward calls:

```solidity
// Deployed at legacy address, forwards to new
contract LegacyRouter {
    function fallback() external {
        address newAddr = registry.getNewAddress(address(this));
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), newAddr, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
```

---

*Last Updated: 2026-01-03*
