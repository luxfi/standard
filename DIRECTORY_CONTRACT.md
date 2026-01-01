# Directory Contract - Lux Standard

**Version**: 1.0.0
**Date**: 2025-12-31

This document defines where code lives, what it may depend on, and the only allowed import paths for Lux Solidity.

---

## Goals

- **ONE PATH**: Every contract has exactly one canonical location - no aliases, no shims, no legacy paths
- **One import namespace**: `@luxfi/contracts/...` - the ONLY way to import
- **Single home** for each concern: precompiles, interfaces, integrations, implementations
- **No compatibility layers**: If it moved, the old path is deleted - period

---

## Import Rules (Hard Requirements)

### 1. Lux ↔ Lux imports always use `@luxfi/contracts/...`

No relative `../` imports across modules (allowed only inside a file's local subfolder if absolutely necessary).

```solidity
import {StableSwap} from "@luxfi/contracts/amm/StableSwap.sol";
import {IOracleSource} from "@luxfi/contracts/oracle/interfaces/IOracleSource.sol";
import {IFHE} from "@luxfi/contracts/precompile/interfaces/IFHE.sol";
```

### 2. Precompile bindings are flat under `/precompile`

No "kernel/" paths. All precompile interfaces/libs/addresses live under:
- `@luxfi/contracts/precompile/interfaces/*`
- `@luxfi/contracts/precompile/libs/*`
- `@luxfi/contracts/precompile/addresses/*`
- `@luxfi/contracts/precompile/errors/*`

---

## Canonical Folders and What Goes Where

### `contracts/precompile/` (vendored; source-of-truth is lux/precompile)

**Purpose**: Solidity interfaces + libs + address/capabilities for precompiles.

**Rules**:
- Do not implement application logic here
- No dependencies on amm/, markets/, perps/, etc.
- Only tiny helpers (staticcall/call wrappers, address resolver, capability detection)

**Required substructure**:
```
precompile/
├── interfaces/     # IFHE.sol, IMLDSA.sol, IWarp.sol, etc.
├── libs/           # Helper libraries
├── addresses/      # Address constants
├── errors/         # Shared precompile errors
└── utils/          # Capability detection, etc.
```

---

### `contracts/interfaces/` (the standard surface)

**Purpose**: Canonical interfaces + events that wallets/indexers integrate once.

**Rules**:
- No storage, no concrete implementations
- Imports limited to other interfaces + minimal shared types

**Must include**:
```
interfaces/
├── analytics/      # Canonical events
├── oracle/         # IOracle, IOracleSource, IOracleWriter
├── amm/            # IAMMV2, IAMMV3, IStableSwap
├── markets/        # IMarkets, IRateModel
├── perps/          # IVault, IRouter, IPositionRouter
├── options/        # IOptions
├── vaults/         # IVault, IStrategy
├── bridge/         # IBridge, IBridgedToken
├── account/        # IAccount, IERC4337
├── governance/     # IGovernor, IVotingWeight
├── streaming/      # IStreams
├── insurance/      # ICover
└── prediction/     # IOracle (prediction), IClaims, IResolver
```

---

### `contracts/integrations/` (single home for adapters)

**Purpose**: External protocol adapters + codecs (Chainlink/Pyth/Uniswap/Aave/etc.).

**Rules**:
- Thin wrappers only: encode/decode + semantic normalization + safety checks
- Must target `contracts/interfaces/*` where applicable
- Must register in a single AdapterRegistry (allowlist + version + metadata)

**Required structure**:
```
integrations/
├── oracles/        # Chainlink, Pyth, RedStone, Chronicle
├── dex/            # UniV2, UniV3, Curve, Balancer
├── lending/        # Aave, Compound, Morpho
├── bridges/        # LayerZero, Wormhole, Axelar, Across
├── automation/     # Keepers, Gelato-style hooks
└── mev/            # Private orderflow, relay hooks
```

**Deprecation rule**: Existing scattered adapter folders are frozen and replaced with forwarders into `integrations/` until removed.

---

## Module Folders (Implementations)

These remain implementation homes; new work should respect the layering above.

### Core DeFi Modules

| Folder | Purpose |
|--------|---------|
| `contracts/amm/` | AMM v2/v3 + StableSwap |
| `contracts/markets/` | Lending/borrowing markets, rate models |
| `contracts/perps/` | Perpetuals core + peripherals |
| `contracts/options/` | Options protocol |
| `contracts/yield/` | Vaults + strategies |
| `contracts/streaming/` | Streaming/vesting |
| `contracts/prediction/` | Optimistic resolution + claims + resolver |
| `contracts/insurance/` | Cover pools + claims process |

### Protocol Plumbing

| Folder | Purpose |
|--------|---------|
| `contracts/oracle/` | Unified oracle, registry, sources |
| `contracts/bridge/` | Bridge tokens + infrastructure |
| `contracts/omnichain/` | Cross-chain messaging |
| `contracts/liquidity/` | Routing infrastructure |
| `contracts/account/` | Smart accounts |
| `contracts/safe/` | Multi-sig safes |
| `contracts/governance/` | Governor, voting, gauges |
| `contracts/treasury/` | Fee distribution |
| `contracts/registry/` | Service registries |

### Crypto/Compute Primitives (app-level)

| Folder | Purpose |
|--------|---------|
| `contracts/fhe/` | Contract-side FHE utilities (calls precompile/) |
| `contracts/crypto/` | App-level crypto helpers (PQ wrappers call precompile/) |

### Other Verticals

| Folder | Purpose |
|--------|---------|
| `contracts/identity/` | DID registry |
| `contracts/ai/` | AI mining/attestation |
| `contracts/nft/` | NFT utilities |
| `contracts/lssvm/` | NFT AMM (sudoswap-style) |
| `contracts/tokens/` | Token standards (LRC20, LRC721, etc.) |

### Support

| Folder | Purpose |
|--------|---------|
| `contracts/utils/` | Shared utilities |
| `contracts/multicall/` | Batch calls |
| `contracts/mocks/` | Test mocks |

---

## Dependency Rules (What May Import What)

**Allowed direction** (top → bottom):

```
amm/ markets/ perps/ options/ yield/ streaming/ prediction/ insurance/ ...
    ↓
may import: interfaces/, precompile/, integrations/, utils/, tokens/, registry/
```

**Forbidden**:
- `interfaces/` importing implementations
- `precompile/` importing anything outside `precompile/`
- `integrations/` importing application implementations (adapters must stay thin)

---

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Interfaces | `IThing.sol` | `IOracle.sol`, `IVault.sol` |
| Adapters | `ThingAdapter*.sol` | `ChainlinkAdapter.sol` |
| Registries | `*Registry.sol` | `AdapterRegistry.sol` |
| Oracle providers | `*Source.sol` | `TWAPSource.sol` |
| Strategies | `*Strategy.sol` | `AaveStrategy.sol` |
| Routers | `*Router.sol` | `IntentRouter.sol` |

---

## Precompile Vendoring Rule

`contracts/precompile/**` is a mirror of:
```
lux/precompile/solidity/precompile/**
```

- Changes to Solidity bindings happen in `lux/precompile` first
- `lux/standard` vendors those files (subtree/submodule/CI sync)
- `@luxfi/contracts/precompile/...` is the only supported public path

---

## Standard Compliance Checklist for New Modules

Every new public module should include:

- [ ] A matching interface in `contracts/interfaces/...`
- [ ] Canonical events in `interfaces/analytics/` (or reuse existing ones)
- [ ] Clear error taxonomy (shared errors where possible)
- [ ] Fuzz + invariants where relevant (AMMs/markets/options/stablecoin/settlement)

---

## Final Structure

### Precompile Bindings (`contracts/precompile/`)

```
precompile/
├── interfaces/
│   ├── IMLDSA.sol        # ML-DSA post-quantum signatures
│   ├── IFROST.sol        # FROST threshold Schnorr
│   ├── ICGGMP21.sol      # CGGMP21 threshold ECDSA
│   ├── IWarp.sol         # Cross-chain messaging
│   ├── IQuasar.sol       # Quantum consensus
│   ├── IFHE.sol          # Fully homomorphic encryption
│   ├── IBLS.sol          # BLS signatures
│   ├── IRingtailThreshold.sol  # PQ threshold
│   ├── IMLKEM.sol        # ML-KEM key encapsulation
│   ├── IPQCrypto.sol     # Multi-PQ operations
│   ├── ISLHDSA.sol       # SLH-DSA signatures
│   ├── ILSS.sol          # Lux Secret Sharing
│   ├── ISecp256r1.sol    # P-256 curve
│   ├── IOracle.sol       # DEX oracle precompile
│   └── dex/              # DEX precompile interfaces
│       ├── IDEX.sol
│       ├── IHooks.sol
│       ├── IPoolManager.sol
│       └── ILRC20Minimal.sol
└── addresses/
    └── PrecompileRegistry.sol
```

### Public Interfaces (`contracts/interfaces/`)

```
interfaces/
├── amm/         # IStableSwap, IAMMV2, IAMMV3, ...
├── markets/     # IMarkets, IRateModel, ...
├── perps/       # IVault, IPositionRouter, ...
├── options/     # IOptions
├── streaming/   # IStreams
├── insurance/   # ICover
├── prediction/  # IOracle, IClaims, IResolver
├── oracle/      # IOracleSource, IOracleWriter
├── governance/  # IGovernor, IVotingWeight
├── bridge/      # IBridge
├── vaults/      # IYieldAdapter
├── safe/        # ISafe
├── identity/    # IDID
└── tokens/      # ILRC20, ILRC721
```

### External Integrations (`contracts/integrations/`)

```
integrations/
├── AdapterRegistry.sol   # Central registry for all adapters
├── oracles/
│   ├── ChainlinkAdapter.sol
│   ├── PythAdapter.sol
│   ├── RedStoneAdapter.sol
│   ├── ChronicleAdapter.sol
│   └── UniswapV3TWAPAdapter.sol
├── dex/
│   ├── UniswapV2Adapter.sol
│   ├── UniswapV3Adapter.sol
│   ├── UniswapV4Adapter.sol
│   ├── CurveAdapter.sol
│   ├── BalancerV2Adapter.sol
│   ├── OneInchAdapter.sol
│   ├── ZeroXAdapter.sol
│   ├── CoWAdapter.sol
│   ├── ParaSwapAdapter.sol
│   └── GMXYieldAdapter.sol
├── lending/
│   ├── AaveV3Adapter.sol
│   ├── CompoundAdapter.sol
│   ├── CompoundV3Adapter.sol
│   ├── MorphoAdapter.sol
│   ├── EulerAdapter.sol
│   └── SparkAdapter.sol
├── bridges/
│   ├── LayerZeroAdapter.sol
│   ├── WormholeAdapter.sol
│   ├── AxelarAdapter.sol
│   ├── AcrossAdapter.sol
│   └── AsterAdapter.sol
├── automation/
│   ├── GelatoAdapter.sol
│   └── KeeperRegistryAdapter.sol
├── mev/
│   ├── PrivateTxAdapter.sol
│   └── FlashbotsAdapter.sol
└── rwa/
    └── RWAYieldAdapter.sol
```

---

## FHE Special Case

FHE contracts live in `contracts/fhe/` but the core interface `IFHE.sol` should be vendored to `contracts/precompile/interfaces/IFHE.sol` since it's a precompile binding.

Application-level FHE utilities (ConfidentialERC20, etc.) stay in `contracts/fhe/`.

---

## Migration Completion Status (2025-12-31)

### Phase Validation Results

| Phase | Validation | Status |
|-------|------------|--------|
| **Phase 1** | `test -d contracts/precompile && test -d contracts/interfaces && test -d contracts/integrations` | ✅ PASS |
| **Phase 2** | 20 files in `contracts/precompile/` | ✅ PASS |
| **Phase 3** | 114 interfaces in `contracts/interfaces/` | ✅ PASS |
| **Phase 4** | 10 adapters in `contracts/integrations/` + AdapterRegistry | ✅ PASS |
| **Phase 5** | 5 new module interfaces created | ✅ PASS |

### Import Path Status

| Metric | Count |
|--------|-------|
| Relative imports remaining | 0 |
| Raw `contracts/` imports | 0 |
| `@luxfi/contracts/` imports | Ready (remapping configured) |

### Foundry Remappings

```toml
remappings = [
    "@luxfi/contracts/=contracts/",
]
```

### NPM Export Intent

- `@luxfi/contracts/*` resolves to `contracts/*` at build/install time
- Package name: `@luxfi/contracts`
- Entry point: `contracts/`

### Adapter Registry

Created `contracts/integrations/AdapterRegistry.sol` with:
- Version tracking
- Allowlist management
- Category-based organization (ORACLE, DEX, LENDING, BRIDGE, PERPS, AUTOMATION, MEV, RWA)
- Status tracking (ACTIVE, INACTIVE, DEPRECATED)

### Files Summary

| Location | Count | Description |
|----------|-------|-------------|
| `contracts/precompile/` | 20 | Precompile interfaces (IMLDSA, IWarp, IFHE, etc.) |
| `contracts/interfaces/` | 114 | Canonical public interfaces |
| `contracts/integrations/` | 32 | External protocol adapters + registry |

**Old paths deleted**: `crypto/precompiles/`, `liquidity/precompiles/`, `oracle/adapters/`, `liquidity/evm/`, `core/adapters/`, `adapters/` - these no longer exist

---

*Last Updated: 2025-12-31*
