# Lux Standard Library

[![npm version](https://badge.fury.io/js/@luxfi%2Fcontracts.svg)](https://www.npmjs.com/package/@luxfi/contracts)
[![CI](https://github.com/luxfi/standard/actions/workflows/ci.yml/badge.svg)](https://github.com/luxfi/standard/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)

The official Solidity smart contracts library for the Lux Network ecosystem. Production-ready contracts for tokens, DeFi protocols, cross-chain bridges, post-quantum cryptography, and more.

## Installation

### npm / pnpm / yarn

```bash
npm install @luxfi/contracts
# or
pnpm add @luxfi/contracts
# or
yarn add @luxfi/contracts
```

### Foundry

```bash
forge install luxfi/standard
```

Add to `remappings.txt`:
```
@luxfi/contracts/=lib/standard/contracts/
```

## Quick Start

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@luxfi/contracts/tokens/LRC20.sol";

contract MyToken is LRC20 {
    constructor() LRC20("My Token", "MTK") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }
}
```

## Contract Categories

### Tokens

Standard token implementations with Lux-native naming:

| Contract | Description | Import |
|----------|-------------|--------|
| **LRC20** | ERC20 base implementation | `@luxfi/contracts/tokens/LRC20.sol` |
| **LRC20B** | Bridgeable ERC20 (mint/burn by bridge) | `@luxfi/contracts/tokens/LRC20B.sol` |
| **LRC721B** | Bridgeable ERC721 | `@luxfi/contracts/tokens/LRC721B.sol` |
| **LRC1155B** | Bridgeable ERC1155 | `@luxfi/contracts/tokens/LRC1155B.sol` |
| **LUX** | Native platform token | `@luxfi/contracts/tokens/LUX.sol` |
| **LUSD** | Lux Dollar stablecoin | `@luxfi/contracts/tokens/LUSD.sol` |
| **AI** | AI compute mining token | `@luxfi/contracts/tokens/AI.sol` |
| **WLUX** | Wrapped LUX | `@luxfi/contracts/tokens/WLUX.sol` |

**Extensions:**
- `LRC20Capped` - Maximum supply cap
- `LRC20Burnable` - Burn functionality
- `LRC20Pausable` - Emergency pause
- `LRC20Permit` - Gasless approvals (EIP-2612)

### Bridge & Cross-Chain

Cross-chain asset transfers via Warp messaging:

| Contract | Description | Import |
|----------|-------------|--------|
| **Bridge** | Core bridge with Warp verification | `@luxfi/contracts/bridge/Bridge.sol` |
| **Teleport** | Token teleportation interface | `@luxfi/contracts/bridge/Teleport.sol` |
| **LRC20B** | Bridgeable token base | `@luxfi/contracts/bridge/LRC20B.sol` |
| **LETH** | Bridged ETH on Lux | `@luxfi/contracts/bridge/lux/LETH.sol` |
| **LUSD** | Lux Dollar stablecoin | `@luxfi/contracts/bridge/lux/LUSD.sol` |
| **LBTC/LSOL/LTON** | Bridged assets (L-prefix) | `@luxfi/contracts/bridge/lux/*.sol` |

```solidity
import "@luxfi/contracts/bridge/Teleport.sol";

// Teleport tokens to another chain
teleport.send(destChainId, recipient, token, amount);
```

### Synths (Self-Repaying Loans)

Deposit yield-bearing collateral, mint synthetic assets, debt repays itself over time:

| Contract | Description |
|----------|-------------|
| **SynthVault** | Main vault - deposit, mint, repay |
| **Transmuter** | 1:1 synth-to-underlying redemption |
| **SynthToken** | Base LRC20 for synthetics |
| **sUSD/sETH/sBTC** | Core synthetic assets |
| **sLUX/sAI/sZOO** | Lux ecosystem synthetics |

```solidity
import "@luxfi/contracts/synths/SynthVault.sol";

// Deposit yield token, mint synths
vault.deposit(yieldToken, amount, recipient);
vault.mint(synthAmount, recipient);
// Yield automatically repays debt over time
```

**Available Synths:** sUSD, sETH, sBTC, sLUX, sAI, sZOO, sSOL, sTON, sADA, sAVAX, sBNB, sPOL

### Perps (Perpetual Trading)

Leveraged perpetual futures with up to 50x leverage:

| Contract | Description |
|----------|-------------|
| **Vault** | Central liquidity pool |
| **Router** | Position management |
| **LLP** | Liquidity provider token |
| **PositionRouter** | Keeper-executed orders |

```solidity
import "@luxfi/contracts/perps/core/Router.sol";

// Open leveraged long position
router.increasePosition(
    collateralToken,
    indexToken,
    collateralAmount,
    sizeDelta,
    true // isLong
);
```

### AMM (Automated Market Maker)

Automated market maker with V2 and V3 pools:

| Contract | Description |
|----------|-------------|
| **AMMV2Factory** | V2 pair factory |
| **AMMV2Pair** | V2 liquidity pair |
| **AMMV2Router** | V2 swap router |
| **AMMV3Factory** | V3 concentrated liquidity factory |
| **AMMV3Pool** | V3 concentrated liquidity pool |

### Markets (Lending)

Morpho-style lending markets:

| Contract | Description |
|----------|-------------|
| **Markets** | Core lending market |
| **Allocator** | Capital allocation |
| **Router** | Lending router |

### LSSVM (NFT AMM)

NFT automated market maker with bonding curves:

| Contract | Description |
|----------|-------------|
| **LSSVMPairFactory** | Pair factory |
| **LSSVMPair** | NFT/token pair |
| **LSSVMRouter** | Swap router |
| **LinearCurve** | Linear bonding curve |
| **ExponentialCurve** | Exponential bonding curve |

### Governance

On-chain governance with vote-escrowed tokens:

| Contract | Description |
|----------|-------------|
| **DAO** | Complete DAO implementation |
| **Governor** | OpenZeppelin Governor |
| **Timelock** | Timelock controller |
| **vLUX** | Vote-escrowed LUX |
| **GaugeController** | Gauge weight voting |

```solidity
import "@luxfi/contracts/governance/DAO.sol";

// Create proposal
dao.propose(targets, values, calldatas, description);
// Vote
dao.castVote(proposalId, support);
```

### Safe (Multi-Signature Wallets)

Multi-sig wallets with post-quantum signer support:

| Contract | Description |
|----------|-------------|
| **Safe** | Core multi-sig wallet |
| **SafeFactory** | Safe deployment factory |
| **SafeFROSTSigner** | FROST threshold signer |
| **SafeMLDSASigner** | ML-DSA (Dilithium) signer |
| **SafeRingtailSigner** | Ringtail lattice signer |
| **SafeLSSSigner** | LSS-MPC signer |
| **SafeCGGMP21Signer** | CGGMP21 ECDSA threshold |
| **QuantumSafe** | Full quantum-resistant safe |

```solidity
import "@luxfi/contracts/safe/Safe.sol";
import "@luxfi/contracts/safe/SafeFROSTSigner.sol";

// Create safe with FROST threshold signing
Safe safe = safeFactory.createSafe(owners, threshold);
safe.enableModule(address(frostSigner));
```

### Post-Quantum Cryptography

Quantum-resistant signature schemes via EVM precompiles:

| Precompile | Description |
|------------|-------------|
| **IFROST** | Schnorr threshold signatures |
| **IMLDSA** | ML-DSA (FIPS 204 / Dilithium) |
| **IMLKEM** | ML-KEM key encapsulation |
| **ISLHDSA** | SLH-DSA (SPHINCS+) |
| **IRingtailThreshold** | Lattice-based threshold |
| **ICGGMP21** | ECDSA threshold (MPC) |
| **IBLS** | BLS signatures |
| **IWarp** | Cross-chain Warp messaging |
| **IQuasar** | Quantum consensus |

```solidity
import "@luxfi/contracts/crypto/precompiles/IMLDSA.sol";

// Verify post-quantum signature
bool valid = IMLDSA.verify(publicKey, message, signature);
```

**Lamport Signatures:**
```solidity
import "@luxfi/contracts/crypto/lamport/LamportBase.sol";

// One-time quantum-safe signatures
```

### Identity (DID)

Decentralized identity management:

| Contract | Description |
|----------|-------------|
| **DIDRegistry** | DID document storage |
| **DIDResolver** | DID resolution |
| **PremiumDIDRegistry** | Premium DID features |

### AI & Compute

AI token mining and compute marketplace:

| Contract | Description |
|----------|-------------|
| **AIToken** | AI mining token |
| **AIMining** | Mining rewards |
| **ComputeMarket** | GPU compute marketplace |

### Staking

| Contract | Description |
|----------|-------------|
| **sLUX** | Staked LUX token |

### Treasury

| Contract | Description |
|----------|-------------|
| **FeeSplitter** | Protocol fee distribution |
| **SynthFeeSplitter** | Synth-specific fees |
| **ValidatorVault** | Validator rewards vault |

### Account Abstraction

| Contract | Description |
|----------|-------------|
| **Account** | ERC-4337 account |
| **EOA** | Externally owned account |
| **EOAFactory** | Account factory |
| **EOAPaymaster** | Gas sponsorship |

### Omnichain

| Contract | Description |
|----------|-------------|
| **OmnichainLP** | Cross-chain liquidity |
| **OmnichainLPRouter** | Routing layer |

### NFT

| Contract | Description |
|----------|-------------|
| **GenesisNFTs** | Genesis collection |
| **Market** | NFT marketplace |

## Development

This project supports both **Foundry** (recommended) and **Hardhat** for development.

### Prerequisites

- [Foundry](https://getfoundry.sh) (recommended)
- Node.js 18+ and pnpm/npm
- Git

### Setup

```bash
# Clone repository
git clone https://github.com/luxfi/standard.git
cd standard

# Install Foundry dependencies
forge install

# Install Node.js dependencies (for Hardhat)
pnpm install
```

### Building

```bash
# Foundry (recommended)
forge build

# Hardhat
pnpm build:hardhat
```

### Testing

```bash
# Foundry (recommended) - 751+ tests
forge test

# With verbosity
forge test -vvv

# With gas reporting
forge test --gas-report

# Coverage
forge coverage

# Hardhat
pnpm test:hardhat
```

### TypeScript Support

Generate TypeChain types for Hardhat/ethers:

```bash
pnpm typechain
```

### Deployment

#### Foundry (recommended)

Deploy scripts are in `script/`:

```bash
# Local deployment (start anvil first)
anvil &
forge script script/DeployAll.s.sol --rpc-url localhost --broadcast

# Lux Mainnet
forge script script/DeployAll.s.sol --rpc-url lux --broadcast --verify

# Lux Testnet
forge script script/DeployAll.s.sol --rpc-url lux_testnet --broadcast --verify
```

**Available deploy scripts:**
- `DeployTokens.s.sol` - Core tokens (LUX, LUSD, AI, WLUX)
- `DeploySynths.s.sol` - Synths protocol (SynthVault, Transmuter)
- `DeployPerps.s.sol` - Perpetual trading (Vault, Router, LLP)
- `DeployAMM.s.sol` - AMM pools (V2, V3)
- `DeployMarkets.s.sol` - Lending markets
- `DeployGovernance.s.sol` - DAO & governance
- `DeployAI.s.sol` - AI mining
- `DeployAll.s.sol` - Full deployment

#### Hardhat

```bash
# Start local node
pnpm node

# Deploy via Hardhat
pnpm deploy:hardhat localhost
```

#### Network Configuration

Configure `.env` for deployments:

```bash
PRIVATE_KEY=your_private_key
INFURA_API_KEY=your_infura_key
ETHERSCAN_API_KEY=your_etherscan_key
LUXSCAN_API_KEY=your_luxscan_key
```

Available networks: `lux`, `lux_testnet`, `zoo`, `zoo_testnet`, `hanzo`, `mainnet`, `sepolia`

## Documentation

Full documentation available at [standard.lux.network](https://standard.lux.network)

- [Getting Started](https://standard.lux.network/docs/getting-started)
- [API Reference](https://standard.lux.network/docs/api)
- [Examples](https://standard.lux.network/docs/examples)

## Security

- All contracts follow Solidity best practices
- Built on OpenZeppelin libraries where applicable
- Post-quantum cryptography for future-proofing
- Comprehensive test coverage (751+ tests)

### Audits

Audit reports are available in the `audits/` directory.

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

BSD-3-Clause License - see [LICENSE](LICENSE)

## Links

- [Documentation](https://standard.lux.network)
- [npm Package](https://www.npmjs.com/package/@luxfi/contracts)
- [GitHub](https://github.com/luxfi/standard)
- [Lux Network](https://lux.network)
- [Discord](https://discord.gg/luxnetwork)
