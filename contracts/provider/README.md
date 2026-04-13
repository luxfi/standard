# Regulated Provider — OSS plug-in interface

Lux exchange is jurisdiction-neutral OSS. Some forks need to offer
regulated assets (security tokens, tokenized equities, wrapped ETFs).
Rather than baking compliance into this repo, the exchange delegates
regulated flow to an **external provider** that implements `IRegulatedProvider`.

## How the router decides

```
user calls ProviderRouter.swap(…, symbol, nativePool, …)
    │
    ▼
if (hasProvider && provider.handles(symbol))
    │ regulated path
    ▼
    provider.isEligible(trader, symbol) → (ok, reasonCode)
    provider.routedSwap(trader, …)
else
    │ open path
    ▼
    IAMMPool(nativePool).swap(…)
```

- **No provider configured** (`address(0)` or `NullProvider`): every swap
  goes through native Lux AMM pools. Pure crypto-to-crypto DeFi.
- **Provider configured**: symbols the provider handles are gated and
  routed; everything else is native.

## Wiring a fork

```solidity
// 1. Pure DeFi fork — deploy a NullProvider (or pass address(0))
ProviderRouter router = new ProviderRouter(IRegulatedProvider(address(0)));

// 2. Regulated fork — deploy a provider-specific adapter from the
//    provider's repo, pass its address.
IRegulatedProvider provider = IRegulatedProvider(PROVIDER_ADDR);
ProviderRouter router = new ProviderRouter(provider);
```

## What implementers must deliver

| Function        | Contract                                                 |
|-----------------|----------------------------------------------------------|
| `handles`       | return true for symbols the provider is licensed to trade |
| `isEligible`    | check KYC/accreditation/jurisdiction/lockup state         |
| `onboard`       | accept an attestation (opaque bytes; implementer-defined) |
| `bestPrice`     | read best bid/ask from provider's venue                   |
| `routedSwap`    | match + settle atomically; return `amountOut`             |

Reason codes follow ERC-1404 conventions:

| Code | Meaning                        |
|------|--------------------------------|
| 0    | OK                             |
| 6    | jurisdiction blocked           |
| 7    | accreditation required         |
| 16/17| not whitelisted                |
| 18   | lockup period active (Rule 144)|
| 32   | max holders                    |
| 33   | per-address limit              |
| 255  | provider disabled              |

## Why this pattern

- **Clean separation**: Lux repo stays OSS / permissionless / universal.
- **One and one way**: any provider that implements the interface drops in.
- **No fork tax**: removing the provider (set to `NullProvider`) returns
  the exchange to pure DeFi. No state migration needed.
- **Regulator-friendly**: compliance state lives in the provider's own
  repo, reviewed by that provider's own regulators — not Lux core.
