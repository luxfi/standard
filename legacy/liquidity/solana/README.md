# Solana Liquidity Adapters

Solana programs are written in Rust/Anchor. We interact via TypeScript SDKs.

## Supported Protocols

| Protocol | Type | Program ID | SDK |
|----------|------|------------|-----|
| **Jupiter** | Aggregator | `JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4` | `@jup-ag/api` |
| **Raydium** | AMM | `675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8` | `@raydium-io/raydium-sdk-v2` |
| **Meteora** | DLMM | `LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo` | `@meteora-ag/dlmm` |
| **Orca** | AMM | `whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc` | `@orca-so/whirlpools-sdk` |
| **Marinade** | Staking | `MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD` | `@marinade.finance/marinade-ts-sdk` |
| **Solend** | Lending | `So1endDq2YkqhipRh3WViPa8hdiSpxWy6z3Z6tMCpAo` | `@solendprotocol/solend-sdk` |
| **Kamino** | Lending | `KLend2g3cP87ber41GXWsSZQq8pKd8Xvw5p2xJrg9` | `@kamino-finance/klend-sdk` |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SOLANA LIQUIDITY ENGINE                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                                            │
│  │  LuxSolanaRouter │  ◄── TypeScript SDK entry point           │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    JUPITER AGGREGATOR                    │    │
│  │     Routes to: Raydium, Meteora, Orca, Lifinity, etc    │    │
│  └─────────────────────────────────────────────────────────┘    │
│           │                                                      │
│           ▼                                                      │
│  ┌──────────┬──────────┬──────────┬──────────┬───────────┐     │
│  │ Raydium  │ Meteora  │  Orca    │ Marinade │  Solend   │     │
│  │  AMM     │  DLMM    │ Whirlpool│ Staking  │  Lending  │     │
│  └──────────┴──────────┴──────────┴──────────┴───────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```typescript
import { LuxSolanaRouter } from '@luxfi/solana-liquidity';

const router = new LuxSolanaRouter({
  connection: new Connection(clusterApiUrl('mainnet-beta')),
  wallet: wallet,
});

// Swap via Jupiter (best route)
const { txId } = await router.swap({
  inputMint: 'So11111111111111111111111111111111111111112', // SOL
  outputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', // USDC
  amount: 1_000_000_000, // 1 SOL in lamports
  slippageBps: 50, // 0.5%
});

// Add liquidity to Meteora DLMM
const { txId } = await router.addLiquidity({
  protocol: 'METEORA',
  pool: 'SOL-USDC',
  amountA: 1_000_000_000,
  amountB: 100_000_000,
});

// Supply to Solend
const { txId } = await router.supply({
  protocol: 'SOLEND',
  token: 'USDC',
  amount: 100_000_000,
});
```

## Jupiter Integration (Recommended Entry Point)

Jupiter aggregates all Solana DEXes. Use it as primary swap router:

```typescript
import { createJupiterApiClient } from '@jup-ag/api';

const jupiter = createJupiterApiClient();

// Get quote
const quote = await jupiter.quoteGet({
  inputMint: 'So11111111111111111111111111111111111111112',
  outputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  amount: 1000000000,
  slippageBps: 50,
});

// Get swap transaction
const { swapTransaction } = await jupiter.swapPost({
  swapRequest: {
    quoteResponse: quote,
    userPublicKey: wallet.publicKey.toString(),
  },
});

// Sign and send
const txId = await connection.sendTransaction(swapTransaction);
```

## Direct Protocol Integration

### Raydium

```typescript
import { Raydium } from '@raydium-io/raydium-sdk-v2';

const raydium = await Raydium.load({
  connection,
  owner: wallet,
});

// Swap
const { execute } = await raydium.swap({
  inputMint: SOL_MINT,
  outputMint: USDC_MINT,
  amount: new BN(1_000_000_000),
  slippage: 0.01,
});

const txId = await execute();
```

### Meteora DLMM

```typescript
import DLMM from '@meteora-ag/dlmm';

const dlmmPool = await DLMM.create(connection, poolAddress);

// Add liquidity
const addLiquidityTx = await dlmmPool.addLiquidity({
  amount: amountA,
  positionPubKey: positionPubKey,
});

await sendAndConfirmTransaction(connection, addLiquidityTx, [wallet]);
```

### Solend

```typescript
import { SolendMarket } from '@solendprotocol/solend-sdk';

const market = await SolendMarket.initialize(connection);

// Deposit
const depositTx = await market.deposit(
  wallet.publicKey,
  'USDC',
  '100', // 100 USDC
);

await sendAndConfirmTransaction(connection, depositTx, [wallet]);
```
