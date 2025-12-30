# Lux Liquid Protocol

Self-repaying loans backed by yield-bearing collateral, with cross-chain teleportation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        LUX LIQUID PROTOCOL                                              │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  EXTERNAL CHAINS (Base/Ethereum)              LUX CHAIN (96369)                        │
│  ┌─────────────────────────────┐              ┌─────────────────────────────┐          │
│  │      LiquidVault            │   Warp      │        Teleporter           │          │
│  │  - MPC custody              │  ────────►  │  - Burn/mint LETH           │          │
│  │  - Yield strategies         │              │  - MPC verification         │          │
│  │  - Buffer management        │              │  - Peg guards               │          │
│  └─────────────────────────────┘              └─────────────────────────────┘          │
│          │                                              │                              │
│          │ harvest()                                    │ mintYield()                  │
│          ▼                                              ▼                              │
│  ┌─────────────────────────────┐              ┌─────────────────────────────┐          │
│  │    IYieldStrategy           │              │      LiquidYield            │          │
│  │  - Lido stETH               │              │  - Burns LETH yield         │          │
│  │  - Aave V3                  │              │  - Notifies LiquidETH       │          │
│  │  - Compound V3              │              │  - Batch processing         │          │
│  │  - EigenLayer               │              └─────────────────────────────┘          │
│  │  - Morpho                   │                        │                              │
│  │  - Yearn V3                 │                        │ notifyYieldBurn()            │
│  └─────────────────────────────┘                        ▼                              │
│                                               ┌─────────────────────────────┐          │
│                                               │       LiquidETH             │          │
│                                               │  - 90% E-Mode LTV           │          │
│                                               │  - In-kind borrowing        │          │
│                                               │  - Yield index debt repay   │          │
│                                               │  - Auto-liquidation         │          │
│                                               └─────────────────────────────┘          │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Contracts

### teleport/
Core cross-chain infrastructure:

| Contract | Description |
|----------|-------------|
| `TeleportVault.sol` | Base MPC-controlled vault (abstract) |
| `LiquidVault.sol` | ETH vault with yield strategies (Base/Ethereum) |
| `Teleporter.sol` | Burn/mint bridge on Lux |
| `LiquidETH.sol` | In-kind lending vault with 90% LTV |
| `LiquidYield.sol` | Yield processor (burn→notify) |

### synths/
Synthetic token system (self-repaying):

| Contract | Description |
|----------|-------------|
| `SynthVault.sol` | Alchemist-style vault wrapper |
| `SynthRedeemer.sol` | Transmuter wrapper for 1:1 redemption |
| `SynthToken.sol` | Base ERC20 for synths |
| `s*.sol` | Concrete synths (sUSD, sETH, sBTC, etc.) |

## Key Parameters

### LiquidETH (E-Mode)
- **LTV**: 90%
- **Liquidation Threshold**: 94%
- **Liquidation Bonus**: 1%

### Teleporter (Peg Guards)
- **Degrade At**: 99.5% (slow minting)
- **Pause At**: 98.5% (halt minting)
- **Backing Min**: 100%

## Yield Flow

1. User deposits ETH to **LiquidVault** on Ethereum
2. LiquidVault deploys to **IYieldStrategy** (Lido, Aave, etc.)
3. Strategies earn yield over time
4. MPC calls `harvestYield()` → yield sent to Lux via Warp
5. **Teleporter** mints LETH yield to **LiquidYield**
6. **LiquidYield** burns LETH and calls `notifyYieldBurn()`
7. **LiquidETH** updates `yieldIndex`, reducing all debts pro-rata

## Usage

### Deposit & Borrow
```solidity
// 1. Deposit ETH on Ethereum
liquidVault.depositETH{value: 10 ether}(myLuxAddress);

// 2. Wait for bridge (MPC mints LETH on Lux)

// 3. Deposit LETH as collateral on Lux
liquidETH.deposit(10 ether);

// 4. Borrow LETH (up to 90% LTV)
liquidETH.borrow(9 ether);

// 5. Debt auto-repays as yield flows from Ethereum strategies
```

### Check Position
```solidity
(uint256 collateral, uint256 debt) = liquidETH.getPosition(user);
uint256 healthFactor = collateral * LT / debt; // Must be > 1e18
```

## Related Packages

- `contracts/yield/` - Yield strategy interfaces and implementations
- `contracts/bridge/` - Cross-chain bridge infrastructure
- `contracts/synths/` - Legacy synth contracts (being consolidated here)
