# Lux Standard Repository Organization Guide

## Overview

This document provides a comprehensive guide to the organization and structure of the Lux Standard repository, linking implementations to their corresponding Lux Proposals (LPs).

## Repository Structure

```
lux/
├── lps/                    # Lux Proposals (specifications)
│   └── LPs/               # Individual LP documents
└── standard/              # Implementation repository
    ├── src/               # Contract implementations
    ├── test/              # Test suites
    ├── script/            # Deployment scripts
    └── deploy/            # Legacy deployment scripts
```

## Quick Links

- [LP Implementation Mapping](./LP_IMPLEMENTATION_MAP.md) - Which LPs are implemented where
- [Test Migration Plan](./TEST_MIGRATION_PLAN.md) - Testing strategy and migration to Foundry
- [Makefile Guide](/Users/z/work/lux/MAKEFILE_GUIDE.md) - Unified build system documentation

## Core Implementations

### 1. Token Standards (LRC Series)

| Standard | LP | Implementation | Status |
|----------|-----|----------------|--------|
| LRC-20 | [LP-20](../lps/LPs/lp-20.md) | `src/LUX.sol`, `src/tokens/LRC20.sol` | ✅ Complete |
| LRC-721 | [LP-721](../lps/LPs/lp-721.md) | `src/LRC721.sol` | ✅ Complete |
| LRC-1155 | [LP-1155](../lps/LPs/lp-1155.md) | `src/tokens/ERC1155B.sol` | ⚠️ Partial |

### 2. DeFi Protocols

| Protocol | LP | Implementation | Status |
|----------|-----|----------------|--------|
| AMM | [LP-61](../lps/LPs/lp-61.md) | `src/uni/` (Uniswap) | ✅ Complete |
| Farming | [LP-62](../lps/LPs/lp-62.md) | `src/Farm.sol` | ✅ Complete |
| Marketplace | [LP-63](../lps/LPs/lp-63.md) | `src/Market.sol`, `src/Auction.sol` | ✅ Complete |
| Drops | [LP-69](../lps/LPs/lp-69.md) | `src/Drop.sol`, `src/DropNFTs.sol` | ✅ Complete |

### 3. Infrastructure

| Component | LP | Implementation | Status |
|-----------|-----|----------------|--------|
| Multisig | [LP-42](../lps/LPs/lp-42.md) | `src/safe/` | ✅ Complete |
| Multicall | [LP-73](../lps/LPs/lp-73.md) | `src/multicall/` | ✅ Complete |
| Bridge | [LP-15](../lps/LPs/lp-15.md) | `src/Bridge.sol` | ✅ Basic |
| Teleport | [LP-16](../lps/LPs/lp-16.md) | `src/teleport/` | ⚠️ Partial |

### 4. Quantum Security

| Feature | LP | Implementation | Status |
|---------|-----|----------------|--------|
| Lamport OTS | [LP-4](../lps/LPs/lp-4.md) | `src/lamport/` | ✅ Complete |
| Quantum Safe | [LP-5](../lps/LPs/lp-5.md) | Safe + Lamport | ✅ Complete |

## Build System

### Using the Unified Makefile

From the root Lux directory:

```bash
# Quick start
make dev                    # Setup development environment
make build-standard         # Build contracts
make test-standard          # Run tests
make deploy-local          # Deploy to local network

# Advanced
make test-standard-gas     # Run tests with gas report
make slither               # Security analysis
make new-lp NUM=99 TITLE="Title"  # Create new LP
```

### Direct Commands

From the standard directory:

```bash
# Foundry commands
forge build               # Build contracts
forge test               # Run tests
forge test --gas-report  # Test with gas report

# Deployment
forge script script/UnifiedDeploy.s.sol:DeployLocal --broadcast
```

## Testing Strategy

### Current State
- **Hardhat Tests**: Legacy TypeScript tests in `/test`
- **Foundry Tests**: New Solidity tests in `/test/foundry`

### Migration Plan
1. Core contracts → Foundry (Week 1-2)
2. Protocol integrations → Foundry (Week 3-4)
3. Advanced testing (Week 5-6)

See [TEST_MIGRATION_PLAN.md](./TEST_MIGRATION_PLAN.md) for details.

## Deployment

### Unified Deployment Scripts

#### TypeScript (Hardhat)
```bash
npx ts-node scripts/unified-deploy.ts
```

#### Solidity (Foundry)
```bash
# Local
forge script script/UnifiedDeploy.s.sol:DeployLocal --broadcast

# Testnet
forge script script/UnifiedDeploy.s.sol:DeployTestnet --broadcast --verify

# Mainnet
forge script script/UnifiedDeploy.s.sol:DeployMainnet --broadcast --verify
```

### Deployment Order
1. Core tokens (LUX, WLUX)
2. Infrastructure (Bridge, Multicall)
3. DeFi protocols (Farm, Market, Auction)
4. Governance (DAO)
5. Post-deployment setup

## Protocol Integrations

### Active Integrations
- **Alchemix v2** (`src/alcx2/`) - Yield strategies
- **GMX v2** (`src/gmx2/`) - Perpetuals and trading
- **Gnosis Safe** (`src/safe/`) - Multisig wallets
- **Uniswap** (`src/uni/`) - AMM functionality

### Planned Integrations
- **AAVE v3** (`src/aave3/`) - Lending/borrowing
- **Chainlink** - Price oracles
- **LayerZero** - Cross-chain messaging

## Common Tasks

### Adding a New Protocol

1. Create LP specification in `/lps/LPs/`
2. Implement contracts in `/standard/src/`
3. Write Foundry tests in `/standard/test/foundry/`
4. Update deployment scripts
5. Update [LP_IMPLEMENTATION_MAP.md](./LP_IMPLEMENTATION_MAP.md)

### Creating Tests

```solidity
// test/foundry/protocols/NewProtocol.t.sol
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/protocols/NewProtocol.sol";

contract NewProtocolTest is Test {
    // Test implementation
}
```

### Deploying Contracts

1. Update `UnifiedDeploy.s.sol` with new contracts
2. Test locally: `make anvil` then `make deploy-local`
3. Deploy to testnet: `make deploy-testnet`
4. Verify: `forge verify-contract ADDRESS CONTRACT_NAME`

## Security Considerations

### Audit Status
- Core contracts: Pending audit
- Protocol integrations: Inherit upstream audits
- Custom implementations: Need review

### Security Tools
```bash
make slither      # Static analysis
make mythril      # Symbolic execution
make coverage     # Test coverage
```

## Maintenance

### Regular Tasks
1. Update dependencies monthly
2. Run security scans before releases
3. Keep tests synchronized with implementations
4. Update documentation with changes

### Deprecation Process
1. Mark in LP as deprecated
2. Add deprecation notice in contract
3. Maintain for 6 months
4. Archive after migration complete

## Resources

### Documentation
- [Lux Network Docs](https://docs.lux.network)
- [Foundry Book](https://book.getfoundry.sh)
- [OpenZeppelin Docs](https://docs.openzeppelin.com)

### Tools
- [Remix IDE](https://remix.ethereum.org)
- [Tenderly](https://tenderly.co)
- [Etherscan](https://etherscan.io)

## Contributing

1. Read the relevant LP specification
2. Implement following existing patterns
3. Write comprehensive tests
4. Update documentation
5. Submit PR with LP reference

## Support

- GitHub Issues: Bug reports and features
- Discord: Community support
- LP Process: Propose improvements

---

This organization ensures:
- ✅ Clear mapping between specs and implementations
- ✅ Consistent testing approach
- ✅ Unified deployment process
- ✅ Comprehensive documentation
- ✅ Easy navigation and discovery