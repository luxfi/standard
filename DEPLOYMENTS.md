# Contract Deployments

All deployed contracts across the Lux ecosystem networks.

**Deploy Script**: `DeployMultiNetwork.s.sol`
**C-Chain Deployed**: 2026-02-26 | **Subnet Chains Deployed**: 2026-03-04
**Last Verified**: 2026-03-04 (on-chain audit)

## Network Chain IDs

| Network | Chain ID | Explorer |
|---------|----------|----------|
| Lux Mainnet | 96369 | [explore.lux.network](https://explore.lux.network) |
| Lux Testnet | 96368 | - |
| Lux Devnet | 96370 | - |
| Zoo Mainnet | 200200 | [explore-zoo.lux.network](https://explore-zoo.lux.network) |
| Zoo Testnet | 200201 | - |
| Zoo Devnet | 200202 | - |
| Hanzo Mainnet | 36963 | [explore-hanzo.lux.network](https://explore-hanzo.lux.network) |
| Hanzo Testnet | 36964 | - |
| Hanzo Devnet | 36964 | - |
| SPC Mainnet | 36911 | [explore-spc.lux.network](https://explore-spc.lux.network) |
| SPC Testnet | 36910 | - |
| SPC Devnet | 36912 | - |
| Pars Mainnet | 494949 | [explore-pars.lux.network](https://explore-pars.lux.network) |
| Pars Testnet | 7071 | - |
| Pars Devnet | 494951 | - |

## Lux Mainnet (Chain ID: 96369) — 20/20 DEPLOYED

All contracts verified on-chain 2026-02-27.

| Contract | Address | Status |
|----------|---------|--------|
| WLUX | `0x3C18bB6B17eb3F0879d4653e0120a531aF4d86E3` | DEPLOYED |
| LETH (BridgedETH) | `0x5a88986958ea76Dd043f834542724F081cA1443B` | DEPLOYED |
| LBTC (BridgedBTC) | `0x8a3fad1c7FB94461621351aa6A983B6f814F039c` | DEPLOYED |
| LUSDC (BridgedUSDC) | `0x57f9E717dc080a6A76fB6F77BecA8C9C1D266B96` | DEPLOYED |
| StakedLUX (sLUX) | `0xc606302cd0722DD42c460B09930477d09993F913` | DEPLOYED |
| AMMV2Factory | `0xb06B31521Afc434F87Fe4852c98FC15A26c92aE8` | DEPLOYED (1 pair) |
| AMMV2Router | `0x6A1a32BF731d504122EA318cE7Bd8D92b2284C0d` | DEPLOYED |
| Timelock | `0xe0C921834384a993963414d6EAA79101C60A59Df` | DEPLOYED |
| vLUX | `0x55833074AD22E2aAE81ad377A600340eC0bc7cbd` | DEPLOYED |
| GaugeController | `0xF207Cf7f1cC372374e54d174B2E184a10417b0F6` | DEPLOYED |
| Karma | `0xc3d1efb6Eaedd048dDfE7066F1c719C7B6Ca43ad` | DEPLOYED |
| DLUX | `0xAAbD65c4Fe3d3f9d54A7C3C7B95B9eD359CC52A8` | DEPLOYED |
| DIDRegistry | `0xe494b658d1C08a56b8783a36A78E777AD282fCC3` | DEPLOYED |
| FeeGov | `0xE7738632E5c84bE3e5421CC691d9fEF5DFb0cCB6` | DEPLOYED |
| ValidatorVault | `0x2BaeF607871FB40515Fb42A299a1E0b03F0C681f` | DEPLOYED |
| LinearCurve | `0x360149cC47A3996522376E4131b4A6eB2A1Ca3D3` | DEPLOYED |
| ExponentialCurve | `0x28EBC6764A1c7Ed47b38772E197761102b08f3bb` | DEPLOYED |
| LSSVMPairFactory | `0x29E3E018C3C19F7713B2dffa3A3c340fD2c7089E` | DEPLOYED |
| Markets | `0x308EBD39eB5E27980944630A0af6F8B0d19e31C6` | DEPLOYED |
| Perp | `0x82312E295533Ab5167B306d5aBF7F3eB2C0D95fD` | DEPLOYED |

### Legacy AMM Addresses — NOT DEPLOYED

These addresses appear in the exchange UI config but have **no code on-chain**. Do not use.

| Contract | Address | Status |
|----------|---------|--------|
| WLUX (old) | `0x55750d6CA62a041c06a8E28626b10Be6c688f471` | EMPTY |
| Multicall | `0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F` | EMPTY |
| UniswapV2Factory | `0xd9a95609DbB228A13568Bd9f9A285105E7596970` | EMPTY |
| UniswapV2Router02 | `0x1F6cbC7d3bc7D803ee76D80F0eEE25767431e674` | EMPTY |
| UniswapV3Factory | `0xb732BD88F25EdD9C3456638671fB37685D4B4e3f` | EMPTY |

## Lux Testnet (Chain ID: 96368) / Lux Devnet (Chain ID: 96370) — 20/20 DEPLOYED

Both networks share addresses (deployer had same nonce). All verified on-chain 2026-02-27.

| Contract | Address | Status |
|----------|---------|--------|
| WLUX | `0xDe5310d0Eccc04C8987cB66Ff6b89Ee793442C91` | DEPLOYED |
| LETH | `0xa695A8a66fbe3e32d15a531Db04185313595771a` | DEPLOYED |
| LBTC | `0x5a88986958ea76Dd043f834542724F081cA1443B` | DEPLOYED |
| LUSDC | `0x8a3fad1c7FB94461621351aa6A983B6f814F039c` | DEPLOYED |
| StakedLUX | `0xA26440c18Fdb48CD5231ffb9Ec93c19Ea0618563` | DEPLOYED |
| AMMV2Factory | `0x1dD4E6cbC6B8fD032FCad5a3b0a45E446A014637` | DEPLOYED |
| AMMV2Router | `0xb06B31521Afc434F87Fe4852c98FC15A26c92aE8` | DEPLOYED |
| Timelock | `0x96a70BAE4e0a6B894ae12dF9b68cedcDb1FFa99f` | DEPLOYED |
| vLUX | `0xe0C921834384a993963414d6EAA79101C60A59Df` | DEPLOYED |
| GaugeController | `0x55833074AD22E2aAE81ad377A600340eC0bc7cbd` | DEPLOYED |
| Karma | `0xF207Cf7f1cC372374e54d174B2E184a10417b0F6` | DEPLOYED |
| DLUX | `0xc3d1efb6Eaedd048dDfE7066F1c719C7B6Ca43ad` | DEPLOYED |
| DIDRegistry | `0xAAbD65c4Fe3d3f9d54A7C3C7B95B9eD359CC52A8` | DEPLOYED |
| FeeGov | `0xe494b658d1C08a56b8783a36A78E777AD282fCC3` | DEPLOYED |
| ValidatorVault | `0xE7738632E5c84bE3e5421CC691d9fEF5DFb0cCB6` | DEPLOYED |
| LinearCurve | `0x2BaeF607871FB40515Fb42A299a1E0b03F0C681f` | DEPLOYED |
| ExponentialCurve | `0x360149cC47A3996522376E4131b4A6eB2A1Ca3D3` | DEPLOYED |
| LSSVMPairFactory | `0x28EBC6764A1c7Ed47b38772E197761102b08f3bb` | DEPLOYED |
| Markets | `0x49B76d9ca9BcA9e9eDef5e2EC4eD425b2e6b2445` | DEPLOYED |
| Perp | `0x308EBD39eB5E27980944630A0af6F8B0d19e31C6` | DEPLOYED |

## Testnet Subnet Chains — Pre-v5 (Addresses may be stale)

These were deployed pre-v5 re-genesis. Testnet subnets may have been wiped. Verify on-chain before use.

**Testnet**: Zoo (200201), Hanzo (36964), SPC (36910), Pars (7071)
**Devnet**: Zoo (200202), Hanzo (36964), SPC (36912), Pars (494951)

## Zoo Mainnet (Chain ID: 200200) — 20/20 DEPLOYED

Deployed 2026-03-04 via `DeployMultiNetwork.s.sol`. Deployer: `0x9011E888251AB053B7bD1cdB598Db4f9DEd94714`

| Contract | Address | Status |
|----------|---------|--------|
| WLUX | `0x5491216406daB99b7032b83765F36790E27F8A61` | DEPLOYED |
| LETH (BridgedETH) | `0x4870621EA8be7a383eFCfdA225249d35888bD9f2` | DEPLOYED |
| LBTC (BridgedBTC) | `0x6fc44509a32E513bE1aa00d27bb298e63830C6A8` | DEPLOYED |
| LUSDC (BridgedUSDC) | `0xb2ee1CE7b84853b83AA08702aD0aD4D79711882D` | DEPLOYED |
| StakedLUX (sLUX) | `0x742202418235B225bD77Ee5BA9C4cBa416Aeb17d` | DEPLOYED |
| AMMV2Factory | `0xF034942c1140125b5c278aE9cEE1B488e915B2FE` | DEPLOYED |
| AMMV2Router | `0x2cd306913e6546C59249b48d7c786A6D1d7ebE08` | DEPLOYED |
| Timelock | `0x7126daf151666e92F8B5D915F9fAf3CDaA7918Ce` | DEPLOYED |
| vLUX | `0xc23e396acA1CbB0D0cF1debc8371eDddbf52430e` | DEPLOYED |
| GaugeController | `0x8C241Bcc7735AA4f21B9e488AC93B22058257264` | DEPLOYED |
| Karma | `0xb2eaA0b9F04184102AB92c443Ad8F4454798fC8b` | DEPLOYED |
| DLUX | `0x7c05e692995e14994a5482dE3F97F712B72838C9` | DEPLOYED |
| DIDRegistry | `0xC23BEB821252D22835B60767C7eFBE06B2f62789` | DEPLOYED |
| FeeGov | `0xeA65F4dDdF09D8CDb8a1E2bCbC77c01567a75326` | DEPLOYED |
| ValidatorVault | `0xEaFFaDf661D82df7871d2E4085C39defc792A1c7` | DEPLOYED |
| LinearCurve | `0x719685C371ce4C4720d3D7877CBf9bc867Ac39a6` | DEPLOYED |
| ExponentialCurve | `0xB4e242f9417872A843B2D0b92FCf89055349ABb5` | DEPLOYED |
| LSSVMPairFactory | `0x60b2d8E6B5B0FEeE529DcC6c460C44eed7b2E82A` | DEPLOYED |
| Markets | `0x6B7D3c38A3e030B95E101927Ee6ff9913ef626d4` | DEPLOYED |
| Perp | `0x58A86aAFB6Cdd0989c799353C891E420Fb530e0a` | DEPLOYED |

## Hanzo Mainnet (Chain ID: 36963) — 20/20 DEPLOYED

Deployed 2026-03-04 via `DeployMultiNetwork.s.sol`. Deployer: `0x9011E888251AB053B7bD1cdB598Db4f9DEd94714`

| Contract | Address | Status |
|----------|---------|--------|
| WLUX | `0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec` | DEPLOYED |
| LETH (BridgedETH) | `0x9378b62fC172d2A4f715d7ecF49DE0362f1BB702` | DEPLOYED |
| LBTC (BridgedBTC) | `0x7fC4f8a926E47Fa3587C0d7658C00E7489e67916` | DEPLOYED |
| LUSDC (BridgedUSDC) | `0x51c3408B9A6a0B2446CCB78c72C846CEB76201FA` | DEPLOYED |
| StakedLUX (sLUX) | `0x977afeE2D1043ecdBc27ff530329837286457988` | DEPLOYED |
| AMMV2Factory | `0xDc384E006BAec602b0b2B2fe6f2712646EFb1e9D` | DEPLOYED |
| AMMV2Router | `0x191067f88d61f9506555E88CEab9CF71deeD61A9` | DEPLOYED |
| Timelock | `0xC63287d85BAe3628f1b824F6D9C2cfADc22F987F` | DEPLOYED |
| vLUX | `0xDd30113b484671A35Ca236ec5A97C1c5327d72FA` | DEPLOYED |
| GaugeController | `0xa1a2cE4377fee42b09Da6376d4887156FeE54c8b` | DEPLOYED |
| Karma | `0x58604f58fC8b6Bf9E8719BA5BA03F2EA586161bB` | DEPLOYED |
| DLUX | `0x48214d4B54432c1037C210bEE96e840F697Bd3ed` | DEPLOYED |
| DIDRegistry | `0x08ae70233ff8d34EcD03299D3c9019F0D1A2Dc71` | DEPLOYED |
| FeeGov | `0x7d0A0401284aC2081721B873187958f55C241059` | DEPLOYED |
| ValidatorVault | `0xf3a126C12EE4f413573B8a32a36953Bd43719E30` | DEPLOYED |
| LinearCurve | `0x9607F59f2377Dff9A56D0A76F0313040070c08CD` | DEPLOYED |
| ExponentialCurve | `0xdE5280a9306da7829A4Ba1fBf87B58e1bB4F4A53` | DEPLOYED |
| LSSVMPairFactory | `0x38E71f39f3f46907E03C48983F6578F9a8c2e72e` | DEPLOYED |
| Markets | `0x9BC44B0De1aBe2e436C8fA5Cd5cA519026b9D8fD` | DEPLOYED |
| Perp | `0x3153c91b6b7f29Cc6BCE51FfF639dA658Bd75363` | DEPLOYED |

## SPC Mainnet (Chain ID: 36911) — NOT DEPLOYED

Genesis-funded address `0x12c6EE1d226225756F57B75957d2BF3Ab2e8597e` has 1B LUX.
Private key unknown (not derivable from project mnemonic). Deployment blocked until key is provided.

## Pars Mainnet (Chain ID: 494949) — 20/20 DEPLOYED

Deployed 2026-03-04 via `DeployMultiNetwork.s.sol`. Deployer: `0xEAbCC110fAcBfebabC66Ad6f9E7B67288e720B59`

| Contract | Address | Status |
|----------|---------|--------|
| WLUX | `0x548F54Dfb32ea6cE4fa3515236696CF3d1b7D26a` | DEPLOYED |
| LETH (BridgedETH) | `0xe0f7E9A0cB1688ccA453995fd6e19AE4fbD9cBfd` | DEPLOYED |
| LBTC (BridgedBTC) | `0x7d7cC8D05BB0F38D80b5Ce44b4b069A6FB769468` | DEPLOYED |
| LUSDC (BridgedUSDC) | `0xC5e4A6f54Be469551a342872C1aB83AB46f61b22` | DEPLOYED |
| StakedLUX (sLUX) | `0xAB95c8b59f68ce922f2f334dFc8bb8f5b0525326` | DEPLOYED |
| AMMV2Factory | `0x84CF0A13db1be8e1F0676405cfcBC8b09692FD1C` | DEPLOYED |
| AMMV2Router | `0x2382F7A49FA48E1F91Bec466c32e1D7F13ec8206` | DEPLOYED |
| Timelock | `0x1f4989a809774CEa35100529690AacAF289f1dc3` | DEPLOYED |
| vLUX | `0x51b74dc77FcCA83ECc2c5c70782c6eAC27eA6197` | DEPLOYED |
| GaugeController | `0x09ab488a7434921AabC2fFF20AF955a62F524862` | DEPLOYED |
| Karma | `0x518ABA97Ec84851E1C68d571e2dA3Bd2fC0507A0` | DEPLOYED |
| DLUX | `0x18F1DF4f036AD993093F8eAd20dD62712dAC2996` | DEPLOYED |
| DIDRegistry | `0x6042014293591DE798Da8F40D50708d4497138D5` | DEPLOYED |
| FeeGov | `0x5f6dB1D3B6f41ffcb8987dbc392781A4C0020b30` | DEPLOYED |
| ValidatorVault | `0x50DE09aFe31Af68aCAF7d6dD7f6fE40ae190d564` | DEPLOYED |
| LinearCurve | `0xd13AB81F02449B1630ecd940Be5Fb9CD367225B4` | DEPLOYED |
| ExponentialCurve | `0xBc92f4e290F8Ad03F5348F81a27fb2Af3B37ec47` | DEPLOYED |
| LSSVMPairFactory | `0xb43dB9AF0C5CACb99f783E30398Ee0AEe6744212` | DEPLOYED |
| Markets | `0x3589fd09e7dfF3f7653fc4965B7CE1b8d8fdA9Bd` | DEPLOYED |
| Perp | `0xd984fED38C98C1eab66E577fd1DdC8dCD88eA799` | DEPLOYED |

### Devnet — Not Yet Deployed

Devnet at `api.lux-dev.network` has 5 separate nodes. Contracts need deployment when ready.

## Ethereum Mainnet (Chain ID: 1)

### Teleport Bridge Tokens

| Contract | Address |
|----------|---------|
| LBTC | `0x526903Ee6118de6737D11b37f82fC7f69B13685D` |
| LETH | `0xAA3AE951A7925F25aE8Ad65b052a76Bd8f052598` |
| Teleport | `0x60D9B4552b67792D4E65B4D3e27de0EfbCd219bA` |

## Precompile Addresses

| Precompile | Address | Description |
|------------|---------|-------------|
| DeployerAllowList | `0x0200...0001` | Deployer permissions |
| TxAllowList | `0x0200...0002` | Transaction permissions |
| FeeManager | `0x0200...0003` | Dynamic fee management |
| NativeMinter | `0x0200...0004` | Native token minting |
| Warp | `0x0200...0005` | Cross-chain messaging |
| RewardManager | `0x0200...0006` | Validator rewards |
| ML-DSA | `0x0200...0007` | Post-quantum signatures |
| Quasar | `0x0200...000A` | Quantum consensus |
| Ringtail | `0x0200...000B` | Threshold lattice signatures |
| FROST | `0x0200...000C` | Schnorr threshold signatures |
| CGGMP21 | `0x0200...000D` | ECDSA threshold signatures |

## Deployment

```bash
# Deploy standard DeFi stack to any chain
LUX_PRIVATE_KEY=0x... forge script contracts/script/DeployMultiNetwork.s.sol \
  --rpc-url <RPC_URL> --broadcast -vvv
```

Source: [github.com/luxfi/standard](https://github.com/luxfi/standard) | npm: [@luxfi/contracts](https://www.npmjs.com/package/@luxfi/contracts)
