# TON Liquidity Adapters

TON contracts use FunC/Tact. We interact via TypeScript SDKs.

## Supported Protocols

| Protocol | Type | Address | SDK |
|----------|------|---------|-----|
| **STON.fi** | DEX | `EQB3ncyBUTjZUA5EnFKR5_EnOMI9V1tTEAAPaiU71gc4TiUt` | `@ston-fi/sdk` |
| **DeDust** | DEX | `EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_` | `@dedust/sdk` |
| **Evaa** | Lending | `EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr` | `@evaa/sdk` |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      TON LIQUIDITY ENGINE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                                            │
│  │  LuxTonRouter   │  ◄── TypeScript SDK entry point            │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    OMNISTON AGGREGATOR                   │    │
│  │     Routes to: STON.fi, DeDust pools for best price     │    │
│  └─────────────────────────────────────────────────────────┘    │
│           │                                                      │
│           ▼                                                      │
│  ┌────────────────┬────────────────┬────────────────┐           │
│  │   STON.fi      │    DeDust      │     Evaa       │           │
│  │   AMM DEX      │    AMM DEX     │    Lending     │           │
│  └────────────────┴────────────────┴────────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```typescript
import { LuxTonRouter } from '@luxfi/ton-liquidity';

const router = new LuxTonRouter({
  endpoint: 'https://toncenter.com/api/v2/jsonRPC',
  wallet: wallet,
});

// Swap via STON.fi
const { txHash } = await router.swap({
  protocol: 'STONFI',
  tokenIn: 'TON',
  tokenOut: 'USDT',
  amount: toNano('1'), // 1 TON
  slippage: 0.01,
});

// Add liquidity
const { txHash } = await router.addLiquidity({
  protocol: 'STONFI',
  pool: 'TON/USDT',
  amount0: toNano('1'),
  amount1: 1_000_000n, // 1 USDT
});
```

## STON.fi Integration

```typescript
import { DEX, pTON } from '@ston-fi/sdk';
import { TonClient } from '@ton/ton';

const client = new TonClient({
  endpoint: 'https://toncenter.com/api/v2/jsonRPC',
});

const dex = new DEX.v1({
  tonClient: client,
});

// Get pool
const pool = await dex.getPool({
  token0: 'TON',
  token1: 'USDT',
});

// Swap TON for USDT
const txParams = await dex.buildSwapTonToJetton({
  userWalletAddress: wallet.address,
  proxyTonAddress: pTON.v1.address,
  askJettonAddress: USDT_ADDRESS,
  offerAmount: toNano('1'),
  minAskAmount: '900000', // 0.9 USDT minimum
});

await wallet.sendTransaction(txParams);
```

## DeDust Integration

```typescript
import { Factory, MAINNET_FACTORY_ADDR, Asset, PoolType } from '@dedust/sdk';
import { TonClient4 } from '@ton/ton';

const client = new TonClient4({
  endpoint: 'https://mainnet-v4.tonhubapi.com',
});

const factory = client.open(Factory.createFromAddress(MAINNET_FACTORY_ADDR));

// Get pool
const pool = await factory.getPool(PoolType.VOLATILE, [
  Asset.native(),
  Asset.jetton(USDT_ADDRESS),
]);

// Swap
const swapParams = await pool.buildSwapParams({
  amount: toNano('1'),
  poolAddress: pool.address,
});

await wallet.sendTransaction(swapParams);
```

## Evaa Lending

```typescript
import { EvaaClient } from '@evaa/sdk';

const evaa = new EvaaClient({
  endpoint: 'https://toncenter.com/api/v2/jsonRPC',
});

// Supply TON
const supplyTx = await evaa.buildSupplyTransaction({
  asset: 'TON',
  amount: toNano('10'),
  userAddress: wallet.address,
});

await wallet.sendTransaction(supplyTx);

// Borrow USDT
const borrowTx = await evaa.buildBorrowTransaction({
  asset: 'USDT',
  amount: 5_000_000n, // 5 USDT
  userAddress: wallet.address,
});

await wallet.sendTransaction(borrowTx);
```

## Cross-Chain via Omniston

STON.fi's Omniston enables cross-chain swaps:

```typescript
import { Omniston } from '@ston-fi/omniston-sdk';

const omniston = new Omniston({
  apiKey: 'your-api-key',
});

// Cross-chain swap TON → ETH
const quote = await omniston.getQuote({
  srcChain: 'TON',
  dstChain: 'ETHEREUM',
  srcToken: 'TON',
  dstToken: 'ETH',
  amount: toNano('10'),
});

const tx = await omniston.buildSwap(quote);
await wallet.sendTransaction(tx);
```
