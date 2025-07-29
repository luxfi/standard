# Lux Standard Repository Migration Notes

## Overview
This document summarizes the migration from ZOO/Eggs references to LUX and from Hardhat/TypeScript testing to Foundry/Solidity testing.

## Changes Made

### 1. File Renames
- `src/ZOO.sol` → `src/LUX.sol` (contract already used LUX internally)
- `src/EGGDrop.sol` → `src/DropNFTs.sol` (contract already used DropNFTs internally)
- `deploy/17_EggDrop.ts` → `deploy/17_DropNFTs.ts`

### 2. Import Updates
- All `@zoolabs` imports changed to `@luxfi` in deploy scripts
- Updated deploy script references from 'ZOO' to 'LUX'
- Updated deploy script references from 'DropEggs' to 'DropNFTs'

### 3. Foundry Integration
Created new Foundry test structure:
- `foundry.toml` - Foundry configuration
- `remappings.txt` - Import path mappings
- `Makefile` - Common Foundry commands
- `.env.example` - Environment variables template

### 4. Test Migration
Created Foundry tests in `test/foundry/`:
- `LUX.t.sol` - Comprehensive tests for LUX token
- `Lamport.t.sol` - Tests for Lamport signature implementation
- `TestHelpers.sol` - Common test utilities
- `README.md` - Documentation for running tests

### 5. Deployment Scripts
Created Foundry deployment scripts in `script/`:
- `Deploy.s.sol` - Deployment scripts for local/testnet/mainnet

### 6. Package.json Updates
Added Foundry commands alongside existing Hardhat commands:
- `npm run build` - Build with Foundry
- `npm run test` - Test with Foundry
- `npm run test:hardhat` - Test with Hardhat (legacy)
- `npm run deploy:local` - Deploy with Foundry

## Remaining Tasks

### High Priority
1. Install Foundry dependencies:
   ```bash
   forge install foundry-rs/forge-std --no-commit
   forge install openzeppelin/openzeppelin-contracts@v4.9.3 --no-commit
   ```

2. Update contract imports to use consistent OpenZeppelin version

3. Ensure main branch has latest from regenesis without losing Lamport implementation

### Medium Priority
1. Convert remaining Hardhat tests to Foundry
2. Update CI/CD pipelines to use Foundry
3. Remove Hardhat dependencies once migration is complete

### Low Priority
1. Optimize gas usage in contracts
2. Add more comprehensive fuzz tests
3. Document deployment procedures

## Lamport Implementation Status
The Lamport implementation in `src/lamport/` has been preserved:
- `LamportBase.sol` - Abstract base contract
- `LamportLib.sol` - Verification library
- `LamportTest.sol` - Test contract
- `LamportTest2.sol` - Additional test contract

Foundry tests have been created to ensure the implementation works correctly.

## Notes
- The contracts already used LUX naming internally, so minimal contract changes were needed
- Foundry provides better gas optimization and testing capabilities
- The migration maintains backward compatibility with existing deployments