# Lux Standard

The official standard smart contracts library for the Lux Network ecosystem.

## Overview

This repository contains the core smart contracts for the Lux Network, including:
- **LUX Token**: The native governance and utility token
- **Bridge**: Cross-chain bridge for asset transfers
- **DropNFTs**: NFT distribution system
- **Lamport Signatures**: Post-quantum secure signature implementation
- **DeFi Protocols**: AMM, staking, and yield farming contracts

## Installation

### Prerequisites
- Node.js v18+ and npm/pnpm
- Foundry (for Solidity testing)
- Git

### Setup

1. Clone the repository:
```bash
git clone https://github.com/luxfi/standard.git
cd standard
```

2. Install dependencies:
```bash
npm install
# or
pnpm install
```

3. Install Foundry (if not already installed):
```bash
./install-foundry.sh
```

## Development

### Building

Build contracts using Foundry:
```bash
forge build
```

### Testing

Run tests with Foundry:
```bash
forge test
```

Run tests with gas reporting:
```bash
forge test --gas-report
```

Generate coverage report:
```bash
forge coverage
```

### Deployment

Deploy to local network:
```bash
anvil # In one terminal
forge script script/Deploy.s.sol:DeployScript --rpc-url localhost --broadcast
```

Deploy to testnet:
```bash
forge script script/Deploy.s.sol:DeployTestnet --rpc-url testnet --broadcast --verify
```

Deploy to mainnet:
```bash
forge script script/Deploy.s.sol:DeployMainnet --rpc-url mainnet --broadcast --verify
```

## Contract Architecture

### Core Contracts

#### LUX Token (`src/LUX.sol`)
- ERC20 governance token with blacklist functionality
- Bridge minting/burning capabilities
- Pausable for emergency situations
- One-time airdrop functionality

#### Bridge (`src/Bridge.sol`)
- Cross-chain asset transfers
- Multi-signature security
- Support for multiple chains

#### DropNFTs (`src/DropNFTs.sol`)
- NFT distribution system
- Whitelist management
- Batch minting capabilities

### Quantum-Safe Features

#### Lamport Signatures (`src/lamport/`)
- One-time signature scheme
- Post-quantum secure
- Integration with Lux Safe

### DeFi Components

- **UniswapV2**: AMM implementation
- **Farm**: Yield farming contracts
- **Market**: NFT marketplace
- **Auction**: NFT auction system

## Security

### Audits
- All contracts follow best practices
- OpenZeppelin libraries for standard implementations
- Comprehensive test coverage

### Quantum Resistance
- Lamport OTS implementation for future-proofing
- Gradual migration path from ECDSA

## Testing

### Foundry Tests
Located in `test/foundry/`:
- `LUX.t.sol` - Token contract tests
- `Lamport.t.sol` - Quantum signature tests
- `TestHelpers.sol` - Common test utilities

### Running Tests
```bash
# All tests
forge test

# Specific test file
forge test --match-path test/foundry/LUX.t.sol

# Specific test function
forge test --match-test testTokenMetadata

# With verbosity
forge test -vvvv
```

## Gas Optimization

Monitor gas usage:
```bash
forge snapshot
```

Compare gas changes:
```bash
forge snapshot --diff
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the BSD-3-Clause License - see the LICENSE file for details.

## Resources

- [Lux Network Documentation](https://docs.lux.network)
- [Foundry Book](https://book.getfoundry.sh)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com)

## Contact

- GitHub: [@luxfi](https://github.com/luxfi)
- Discord: [Lux Network](https://discord.gg/luxnetwork)