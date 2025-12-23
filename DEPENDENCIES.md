# @luxfi/standard Dependencies & Audits

This document outlines all audited third-party contracts that @luxfi/standard builds upon.

## Core Dependencies

### OpenZeppelin Contracts v5.1.0
**Source**: [openzeppelin-contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
**Audits**: 
- [Trail of Bits](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/audits)
- [ChainSecurity](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/audits)
- [Sigma Prime](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/audits)
- [Peckshield](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/audits)

**Used For**:
- Token standards (ERC20, ERC721, ERC1155, ERC4626)
- Access control (Ownable, AccessControl, Roles)
- Security (ReentrancyGuard, Pausable)
- Utilities (Address, SafeERC20, Counters)
- Governance (Governor, TimelockController)

### OpenZeppelin Contracts Upgradeable v4.9.0
**Source**: [openzeppelin-contracts-upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable)
**Audits**: Same as OpenZeppelin Contracts

**Used For**:
- UUPS/Transparent proxy patterns
- Upgradeable token implementations
- Upgradeable governance

---

## Account Abstraction (ERC-4337)

### eth-infinitism Account Abstraction v0.9.0
**Source**: [account-abstraction](https://github.com/eth-infinitism/account-abstraction)
**Audits**:
- [OpenZeppelin Audit (2023)](https://github.com/eth-infinitism/account-abstraction/blob/develop/audits/OpenZeppelin-AA-Audit-2023.pdf)
- [Ackee Blockchain Audit (2023)](https://github.com/eth-infinitism/account-abstraction/tree/develop/audits)

**Used For**:
- EntryPoint contract
- BaseAccount abstraction
- UserOperation validation
- Paymaster patterns

**Lux Extensions**:
- `contracts/account/` - Lux-specific account implementations
- Smart account factory with Lux precompiles
- Passkey validation modules

---

## Safe (Gnosis) Smart Accounts

### Safe Smart Account v1.5.0
**Source**: [safe-smart-account](https://github.com/safe-global/safe-smart-account)
**Audits**:
- [Ackee Blockchain (2024)](https://github.com/safe-global/safe-smart-account/tree/main/docs/audit_reports)
- [G0 Group (2024)](https://github.com/safe-global/safe-smart-account/tree/main/docs/audit_reports)
- [OpenZeppelin (2023)](https://github.com/safe-global/safe-smart-account/tree/main/docs/audit_reports)
- [Runtime Verification (2023)](https://github.com/safe-global/safe-smart-account/tree/main/docs/audit_reports)

**Used For**:
- Multi-signature wallet
- Safe core (Safe.sol, SafeL2.sol)
- Module management
- Guard functionality
- Fallback handlers

**Lux Extensions**:
- `contracts/safe/` - Lux Safe integrations
- Lamport signature support
- Quantum-resistant fallback

### Safe Modules v0.1.0
**Source**: [safe-modules](https://github.com/safe-global/safe-modules)
**Audits**:
- [Ackee Blockchain (2024)](https://github.com/safe-global/safe-modules/tree/main/docs/audit_reports)

**Used For**:
- Passkey module (WebAuthn)
- 4337 module (Account Abstraction)
- Allowance module
- Session keys

---

## DeFi Primitives

### Uniswap v3 Core v1.0.1
**Source**: [v3-core](https://github.com/Uniswap/v3-core)
**Audits**:
- [Trail of Bits (2021)](https://github.com/Uniswap/v3-core/tree/main/audits)
- [ABDK (2021)](https://github.com/Uniswap/v3-core/tree/main/audits)

**Used For**:
- Concentrated liquidity math
- Tick management
- Oracle integration

### Uniswap v3 Periphery v1.4.4
**Source**: [v3-periphery](https://github.com/Uniswap/v3-periphery)
**Audits**: Same as v3-core

**Used For**:
- Swap router patterns
- Liquidity management
- Position NFTs

### Uniswap v2 Core v1.0.1
**Source**: [v2-core](https://github.com/Uniswap/v2-core)
**Audits**:
- [dapp.org (2020)](https://uniswap.org/audit.html)

**Used For**:
- AMM pair patterns
- LP token standards

### Seaport v1.6.0
**Source**: [seaport](https://github.com/ProjectOpenSea/seaport)
**Audits**:
- [OpenZeppelin (2022)](https://github.com/ProjectOpenSea/seaport/tree/main/audits)
- [Trail of Bits (2022)](https://github.com/ProjectOpenSea/seaport/tree/main/audits)

**Used For**:
- NFT marketplace patterns
- Order fulfillment
- Conduit system

---

## Utilities

### Solmate v6.8.0
**Source**: [solmate](https://github.com/transmissions11/solmate)
**Audits**: Community reviewed, gas-optimized implementations

**Used For**:
- Gas-efficient ERC20
- Owned pattern
- SafeTransferLib
- FixedPointMathLib

### Clones with Immutable Args v1.1.2
**Source**: [clones-with-immutable-args](https://github.com/wighawag/clones-with-immutable-args)
**Audits**: Community reviewed

**Used For**:
- Minimal proxy clones
- Immutable argument passing

---

## Lux-Specific Contracts

These are Lux-original contracts (not based on external audited code):

### Core Tokens
| Contract | Description | Based On |
|----------|-------------|----------|
| LRC20 | Lux ERC-20 standard | OpenZeppelin ERC20 |
| LRC721 | Lux ERC-721 standard | OpenZeppelin ERC721 |
| LRC1155 | Lux ERC-1155 standard | OpenZeppelin ERC1155 |
| LRC4626 | Lux ERC-4626 vault | OpenZeppelin ERC4626 |
| LBTC | Wrapped Bitcoin on Lux | OpenZeppelin ERC20 |
| LETH | Wrapped Ether on Lux | OpenZeppelin ERC20 |

### Crypto (Novel)
| Contract | Description | Audit Status |
|----------|-------------|--------------|
| LamportBase | Lamport signature base | Pending |
| LamportLib | Lamport utilities | Pending |

### Governance
| Contract | Description | Based On |
|----------|-------------|----------|
| GuardableModule | Safe module base | Zodiac/Safe |
| DAO | DAO framework | OpenZeppelin Governor |
| Vote | Voting mechanism | OpenZeppelin Votes |

### AI Contracts (Novel)
| Contract | Description | Audit Status |
|----------|-------------|--------------|
| AIMining | AI compute mining | Pending |
| AIToken | AI utility token | Pending |
| ComputeMarket | AI compute marketplace | Pending |

---

## Version Matrix

| Library | Version | Solidity | License |
|---------|---------|----------|---------|
| openzeppelin-contracts | 5.1.0 | ^0.8.20 | MIT |
| openzeppelin-contracts-upgradeable | 4.9.0 | ^0.8.0 | MIT |
| account-abstraction | 0.9.0 | ^0.8.23 | GPL-3.0 |
| safe-smart-account | 1.5.0 | ^0.8.20 | LGPL-3.0 |
| safe-modules | 0.1.0 | ^0.8.20 | LGPL-3.0 |
| solmate | 6.8.0 | ^0.8.0 | AGPL-3.0 |
| seaport | 1.6.0 | ^0.8.24 | MIT |
| v3-core | 1.0.1 | ^0.8.0 | BUSL-1.1 |
| v3-periphery | 1.4.4 | ^0.8.0 | GPL-2.0 |
| forge-std | 1.11.0 | ^0.8.0 | MIT |

---

## Import Paths

```solidity
// OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// Lux Standard (uses OpenZeppelin under the hood)
import "@luxfi/standard/lib/token/ERC20/ERC20.sol";

// Safe
import "@safe-global/safe-smart-account/Safe.sol";
import "@safe-global/safe-modules/passkey/PasskeyModule.sol";

// Account Abstraction
import "@account-abstraction/core/EntryPoint.sol";
import "@account-abstraction/interfaces/IAccount.sol";

// DeFi
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@seaport/main/Seaport.sol";

// Utilities
import "@solmate/tokens/ERC20.sol";
import "clones-with-immutable-args/Clone.sol";
```

---

## Security Model

### Thin Shim Philosophy
Lux Standard follows a "thin shim" approach:

1. **Use Audited Code**: All core functionality comes from audited libraries
2. **Minimal Extensions**: Lux-specific code only adds thin wrappers
3. **No Modification**: We don't modify audited contract internals
4. **Composition Over Inheritance**: Prefer composing contracts over deep inheritance

### Audit Status
| Category | Coverage | Status |
|----------|----------|--------|
| Token Standards | 100% | ✅ Audited (OpenZeppelin) |
| Account Abstraction | 95% | ✅ Audited (eth-infinitism) |
| Safe/Multisig | 100% | ✅ Audited (Safe Global) |
| Governance | 90% | ✅ Audited (OpenZeppelin) |
| DeFi | 100% | ✅ Audited (Uniswap/Seaport) |
| AI Contracts | 0% | ⚠️ Pending Audit |
| Lamport Crypto | 0% | ⚠️ Pending Audit |

---

## Updating Dependencies

```bash
# Update all dependencies
forge update

# Install specific version
forge install openzeppelin/openzeppelin-contracts@v5.1.0

# Check versions
forge tree
```

---

*Last Updated: 2024-12-22*
*Maintained by: Lux Industries Inc.*
