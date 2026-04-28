# Securities Module

Regulated security token contracts for Lux. The canonical token + compliance
machinery is the **ERC-3643 (T-REX)** suite, vendored as `@luxfi/erc-3643`
(fork of [ERC-3643/ERC-3643](https://github.com/ERC-3643/ERC-3643)). Identity
is **ONCHAINID** (ERC-734/735), vendored as `@luxfi/onchain-id` (fork of
[onchain-id/solidity](https://github.com/onchain-id/solidity)).

We do not duplicate ERC-3643 — we extend it with what lux uniquely provides:
cross-chain teleport via Warp, on-chain dividends, and document/corporate
action helpers.

## Structure

```
securities/
  bridge/SecurityBridge.sol      -- teleport-enabled cross-chain bridge (Warp + IToken)
  corporate/CorporateActions.sol -- forced transfer, seize, recovery (T-REX agent role)
  corporate/DividendDistributor.sol -- on-chain dividend payouts (snapshot + claim)
  registry/DocumentRegistry.sol  -- ERC-1643 on-chain document references
```

## Canonical imports

```solidity
// Token + compliance + identity registry
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { Token } from "@luxfi/erc-3643/contracts/token/Token.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import { IModularCompliance } from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";

// Compliance modules (drop-in)
import { CountryAllowModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/CountryAllowModule.sol";
import { CountryRestrictModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/CountryRestrictModule.sol";
import { MaxBalanceModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/MaxBalanceModule.sol";
import { TimeTransfersLimitsModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/TimeTransfersLimitsModule.sol";
// (and 9 more — see node_modules/@luxfi/erc-3643/contracts/compliance/modular/modules/)

// Identity (ONCHAINID)
import { IIdentity } from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";

// Lux extensions
import { SecurityBridge } from "@luxfi/contracts/securities/bridge/SecurityBridge.sol";
import { CorporateActions } from "@luxfi/contracts/securities/corporate/CorporateActions.sol";
import { DividendDistributor } from "@luxfi/contracts/securities/corporate/DividendDistributor.sol";
import { DocumentRegistry } from "@luxfi/contracts/securities/registry/DocumentRegistry.sol";
```

## Teleport flow

```
Source chain                         Destination chain
─────────────                        ─────────────────
holder ──lock(amount, dst)──> Bridge ──Warp(LOCK)──> Bridge ──claimMint(idx)──> Token.mint(holder)
holder ──teleport(amount,dst)──> Bridge ──Warp(BURN)──> Bridge ──claimRelease(idx)──> Token.transfer(holder)
```

The bridge holds the T-REX agent role (via `Token.addAgent(address(bridge))`)
on the wrapped chain so it can mint/burn. Trusted source chains and senders
are configured by `ADMIN_ROLE` on the destination bridge.
