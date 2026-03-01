# Securities Module

Regulated security token contracts for the Lux Standard Library.

## Origin

Originally based on [Arca Labs ST-Contracts](https://github.com/arcalabs/st-contracts) (Solidity 0.4.25).
Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team.

**Copyright (c) 2026 Lux Partners Limited** -- https://lux.network
**Copyright (c) 2019 Arca Labs Inc** -- https://arca.digital

## Standards Implemented

| Standard | Description | Contract |
|----------|-------------|----------|
| ERC-1404 | Simple Restricted Token | `interfaces/IERC1404.sol`, `token/SecurityToken.sol` |
| ST-20    | Security Token Standard | `interfaces/IST20.sol`, `token/SecurityToken.sol` |
| ERC-1400 | Partitioned Securities  | `token/PartitionToken.sol` (simplified) |
| ERC-1643 | Document Management     | `registry/DocumentRegistry.sol` |

## Structure

```
securities/
  interfaces/
    IERC1404.sol            -- ERC-1404 (Simple Restricted Transfer)
    IST20.sol               -- ST-20 (verifyTransfer hook)
    IComplianceModule.sol   -- pluggable compliance interface
  compliance/
    ComplianceRegistry.sol  -- KYC/AML/accreditation registry
    WhitelistModule.sol     -- whitelist-based transfer restriction
    LockupModule.sol        -- Rule 144 holding period enforcement
    JurisdictionModule.sol  -- country/jurisdiction restrictions
  token/
    SecurityToken.sol       -- base regulated ERC-20 (ERC-1404 + ST-20)
    RestrictedToken.sol     -- ERC-1404 with external restriction engine
    PartitionToken.sol      -- ERC-1400 partitioned security
  registry/
    TransferRestriction.sol -- transfer restriction engine
    DocumentRegistry.sol    -- on-chain document storage (ERC-1643)
  corporate/
    DividendDistributor.sol -- on-chain dividend payments
    CorporateActions.sol    -- splits, mergers, forced transfers
  bridge/
    SecurityBridge.sol      -- cross-chain mint/burn/teleport
```

## Restriction Codes

Shared across the module for ERC-1404 `messageForTransferRestriction`:

| Code | Meaning |
|------|---------|
| 0    | SUCCESS |
| 1    | SENDER_NOT_WHITELISTED |
| 2    | RECEIVER_NOT_WHITELISTED |
| 3    | SENDER_BLACKLISTED |
| 4    | RECEIVER_BLACKLISTED |
| 5    | SENDER_LOCKED |
| 6    | JURISDICTION_BLOCKED |
| 7    | ACCREDITATION_REQUIRED |
| 16   | SENDER_NOT_ON_WHITELIST (module) |
| 17   | RECEIVER_NOT_ON_WHITELIST (module) |
| 18   | SENDER_LOCKUP_ACTIVE (module) |
| 19   | SENDER_JURISDICTION_BLOCKED (module) |
| 20   | RECEIVER_JURISDICTION_BLOCKED (module) |
| 21   | SENDER_JURISDICTION_UNSET (module) |
| 22   | RECEIVER_JURISDICTION_UNSET (module) |
| 32   | MAX_HOLDERS_REACHED |
| 33   | TRANSFER_AMOUNT_EXCEEDED |

## Usage

```solidity
import {ComplianceRegistry} from "@luxfi/standard/securities/compliance/ComplianceRegistry.sol";
import {SecurityToken} from "@luxfi/standard/securities/token/SecurityToken.sol";

// Deploy compliance registry
ComplianceRegistry registry = new ComplianceRegistry(admin);

// Deploy security token
SecurityToken token = new SecurityToken("Acme Shares", "ACME", admin, registry);

// Whitelist investors
registry.whitelistAdd(investor1);
registry.whitelistAdd(investor2);

// Mint tokens
token.mint(investor1, 1000e18);

// Transfer (compliance enforced automatically via _update hook)
token.transfer(investor2, 100e18);
```

## What Was Ported vs Created New

### Ported from Arca Labs
- `IERC1404.sol` -- ERC-1404 interface (from `ERC1404.sol`)
- `IST20.sol` -- ST-20 verifyTransfer hook
- `SecurityToken.sol` -- base security token (from `SecurityToken.sol`)
- `ComplianceRegistry.sol` -- KYC/AML registry (from `Registry.sol`)
- `WhitelistModule.sol` -- whitelist logic (from `hanzo-solidity/Whitelist.sol`)

### Created New
- `IComplianceModule.sol` -- pluggable compliance interface
- `LockupModule.sol` -- Rule 144 lockup enforcement
- `JurisdictionModule.sol` -- country/jurisdiction restrictions
- `RestrictedToken.sol` -- ERC-1404 with external restriction engine
- `PartitionToken.sol` -- ERC-1400 partitioned security
- `TransferRestriction.sol` -- transfer restriction engine
- `DocumentRegistry.sol` -- on-chain document storage (ERC-1643)
- `DividendDistributor.sol` -- on-chain dividend payments
- `CorporateActions.sol` -- corporate actions (splits, seizure)
- `SecurityBridge.sol` -- cross-chain bridge
