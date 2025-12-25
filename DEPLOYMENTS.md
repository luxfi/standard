# Contract Deployments

All deployed contracts across the Lux ecosystem networks.

## Network Chain IDs

| Network | Chain ID | Explorer |
|---------|----------|----------|
| Lux Mainnet | 96369 | [explore.lux.network](https://explore.lux.network) |
| Lux Testnet | 96368 | [explore.lux-test.network](https://explore.lux-test.network) |
| Zoo Mainnet | 200200 | [explore.zoo.network](https://explore.zoo.network) |
| Zoo Testnet | 200201 | [explore.zoo-test.network](https://explore.zoo-test.network) |
| Hanzo Mainnet | 36963 | [explore.hanzo.network](https://explore.hanzo.network) |
| Hanzo Testnet | 36964 | [explore.hanzo-test.network](https://explore.hanzo-test.network) |

## Lux Mainnet (Chain ID: 96369)

### Core Infrastructure

| Contract | Address |
|----------|---------|
| WLUX | `0x55750d6CA62a041c06a8E28626b10Be6c688f471` |
| Multicall | `0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F` |

### AMM V2 (QuantumSwap)

| Contract | Address |
|----------|---------|
| UniswapV2Factory | `0xd9a95609DbB228A13568Bd9f9A285105E7596970` |
| UniswapV2Router02 | `0x1F6cbC7d3bc7D803ee76D80F0eEE25767431e674` |

### AMM V3 (Concentrated Liquidity)

| Contract | Address |
|----------|---------|
| UniswapV3Factory | `0xb732BD88F25EdD9C3456638671fB37685D4B4e3f` |
| SwapRouter | `0xE8fb25086C8652c92f5AF90D730Bac7C63Fc9A58` |
| SwapRouter02 | `0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E` |
| Quoter | `0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275` |
| QuoterV2 | `0x15C729fdd833Ba675edd466Dfc63E1B737925A4c` |
| TickLens | `0x57A22965AdA0e52D785A9Aa155beF423D573b879` |
| NonfungiblePositionManager | `0x7a4C48B9dae0b7c396569b34042fcA604150Ee28` |
| NonfungibleTokenPositionDescriptor | `0x043ccF9C207165DA6D4a44ae47488AF49843bADe` |
| NFTDescriptor | `0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5` |

## Lux Testnet (Chain ID: 96368)

### Core Infrastructure

| Contract | Address |
|----------|---------|
| WLUX | `0x732740c5c895C9FCF619930ed4293fc858eb44c7` |
| WETH9 | `0xd9956542B51032d940ef076d70B69410667277A3` |
| Multicall | `0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F` |

### AMM V2

| Contract | Address |
|----------|---------|
| UniswapV2Factory | `0x81C3669B139D92909AA67DbF74a241b10540d919` |
| UniswapV2Router02 | `0xDB6c703c80BFaE5F9a56482d3c8535f27E1136EB` |

### AMM V3

| Contract | Address |
|----------|---------|
| UniswapV3Factory | `0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84` |
| SwapRouter | `0xE8fb25086C8652c92f5AF90D730Bac7C63Fc9A58` |
| SwapRouter02 | `0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E` |
| Quoter | `0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275` |
| QuoterV2 | `0x15C729fdd833Ba675edd466Dfc63E1B737925A4c` |
| TickLens | `0x57A22965AdA0e52D785A9Aa155beF423D573b879` |
| NonfungiblePositionManager | `0x7a4C48B9dae0b7c396569b34042fcA604150Ee28` |
| NonfungibleTokenPositionDescriptor | `0x043ccF9C207165DA6D4a44ae47488AF49843bADe` |
| NFTDescriptor | `0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5` |

## Bridge Tokens

### Lux Chain (L-prefix)

Bridge tokens on Lux for assets from other chains:

| Token | Symbol | Description |
|-------|--------|-------------|
| LuxDollar | LUSD | Native Lux stablecoin |
| LuxETH | LETH | Bridged ETH |
| LuxBTC | LBTC | Bridged BTC |
| LuxSOL | LSOL | Bridged SOL |
| LuxTON | LTON | Bridged TON |
| LuxADA | LADA | Bridged ADA |
| LuxAVAX | LAVAX | Bridged AVAX |
| LuxBNB | LBNB | Bridged BNB |
| LuxPOL | LPOL | Bridged POL |
| LuxZOO | LZOO | Bridged ZOO |
| LuxXDAI | LXDAI | Bridged xDAI |

### Zoo Chain (Z-prefix)

Bridge tokens on Zoo for assets from other chains:

| Token | Symbol | Description |
|-------|--------|-------------|
| ZooETH | ZETH | Bridged ETH |
| ZooBTC | ZBTC | Bridged BTC |
| ZooLUX | ZLUX | Bridged LUX |
| ZooXDAI | ZXDAI | Bridged xDAI |

## Synthetic Assets (x-prefix)

Self-repaying synthetic assets from the Synths protocol:

| Synth | Underlying | Category |
|-------|------------|----------|
| xUSD | LUSD | Stablecoin |
| xETH | LETH | Major L1 |
| xBTC | LBTC | Major L1 |
| xLUX | LUX/sLUX | Native |
| xAI | AI/sAI | Native |
| xZOO | LZOO | Native |
| xSOL | LSOL | Major L1 |
| xTON | LTON | Major L1 |
| xADA | LADA | Major L1 |
| xAVAX | LAVAX | Major L1 |
| xBNB | LBNB | Major L1 |
| xPOL | LPOL | Major L1 |

## Perps Protocol (LPX)

Perpetual futures protocol contracts:

| Contract | Description |
|----------|-------------|
| Vault | Central liquidity pool |
| Router | Position management |
| LlpManager | LLP token management |
| LLP | Lux Liquidity Provider token |
| LPUSD | Internal accounting stablecoin |
| LPX | Governance/utility token |
| xLPX | Escrowed LPX (vesting) |

## Precompile Addresses

Native EVM precompiles for cryptographic operations:

| Precompile | Address | Description |
|------------|---------|-------------|
| DeployerAllowList | `0x0200...0001` | Deployer permissions |
| TxAllowList | `0x0200...0002` | Transaction permissions |
| FeeManager | `0x0200...0003` | Dynamic fee management |
| NativeMinter | `0x0200...0004` | Native token minting |
| RewardManager | `0x0200...0005` | Validator rewards |
| ML-DSA | `0x0200...0006` | Post-quantum signatures |
| ML-KEM | `0x0200...0007` | Post-quantum key encapsulation |
| Warp | `0x0200...0008` | Cross-chain messaging |
| PQCrypto | `0x0200...0009` | Multi-PQ operations |
| Quasar | `0x0200...000A` | Quantum consensus |
| Ringtail | `0x0200...000B` | Threshold lattice signatures |
| FROST | `0x0200...000C` | Schnorr threshold signatures |
| CGGMP21 | `0x0200...000D` | ECDSA threshold signatures |

## Verification

All contracts are verified on their respective block explorers. Source code is available at:
- GitHub: [github.com/luxfi/standard](https://github.com/luxfi/standard)
- npm: [@luxfi/contracts](https://www.npmjs.com/package/@luxfi/contracts)

## Deployment Scripts

Deploy using Foundry:

```bash
# Deploy to Lux Mainnet
forge script script/DeployAll.s.sol --rpc-url lux --broadcast --verify

# Deploy to Lux Testnet
forge script script/DeployAll.s.sol --rpc-url lux_testnet --broadcast --verify
```
