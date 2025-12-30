# Lux Standard Contracts - Architecture Cleanup Plan

**Date**: 2025-12-26
**Version**: 1.0.0
**Author**: Senior Software Architect

---

## Executive Summary

This document provides a comprehensive analysis of the Lux Standard contracts directory, identifying duplications, typos, and architectural inconsistencies. It proposes a canonical structure and deployment order for a complete DeFi stack.

---

## Part 1: Identified Issues

### 1.1 Typos

| File | Issue | Fix |
|------|-------|-----|
| `contracts/tokens/GoveranceToken.sol` | Missing 'n' in "Governance" | Rename to `GovernanceToken.sol` |

### 1.2 Duplicate Governance Contracts

**Problem**: Two nearly identical Governor implementations exist:

| Contract | Location | Purpose |
|----------|----------|---------|
| `Governor.sol` | `contracts/governance/` | Generic OZ Governor wrapper |
| `LuxGovernor.sol` | `contracts/dao/governance/` | Lux-branded OZ Governor wrapper |

**Analysis**: Both contracts extend the exact same OZ modules:
- `GovernorSettings`
- `GovernorCountingSimple`
- `GovernorVotes`
- `GovernorVotesQuorumFraction`
- `GovernorTimelockControl`

The only differences:
- `Governor.sol` aliases OZGovernor to avoid name collision
- `LuxGovernor.sol` has Lux branding in comments
- Both have identical override implementations

**RECOMMENDATION**: Keep `contracts/governance/Governor.sol` as canonical. Delete `contracts/dao/governance/LuxGovernor.sol`.

### 1.3 Duplicate Voting Tokens

| Contract | Location | Purpose |
|----------|----------|---------|
| `GoveranceToken.sol` (typo) | `contracts/governance/` | Empty upgradeable placeholder |
| `VotesToken.sol` | `contracts/dao/governance/` | Full ERC20Votes implementation |
| `vLUX.sol` | `contracts/governance/` | Vote-escrowed LUX (Curve-style) |
| `DLUX.sol` | `contracts/governance/` | OHM-style rebasing governance |

**Analysis**: Four different governance token approaches coexist:
1. **Empty placeholder** (GoveranceToken.sol) - useless
2. **Standard ERC20Votes** (VotesToken.sol) - OpenZeppelin standard
3. **Vote-escrow model** (vLUX.sol) - Time-locked voting power
4. **Rebasing model** (DLUX.sol) - OHM-style with demurrage

**RECOMMENDATION**:
- DELETE `GoveranceToken.sol` (typo, empty placeholder)
- KEEP `VotesToken.sol` renamed to `LuxToken.sol` in `contracts/governance/`
- KEEP `vLUX.sol` - useful for gauge voting
- KEEP `DLUX.sol` - useful for protocol-owned liquidity

### 1.4 Duplicate Bridge Tokens

**Problem**: Two LETH contracts exist:

| Contract | Location | Implementation |
|----------|----------|----------------|
| `LETH.sol` | `contracts/bridge/` | Minimal (extends LRC20B, 14 lines) |
| `LETH.sol` | `contracts/bridge/lux/` | Adds explicit mint/burn (28 lines) |

**Analysis**:
- Root `contracts/bridge/LETH.sol` uses base class `bridgeMint`/`bridgeBurn`
- Subfolder `contracts/bridge/lux/LETH.sol` adds redundant `mint`/`burn` that call the same base methods

**RECOMMENDATION**: DELETE `contracts/bridge/LETH.sol` (root). KEEP `contracts/bridge/lux/LETH.sol` as canonical. The explicit mint/burn methods provide better code clarity.

Same pattern applies to all bridge tokens - consolidate to `contracts/bridge/lux/` and `contracts/bridge/zoo/` subdirectories.

### 1.5 Duplicate LRC20B Token Standards

**Problem**: Two LRC20B implementations exist:

| Contract | Location | Features |
|----------|----------|----------|
| `LRC20B.sol` | `contracts/bridge/` | Uses `LRC20` import from tokens, has `bridgeMint`/`bridgeBurn` |
| `LRC20B.sol` | `contracts/tokens/` | Uses `ERC20` directly, has `mint`/`burnIt` |

**Analysis**:
- Bridge version is more feature-complete (`bridgeMint`/`bridgeBurn` events)
- Tokens version uses awkward `burnIt` method name
- Bridge version imports `LRC20` from tokens (creates dependency)

**RECOMMENDATION**: CONSOLIDATE to `contracts/tokens/LRC20B.sol` as canonical. Update:
1. Rename `burnIt` to `burn`
2. Add `bridgeMint`/`bridgeBurn` aliases for compatibility
3. All bridge tokens import from `../tokens/LRC20B.sol`

### 1.6 LRC20 Token Standard Proliferation

**Problem**: Multiple LRC20 implementations with overlapping purposes:

| Contract | Location | Features |
|----------|----------|----------|
| `LRC20.sol` | `contracts/tokens/` | Minimal (just ERC20 wrapper) |
| `LRC20.sol` | `contracts/tokens/LRC20/` | Full-featured (Burnable, Pausable, Permit, Votes, FlashMint) |
| `LRC20Basic.sol` | `contracts/tokens/LRC20/` | Minimal + Ownable + mint |
| `LRC20Capped.sol` | `contracts/tokens/LRC20/` | Basic + max supply cap |

**RECOMMENDATION**: Establish clear token hierarchy:

```
contracts/tokens/
├── LRC20.sol                    # Base: Simple ERC20 wrapper (KEEP)
├── LRC20B.sol                   # Bridgeable: Admin mint/burn (CONSOLIDATE)
├── LRC20/
│   ├── LRC20Full.sol            # Rename from LRC20.sol - Full featured
│   ├── LRC20Basic.sol           # Minimal + owner mint (KEEP)
│   ├── LRC20Capped.sol          # Basic + cap (KEEP)
│   ├── LRC20Wrapper.sol         # Wrapping (KEEP)
│   ├── SafeLRC20.sol            # Safe transfer utils (KEEP)
│   └── extensions/
│       ├── LRC20Burnable.sol    # Burnable extension (KEEP)
│       ├── LRC20FlashMint.sol   # Flash mint (KEEP)
│       ├── LRC20Mintable.sol    # Mintable extension (KEEP)
│       └── LRC20Permit.sol      # EIP-2612 permit (KEEP)
```

---

## Part 2: Canonical Structure Proposal

### 2.1 Governance Stack (Single Implementation)

```
contracts/governance/
├── Governor.sol                 # CANONICAL - OZ Governor with all extensions
├── Timelock.sol                 # CANONICAL - OZ TimelockController wrapper
├── LuxToken.sol                 # CANONICAL - Renamed from VotesToken.sol
├── vLUX.sol                     # Vote-escrowed for gauges (Curve model)
├── DLUX.sol                     # Rebasing governance (OHM model)
├── GaugeController.sol          # Gauge weight voting
├── Vote.sol                     # Voting utilities
├── VotingPower.sol              # Power calculation
├── Karma.sol                    # Reputation tracking
├── Owned.sol                    # Simple ownership
└── interfaces/
    └── IVoting.sol

# DELETE:
# - contracts/dao/governance/LuxGovernor.sol (duplicate)
# - contracts/dao/governance/VotesToken.sol (move to governance/)
# - contracts/governance/GoveranceToken.sol (typo, empty)
# - contracts/governance/DAO.sol (move to dao/ if needed, or keep but rename)
# - contracts/governance/SafeGovernor.sol (keep - Safe-specific)
```

### 2.2 Token Standards (Consolidated)

```
contracts/tokens/
├── LRC20.sol                    # Base ERC20 wrapper
├── LRC20B.sol                   # Bridgeable (consolidated from bridge/)
├── LRC721B.sol                  # Bridgeable NFT
├── LRC1155B.sol                 # Bridgeable multi-token
├── WLUX.sol                     # Wrapped native LUX
├── LUX.sol                      # Native token interface
├── LUSD.sol                     # Lux USD (canonical stablecoin)
├── AI.sol                       # AI token
├── LRC20/
│   ├── LRC20Full.sol            # Full-featured with all extensions
│   ├── LRC20Basic.sol           # Minimal with owner mint
│   ├── LRC20Capped.sol          # With max supply
│   ├── LRC20Wrapper.sol         # Token wrapping
│   ├── SafeLRC20.sol            # Safe transfer library
│   └── extensions/              # Modular extensions
├── LRC721/
│   └── LRC721.sol               # Base NFT
├── LRC1155/
│   └── LRC1155.sol              # Base multi-token
├── LRC4626/
│   └── LRC4626.sol              # Vault standard
└── interfaces/
    ├── ILRC20.sol
    ├── ILRC721.sol
    └── ILRC1155.sol

# DELETE:
# - contracts/tokens/GoveranceToken.sol (typo, empty)
# - contracts/bridge/LRC20B.sol (use tokens/LRC20B.sol)
```

### 2.3 Bridge Tokens (Organized by Chain)

```
contracts/bridge/
├── Bridge.sol                   # Core bridge logic
├── BridgeVault.sol              # Vault for locked assets
├── ETHVault.sol                 # ETH-specific vault
├── Teleport.sol                 # Warp-based teleportation
├── XChainVault.sol              # Cross-chain vault
├── LERC4626.sol                 # ERC4626 vault variant
├── lux/                         # CANONICAL: Lux chain bridge tokens
│   ├── LETH.sol                 # Bridged ETH
│   ├── LBTC.sol                 # Bridged BTC
│   ├── LUSD.sol                 # Bridged USD
│   ├── LSOL.sol                 # Bridged SOL
│   ├── LTON.sol                 # Bridged TON
│   ├── LADA.sol                 # Bridged ADA
│   ├── LAVAX.sol                # Bridged AVAX
│   ├── LBNB.sol                 # Bridged BNB
│   ├── LPOL.sol                 # Bridged POL
│   ├── LZOO.sol                 # Bridged ZOO
│   └── ... (memecoins: LBONK, LPOPCAT, etc.)
├── zoo/                         # Zoo chain bridge tokens
│   ├── ZETH.sol
│   ├── ZBTC.sol
│   ├── ZUSD.sol
│   ├── ZLUX.sol                 # LUX bridged to Zoo
│   └── ... (memecoins: TRUMP, MELANIA, etc.)
├── yield/                       # Yield-bearing bridge tokens
│   ├── IYieldStrategy.sol
│   ├── YieldBearingBridgeToken.sol
│   ├── YieldBridgeConfig.sol
│   ├── YieldBridgeVault.sol
│   └── strategies/
│       ├── AaveV3Strategy.sol
│       ├── CompoundV3Strategy.sol
│       └── ... (other strategies)
└── interfaces/
    ├── IBridge.sol
    └── IWarpMessenger.sol

# DELETE:
# - contracts/bridge/LETH.sol (duplicate of lux/LETH.sol)
# - contracts/bridge/LRC20B.sol (moved to tokens/)
```

### 2.4 DAO Structure (Minimal)

```
contracts/dao/
└── # DELETE ENTIRE DIRECTORY
    # Move VotesToken.sol to governance/LuxToken.sol
    # LuxGovernor.sol is duplicate - delete
```

---

## Part 3: Full Stack Deployment Order

### Phase 1: Core Infrastructure (No Dependencies)

```solidity
// 1.1 Token Standards (deployed once, used by everything)
// Deploy order doesn't matter - no interdependencies
1. WLUX                          // Wrapped native LUX
2. LUSD                          // Lux USD stablecoin (bridge/)
3. LETH                          // Bridged ETH (bridge/lux/)
4. LBTC                          // Bridged BTC (bridge/lux/)

// 1.2 Multicall (useful for all operations)
5. Multicall2                    // Batch calls
```

### Phase 2: Identity (Foundation for DeFi)

```solidity
// 2.1 DID System
6. DIDRegistry                   // Core identity registry
7. DIDResolver                   // DID resolution
8. PremiumDIDRegistry            // Premium names (optional)
```

### Phase 3: NFT Infrastructure

```solidity
// 3.1 Core NFTs
9. GenesisNFTs                   // Protocol genesis NFTs

// 3.2 NFT Marketplace
10. Market                       // NFT marketplace

// 3.3 NFT AMM (LSSVM)
11. LinearCurve                  // Price curve
12. ExponentialCurve             // Price curve
13. LSSVMPairFactory             // Create pairs
14. LSSVMRouter                  // Trade routing
```

### Phase 4: Governance

```solidity
// 4.1 Governance Token
15. LuxToken                     // Renamed from VotesToken (ERC20Votes)
                                 // OR use existing LUX/AI token

// 4.2 Timelock
16. Timelock                     // 2-day minimum delay

// 4.3 Governor
17. Governor                     // OZ Governor with all extensions
    // Constructor args:
    // - token: LuxToken address
    // - timelock: Timelock address
    // - name: "Lux Governor"
    // - votingDelay: 7200 (1 day @ 12s blocks)
    // - votingPeriod: 50400 (7 days @ 12s blocks)
    // - proposalThreshold: 100000e18 (100k tokens)
    // - quorumPercentage: 4 (4%)

// 4.4 Vote Escrow (optional)
18. vLUX                         // Vote-escrowed LUX for gauges
19. GaugeController              // Gauge weight voting

// 4.5 Grant roles
// - Grant PROPOSER_ROLE to Governor on Timelock
// - Grant EXECUTOR_ROLE to address(0) on Timelock (anyone can execute)
// - Renounce admin on Timelock
```

### Phase 5: AMM Infrastructure

```solidity
// 5.1 AMM V2
20. AMMV2Factory                 // Create pairs
    // Constructor: feeToSetter address

21. AMMV2Router                  // Swap routing
    // Constructor: factory, WLUX

// 5.2 Initial Liquidity Pools
22. Create WLUX/LUSD pool        // Main trading pair
23. Create LETH/WLUX pool        // ETH pair
24. Create LBTC/WLUX pool        // BTC pair
```

### Phase 6: Lending Markets (Morpho-style)

```solidity
// 6.1 Oracle Infrastructure
25. ChainlinkOracle              // Price feeds
26. PythOracle                   // Alternative oracle

// 6.2 Rate Model
27. AdaptiveCurveRateModel       // Interest rate curve

// 6.3 Core Markets
28. Markets                      // Core lending protocol
    // Constructor: owner address

29. Allocator                    // Risk allocation
30. Router                       // Market routing

// 6.4 Configure Markets
// - Set oracle
// - Set rate model
// - Create markets (LUSD/LETH, LUSD/WLUX, etc.)
```

### Phase 7: Synths Protocol (Alchemix-style)

```solidity
// 7.1 Deploy Synth Tokens (s* prefix)
31. sUSD                         // Synthetic USD
32. sETH                         // Synthetic ETH
33. sBTC                         // Synthetic BTC
34. sLUX                         // Synthetic LUX
35. sAI                          // Synthetic AI
36. sSOL, sTON, sADA, sAVAX, sBNB, sPOL, sZOO  // Other synths

// 7.2 Core Protocol
37. SynthVault (AlchemistV2)     // Main vault
    // Initialize with synth tokens

38. TransmuterV2                 // 1:1 redemption
39. TransmuterBuffer             // Buffer management
40. SynthRedeemer                // Lux wrapper for transmuter

// 7.3 Yield Adapters
41. YearnTokenAdapter            // Yearn integration
42. YieldBridgeAdapter           // Bridge yield
43. sLUXAdapter                  // sLUX yield adapter

// 7.4 Create Synth LP Pools
44. WLUX/sLUX pool
45. LUSD/sUSD pool
46. LETH/sETH pool
47. LBTC/sBTC pool
```

### Phase 8: Perpetuals (GMX-style, renamed to LPX)

```solidity
// 8.1 Core Perps Infrastructure
48. LPUSD                        // Internal accounting stablecoin
49. LLP                          // Liquidity provider token
50. LPX                          // Protocol token
51. xLPX                         // Escrowed LPX

// 8.2 Oracle
52. VaultPriceFeed               // Price aggregator
53. FastPriceFeed                // Low-latency updates
54. FastPriceEvents              // Oracle events

// 8.3 Core Vault
55. Vault                        // Central liquidity pool
    // Configure:
    // - setFees
    // - setTokenConfig for whitelisted tokens
    // - setFundingRate
    
56. VaultUtils                   // Utility functions
57. VaultErrorController         // Error handling

// 8.4 Position Management
58. Router                       // User-facing router
59. PositionRouter               // Keeper-executed positions
60. PositionManager              // Position management
61. OrderBook                    // Limit orders
62. ShortsTracker                // Short position tracking

// 8.5 LP Management
63. LLPManager                   // Mint/burn LLP
    // Configure:
    // - setInPrivateMode(false)
    // - setHandler(PositionRouter)
    // - setHandler(PositionManager)

// 8.6 Staking & Rewards
64. RewardTracker (stakedLPX)    // Track staked LPX
65. RewardTracker (bonusLPX)     // Track bonus
66. RewardTracker (feeLPX)       // Track fee rewards
67. RewardDistributor            // Distribute rewards
68. BonusDistributor             // Bonus distribution
69. RewardRouter                 // Unified staking interface
70. Vester                       // xLPX to LPX conversion

// 8.7 Timelocks (Governance)
71. LPXTimelock                  // Protocol timelock
72. PriceFeedTimelock            // Oracle timelock
73. ShortsTrackerTimelock        // Shorts timelock

// 8.8 Referrals
74. ReferralStorage              // Referral tracking
```

### Phase 9: Treasury & Fee Distribution

```solidity
// 9.1 Fee Splitters
75. FeeSplitter                  // Protocol fee distribution
    // Configure recipients:
    // - Treasury: 50%
    // - Stakers: 30%
    // - Dev fund: 20%

76. SynthFeeSplitter             // Synths-specific fees

// 9.2 Validator Vault
77. ValidatorVault               // Validator rewards
```

### Phase 10: Safe Multisig Infrastructure

```solidity
// 10.1 Core Safe (from Safe Global)
// Usually deployed via CREATE2 factory - use existing deployments
78. Safe                         // Or SafeL2 for L2s
79. SafeProxyFactory             // Create Safe proxies
80. MultiSend                    // Batch transactions
81. CompatibilityFallbackHandler // Handler

// 10.2 Custom Safe Extensions
82. SafeFactory                  // Lux-specific factory
83. SafeModule                   // Base module
84. SafeGovernor                 // Governance module for Safe

// 10.3 Quantum-Safe Signers
85. SafeFROSTSigner              // FROST threshold signer
86. SafeFROSTCoSigner            // FROST co-signer
87. SafeCGGMP21Signer            // CGGMP21 threshold
88. SafeMLDSASigner              // ML-DSA quantum-safe
89. SafeRingtailSigner           // Ringtail threshold
90. SafeLSSSigner                // LSS signer

// 10.4 Specialized Modules
91. FROSTAccount                 // FROST-enabled account
92. QuantumSafe                  // Quantum-resistant Safe
```

### Phase 11: AI & Compute

```solidity
// 11.1 AI Token Infrastructure
93. AIToken                      // Core AI token
94. AIMining                     // Hardware-attested mining
95. ComputeMarket                // GPU compute marketplace

// 11.2 Chain Configuration
96. ChainConfig                  // Multi-chain config
97. DeployConfig                 // Deployment config
```

### Phase 12: Adapters & Integrations

```solidity
// 12.1 Protocol Adapters
98. AsterAdapter                 // Aster protocol
99. Various DeFi adapters        // (adapters/)

// 12.2 Liquidity Aggregation
100. UniversalLiquidityRouter    // Multi-dex routing
101. CrossChainDeFiRouter        // Cross-chain operations
102. ProtocolRegistry            // Protocol registry

// 12.3 External Integrations
103. AaveV3Adapter
104. UniswapV3Adapter
105. UniswapV4Adapter
106. OneInchAdapter
```

### Phase 13: Omnichain

```solidity
// 13.1 Omnichain LP
107. OmnichainLPFactory          // Create omnichain LPs
108. OmnichainLP                 // LP implementation
109. OmnichainLPRouter           // Routing
110. Bridge (omnichain/)         // Omnichain bridge
```

---

## Part 4: Deployment Script Structure

```solidity
// Recommended script organization
script/
├── deploy/
│   ├── 01_Core.s.sol           // WLUX, bridge tokens
│   ├── 02_Identity.s.sol       // DID system
│   ├── 03_NFT.s.sol            // NFTs, marketplace, LSSVM
│   ├── 04_Governance.s.sol     // Token, timelock, governor
│   ├── 05_AMM.s.sol            // Factory, router, pools
│   ├── 06_Markets.s.sol        // Lending markets
│   ├── 07_Synths.s.sol         // Synth tokens, vault, transmuter
│   ├── 08_Perps.s.sol          // LPX perpetuals
│   ├── 09_Treasury.s.sol       // Fee splitters, validator vault
│   ├── 10_Safe.s.sol           // Multisig infrastructure
│   ├── 11_AI.s.sol             // AI token, mining
│   └── 12_Adapters.s.sol       // Protocol adapters
├── DeployFullStack.s.sol       // Deploy everything (existing)
└── config/
    ├── mainnet.json
    ├── testnet.json
    └── anvil.json
```

---

## Part 5: Files to Delete

### Duplicates to Remove

```bash
# Governance duplicates
rm contracts/dao/governance/LuxGovernor.sol    # Use governance/Governor.sol
rm contracts/governance/GoveranceToken.sol     # Typo, empty placeholder

# Move, don't delete
mv contracts/dao/governance/VotesToken.sol contracts/governance/LuxToken.sol

# Bridge duplicates
rm contracts/bridge/LETH.sol                   # Use bridge/lux/LETH.sol
rm contracts/bridge/LRC20B.sol                 # Use tokens/LRC20B.sol (after consolidation)

# After moving VotesToken
rm -rf contracts/dao/governance/               # Empty after moves
rm -rf contracts/dao/                          # If entirely empty
```

### Rename Required

```bash
# Fix typo
mv contracts/tokens/GoveranceToken.sol contracts/governance/LuxToken.sol
# (or just delete if VotesToken is preferred)

# Clarify LRC20 variants
mv contracts/tokens/LRC20/LRC20.sol contracts/tokens/LRC20/LRC20Full.sol
```

---

## Part 6: Migration Checklist

### Pre-Migration

- [ ] Backup all contracts
- [ ] Document current test coverage
- [ ] Identify all import dependencies

### Execution

1. [ ] Fix typo: Rename `GoveranceToken.sol`
2. [ ] Move `VotesToken.sol` to `governance/LuxToken.sol`
3. [ ] Delete `dao/governance/LuxGovernor.sol`
4. [ ] Delete empty `dao/` directory
5. [ ] Delete `bridge/LETH.sol` (keep `bridge/lux/LETH.sol`)
6. [ ] Consolidate `LRC20B.sol` to tokens directory
7. [ ] Update all imports throughout codebase
8. [ ] Rename `LRC20.sol` in `LRC20/` to `LRC20Full.sol`
9. [ ] Update DeployFullStack.s.sol imports

### Post-Migration

- [ ] Run full test suite
- [ ] Verify all 751 tests pass
- [ ] Update CLAUDE.md documentation
- [ ] Commit with detailed message

---

## Part 7: Summary

### Contracts Removed: 4

| File | Reason |
|------|--------|
| `dao/governance/LuxGovernor.sol` | Duplicate of `governance/Governor.sol` |
| `governance/GoveranceToken.sol` | Typo, empty placeholder |
| `bridge/LETH.sol` | Duplicate of `bridge/lux/LETH.sol` |
| `bridge/LRC20B.sol` | Consolidate to `tokens/LRC20B.sol` |

### Contracts Moved: 1

| From | To |
|------|-----|
| `dao/governance/VotesToken.sol` | `governance/LuxToken.sol` |

### Contracts Renamed: 2

| From | To |
|------|-----|
| `tokens/LRC20/LRC20.sol` | `tokens/LRC20/LRC20Full.sol` |
| (Content update only) | `tokens/LRC20B.sol` - add `burn` alias for `burnIt` |

### Canonical Implementations

| Component | Canonical Location | Notes |
|-----------|-------------------|-------|
| Governor | `governance/Governor.sol` | OZ Governor with all extensions |
| Timelock | `governance/Timelock.sol` | OZ TimelockController |
| Voting Token | `governance/LuxToken.sol` | ERC20Votes |
| Bridge Token Base | `tokens/LRC20B.sol` | Admin mint/burn |
| Bridge Tokens (Lux) | `bridge/lux/L*.sol` | LETH, LBTC, LUSD... |
| Bridge Tokens (Zoo) | `bridge/zoo/Z*.sol` | ZETH, ZBTC, ZUSD... |
| Synth Tokens | `synths/s*.sol` | sUSD, sETH, sBTC... |
| Perps Core | `perps/` | LPX ecosystem |

---

## Appendix A: Token Naming Conventions

| Prefix | Chain | Example | Purpose |
|--------|-------|---------|---------|
| W* | Native | WLUX | Wrapped native token |
| L* | Lux | LETH, LBTC | Bridge tokens on Lux |
| Z* | Zoo | ZETH, ZLUX | Bridge tokens on Zoo |
| s* | Synth | sUSD, sETH | Synthetic tokens |
| x* | Escrowed | xLPX | Escrowed/vesting tokens |
| v* | Vote-locked | vLUX | Vote-escrowed tokens |

---

## Appendix B: Complete Deployment Order (Quick Reference)

1. WLUX, LUSD, LETH, LBTC, Multicall2
2. DIDRegistry, DIDResolver
3. GenesisNFTs, Market, LSSVM (Curves, Factory, Router)
4. LuxToken, Timelock, Governor, vLUX, GaugeController
5. AMMV2Factory, AMMV2Router, LP Pools
6. ChainlinkOracle, AdaptiveCurveRateModel, Markets
7. sUSD/sETH/sBTC/sLUX/..., SynthVault, Transmuter, SynthRedeemer
8. LPUSD, LLP, LPX, xLPX, Vault, Routers, Staking
9. FeeSplitter, ValidatorVault
10. Safe infrastructure
11. AIToken, AIMining, ComputeMarket
12. Adapters, Cross-chain routers

---

*Document Version: 1.0.0*
*Last Updated: 2025-12-26*
