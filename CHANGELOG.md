
## [1.1.0] - 2025-11-22

### Added
- AIRegistry: Universal identity registry (EVM-agnostic)
- AIRegistrySimple: Lightweight registry implementation
- OmnichainLP: Cross-chain liquidity pools
- OmnichainLPFactory: Pool factory contract
- OmnichainLPRouter: Routing for omnichain swaps

### Changed
- Reorganized contracts: separated core infrastructure from chain-specific implementations
- Moved AI-specific contracts (AIToken, AIFaucet) to AI repository
- Updated .gitignore to exclude build artifacts

### Infrastructure
- Post-quantum precompiles: ML-DSA (FIPS 204), SLH-DSA (FIPS 205)
- Deployment scripts for multiple EVM chains
- Foundry build configuration with dependency management

