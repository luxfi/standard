# @luxfi/contracts

This package is an alias for `@luxfi/standard`. Both packages are identical and maintained by the Lux Network team.

## Usage

```bash
# Install either package - they are equivalent
npm install @luxfi/contracts
# OR
npm install @luxfi/standard
```

## Solidity Imports

```solidity
// Both import paths work identically:
import {ERC20} from "@luxfi/contracts/tokens/ERC20.sol";
import {ERC20} from "@luxfi/standard/tokens/ERC20.sol";
```

## Why Two Packages?

- `@luxfi/standard` - The canonical package name following the repository name
- `@luxfi/contracts` - Alternative name for those who prefer the more descriptive name

Both packages are published from the same source code and are always in sync.

## Documentation

See [@luxfi/standard](https://www.npmjs.com/package/@luxfi/standard) for full documentation.
