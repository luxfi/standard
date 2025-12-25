# Yield Strategies for Lux Bridge

Comprehensive yield strategies for Lux bridge tokens (LETH, LBTC, LUSD, LSOL, etc.). Each bridged asset automatically earns yield from source chain DeFi protocols.

## Quick Reference

| File | Protocols | Chains | Status |
|------|-----------|--------|--------|
| [AaveV3Strategy.sol](./AaveV3Strategy.sol) | Aave V3 Supply/Leverage | Ethereum, Arbitrum, Optimism, Polygon, Base | ✅ |
| [BabylonStrategy.sol](./BabylonStrategy.sol) | Babylon BTC Staking, Lombard LBTC | Bitcoin → Ethereum | ✅ |
| [BaseStrategies.sol](./BaseStrategies.sol) | Aerodrome, Moonwell, Seamless | Base | ✅ |
| [CompoundV3Strategy.sol](./CompoundV3Strategy.sol) | Compound V3 (Comet) | Ethereum, Base | ✅ |
| [ConvexStrategy.sol](./ConvexStrategy.sol) | Convex + Curve Boosting | Ethereum | ✅ |
| [CurveStrategy.sol](./CurveStrategy.sol) | Curve LP Staking | Ethereum, L2s | ✅ |
| [EigenLayerStrategy.sol](./EigenLayerStrategy.sol) | EigenLayer LST Restaking | Ethereum | ✅ |
| [EthenaStrategy.sol](./EthenaStrategy.sol) | Ethena USDe, sUSDe | Ethereum | ✅ |
| [EulerV2Strategy.sol](./EulerV2Strategy.sol) | Euler V2 Modular Lending | Ethereum | ✅ |
| [FluidStrategy.sol](./FluidStrategy.sol) | Fluid/Instadapp Lending+DEX | Ethereum | ✅ |
| [FraxStrategy.sol](./FraxStrategy.sol) | sFRAX, sfrxETH, Fraxlend, veFXS | Ethereum | ✅ |
| [L2DexStrategies.sol](./L2DexStrategies.sol) | Velodrome, Camelot, TraderJoe, Balancer | Optimism, Arbitrum, Avalanche | ✅ |
| [LidoStrategy.sol](./LidoStrategy.sol) | Lido stETH, wstETH | Ethereum | ✅ |
| [MakerDAOStrategy.sol](./MakerDAOStrategy.sol) | sDAI, DSR | Ethereum | ✅ |
| [MapleFinanceStrategy.sol](./MapleFinanceStrategy.sol) | Maple Institutional Lending | Ethereum | ✅ |
| [MorphoStrategy.sol](./MorphoStrategy.sol) | Morpho Blue, MetaMorpho | Ethereum | ✅ |
| [PendleStrategy.sol](./PendleStrategy.sol) | Pendle PT, YT, LP, vePENDLE | Ethereum, Arbitrum | ✅ |
| [PerpsStrategies.sol](./PerpsStrategies.sol) | GMX V2, Hyperliquid, Vertex, Gains | Arbitrum, Various | ✅ |
| [RestakingStrategies.sol](./RestakingStrategies.sol) | EtherFi eETH, Kelp rsETH, Swell swETH, Puffer pufETH, Renzo ezETH | Ethereum | ✅ |
| [RocketPoolStrategy.sol](./RocketPoolStrategy.sol) | Rocket Pool rETH | Ethereum | ✅ |
| [SolanaStrategies.sol](./SolanaStrategies.sol) | Marinade mSOL, Jito jitoSOL, Kamino | Solana (via Wormhole) | ✅ |
| [SparkStrategy.sol](./SparkStrategy.sol) | Spark Lending, sDAI, DSR | Ethereum | ✅ |
| [StablecoinStrategies.sol](./StablecoinStrategies.sol) | Sky, Angle, Liquity, Raft, Prisma | Ethereum | ✅ |
| [TONStrategy.sol](./TONStrategy.sol) | tsTON, stTON, STON.fi | TON (via Bridge) | ✅ |
| [YearnV3Strategy.sol](./YearnV3Strategy.sol) | Yearn V3 Vaults + Gauges | Ethereum | ✅ |

---

## Ethereum Mainnet Strategies

### ETH Liquid Staking (LSDs)

| Strategy | Contract | Token | APY | Risk | TVL Source |
|----------|----------|-------|-----|------|------------|
| Lido | `LidoStrategy.sol` | stETH/wstETH | ~4.5% | Low | $30B+ |
| Rocket Pool | `RocketPoolStrategy.sol` | rETH | ~4.5% | Low | $3B+ |
| Frax Ether | `FraxStrategy.sol` | sfrxETH | ~5-7% | Medium | $1B+ |
| Coinbase | `RestakingStrategies.sol` | cbETH | ~4% | Low | $3B+ |
| Swell | `RestakingStrategies.sol` | swETH | ~4.5% | Medium | $500M+ |
| Mantle | `RestakingStrategies.sol` | mETH | ~4.5% | Medium | $1B+ |

### Restaking (EigenLayer Ecosystem)

| Strategy | Contract | Token | APY | Risk | TVL Source |
|----------|----------|-------|-----|------|------------|
| EigenLayer | `EigenLayerStrategy.sol` | Native/LST | +2-5% | Medium | $15B+ |
| EtherFi | `RestakingStrategies.sol` | eETH/weETH | ~5-8% | Medium | $5B+ |
| Kelp DAO | `RestakingStrategies.sol` | rsETH | ~5-8% | Medium | $2B+ |
| Puffer | `RestakingStrategies.sol` | pufETH | ~5-8% | Medium | $1B+ |
| Renzo | `RestakingStrategies.sol` | ezETH | ~5-8% | Medium | $3B+ |

### Lending Protocols

| Strategy | Contract | Assets | APY | Risk | TVL Source |
|----------|----------|--------|-----|------|------------|
| Aave V3 | `AaveV3Strategy.sol` | ETH/USDC/DAI | 2-8% | Low | $20B+ |
| Compound V3 | `CompoundV3Strategy.sol` | ETH/USDC | 2-6% | Low | $3B+ |
| Morpho Blue | `MorphoStrategy.sol` | ETH/USDC | 3-10% | Low-Med | $2B+ |
| Euler V2 | `EulerV2Strategy.sol` | Various | 3-12% | Medium | $500M+ |
| Fluid | `FluidStrategy.sol` | ETH/USDC | 3-10% | Medium | $500M+ |
| Spark | `SparkStrategy.sol` | DAI/ETH | 5-8% | Low | $5B+ |
| Maple | `MapleFinanceStrategy.sol` | USDC/wETH | 8-15% | Medium | $500M+ |

### Stablecoin Yield

| Strategy | Contract | Assets | APY | Risk | TVL Source |
|----------|----------|--------|-----|------|------------|
| MakerDAO sDAI | `MakerDAOStrategy.sol` | DAI | ~8% | Low | $5B+ |
| Spark DSR | `SparkStrategy.sol` | DAI | ~8% | Low | $5B+ |
| Curve 3pool | `CurveStrategy.sol` | 3CRV | 2-5% | Low | $500M+ |
| Convex | `ConvexStrategy.sol` | Curve LPs | 5-15% | Medium | $2B+ |
| Ethena | `EthenaStrategy.sol` | USDe/sUSDe | 15-30% | Med-High | $3B+ |
| Yearn V3 | `YearnV3Strategy.sol` | Various | 5-15% | Medium | $500M+ |
| Frax | `FraxStrategy.sol` | sFRAX | ~5-7% | Low | $500M+ |

### CDP & Stablecoin Protocols

| Strategy | Contract | Assets | APY | Risk | TVL Source |
|----------|----------|--------|-----|------|------------|
| Sky/USDS | `StablecoinStrategies.sol` | USDS/sUSDS | ~8% | Low | $5B+ |
| Angle | `StablecoinStrategies.sol` | stEUR | 3-8% | Low-Med | $100M+ |
| Liquity V2 | `StablecoinStrategies.sol` | BOLD | 5-10% | Medium | $500M+ |
| Prisma | `StablecoinStrategies.sol` | mkUSD | 5-15% | Medium | $200M+ |
| Raft | `StablecoinStrategies.sol` | R | 3-8% | Medium | $100M+ |

### Yield Tokenization

| Strategy | Contract | Assets | APY | Risk | TVL Source |
|----------|----------|--------|-----|------|------------|
| Pendle PT | `PendleStrategy.sol` | PT tokens | Fixed | Low | $5B+ |
| Pendle YT | `PendleStrategy.sol` | YT tokens | Variable | High | $5B+ |
| Pendle LP | `PendleStrategy.sol` | PT/YT LPs | 10-30% | Medium | $5B+ |
| vePENDLE | `PendleStrategy.sol` | PENDLE | 20-50%+ | Medium | $1B+ |

---

## Layer 2 Strategies

### Base

| Strategy | Contract | Assets | APY | Risk |
|----------|----------|--------|-----|------|
| Aerodrome | `BaseStrategies.sol` | LP tokens | 10-50% | Medium |
| Moonwell | `BaseStrategies.sol` | ETH/USDC | 3-8% | Low |
| Seamless | `BaseStrategies.sol` | ETH/USDC | 3-8% | Low |
| Compound V3 | `CompoundV3Strategy.sol` | USDC | 2-6% | Low |

### Optimism

| Strategy | Contract | Assets | APY | Risk |
|----------|----------|--------|-----|------|
| Velodrome V2 | `L2DexStrategies.sol` | LP tokens | 10-50% | Medium |
| Aave V3 | `AaveV3Strategy.sol` | ETH/USDC | 2-8% | Low |

### Arbitrum

| Strategy | Contract | Assets | APY | Risk |
|----------|----------|--------|-----|------|
| Camelot | `L2DexStrategies.sol` | LP tokens | 10-40% | Medium |
| GMX V2 | `PerpsStrategies.sol` | GM tokens | 15-40% | Med-High |
| Pendle | `PendleStrategy.sol` | PT/YT/LP | Variable | Medium |
| Aave V3 | `AaveV3Strategy.sol` | ETH/USDC | 2-8% | Low |

### Avalanche

| Strategy | Contract | Assets | APY | Risk |
|----------|----------|--------|-----|------|
| TraderJoe | `L2DexStrategies.sol` | LP tokens | 10-30% | Medium |
| Aave V3 | `AaveV3Strategy.sol` | AVAX/USDC | 2-8% | Low |

---

## Bitcoin Strategies

| Strategy | Contract | Assets | APY | Risk | Notes |
|----------|----------|--------|-----|------|-------|
| Babylon Native | `BabylonStrategy.sol` | BTC | 3-5% | Low | Native BTC staking |
| Lombard LBTC | `BabylonStrategy.sol` | LBTC | 3-5% | Low | Liquid BTC staking |
| tBTC + Curve | `CurveStrategy.sol` | tBTC | 5-10% | Medium | Curve LP yield |

---

## Cross-Chain Strategies

### Solana (via Wormhole)

| Strategy | Contract | Assets | APY | Risk |
|----------|----------|--------|-----|------|
| Marinade | `SolanaStrategies.sol` | mSOL | ~7% | Low |
| Jito | `SolanaStrategies.sol` | jitoSOL | ~8% | Low |
| Kamino | `SolanaStrategies.sol` | Various | 5-20% | Medium |

### TON (via TON Bridge)

| Strategy | Contract | Assets | APY | Risk |
|----------|----------|--------|-----|------|
| Tonstakers | `TONStrategy.sol` | tsTON | ~5% | Low |
| Bemo | `TONStrategy.sol` | stTON | ~5% | Low |
| STON.fi | `TONStrategy.sol` | LP tokens | 10-30% | Medium |

---

## Perpetual Protocols (Delta-Neutral)

| Strategy | Contract | Assets | APY | Risk | Chain |
|----------|----------|--------|-----|------|-------|
| GMX V2 | `PerpsStrategies.sol` | GM tokens | 15-40% | Med-High | Arbitrum |
| Hyperliquid | `PerpsStrategies.sol` | HLP | 20-50% | High | Hyperliquid |
| Vertex | `PerpsStrategies.sol` | LP | 15-30% | High | Arbitrum |
| Gains Network | `PerpsStrategies.sol` | gDAI | 10-25% | Med-High | Arbitrum |

---

## Interface

All strategies implement `IYieldStrategy`:

```solidity
interface IYieldStrategy {
    function deposit(uint256 amount, bytes calldata data) external returns (uint256 shares);
    function withdraw(uint256 amount, address recipient, bytes calldata data) external returns (uint256 assets);
    function totalAssets() external view returns (uint256);
    function currentAPY() external view returns (uint256);
    function asset() external view returns (address);
    function harvest() external returns (uint256 harvested);
    function isActive() external view returns (bool);
    function name() external view returns (string memory);
    function totalDeposited() external view returns (uint256);
}
```

---

## Risk Categories

| Level | Description | Examples |
|-------|-------------|----------|
| **Low** | Battle-tested, $1B+ TVL, audited | Lido, Aave, Compound, MakerDAO |
| **Medium** | Established, $100M+ TVL, some complexity | Pendle, Morpho, Convex, GMX |
| **Med-High** | Newer protocols, delta-neutral strategies | Ethena, Hyperliquid, Vertex |
| **High** | Leveraged, complex mechanics | YT tokens, leveraged LP |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Source Chain (Ethereum, Base, Arbitrum, Solana, TON, etc.)                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                    YieldBridgeVault.sol                                 ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   ││
│  │  │ LidoStrategy│  │AaveStrategy │  │PendleStrat  │  │MoreStrategies│   ││
│  │  │   (stETH)   │  │  (aTokens)  │  │  (PT/YT/LP) │  │    (...)    │   ││
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘   ││
│  │         │                │                │                │          ││
│  │         └────────────────┴────────────────┴────────────────┘          ││
│  │                                   │                                    ││
│  │                          StrategyRouter                                ││
│  │                    (Routes deposits to best APY)                       ││
│  └─────────────────────────────────────┬───────────────────────────────────┘│
└────────────────────────────────────────┼────────────────────────────────────┘
                                         │ Warp/Wormhole/Bridge
┌────────────────────────────────────────┼────────────────────────────────────┐
│  Lux Network                           ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │           YieldBearingBridgeToken.sol (yLETH, yLBTC, yLUSD)            ││
│  │                                                                         ││
│  │  • Exchange rate appreciates as source chain yield accrues              ││
│  │  • Compatible with Alchemix (self-repaying loans)                       ││
│  │  • Compatible with LPX Perps (collateral)                              ││
│  │  • 10% liquid reserve, 90% deployed to strategies                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Adding New Strategies

1. Create new strategy contract implementing `IYieldStrategy`
2. Add protocol-specific interfaces
3. Implement deposit/withdraw/harvest logic
4. Add to StrategyRouter whitelist
5. Update this README

---

## Security

- All strategies use `SafeERC20` for token transfers
- Reentrancy protection via `ReentrancyGuard`
- Owner-only admin functions
- Slippage protection on swaps
- Emergency pause functionality

---

## License

BSD-3-Clause
