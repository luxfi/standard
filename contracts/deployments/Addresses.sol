// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Lux Addresses - Canonical contract addresses across all Lux networks
// Source of truth: ~/work/lux/exchange/packages/exchange/src/contracts/addresses.ts
//
// Usage:
//   import {LuxMainnet, LuxTestnet, ZooMainnet} from "@lux/standard/deployments/Addresses.sol";
//   address router = LuxMainnet.V3_SWAP_ROUTER;

// ============ Chain IDs ============
uint256 constant LUX_MAINNET_CHAIN_ID = 96369;
uint256 constant LUX_TESTNET_CHAIN_ID = 96368;
uint256 constant ZOO_MAINNET_CHAIN_ID = 200200;
uint256 constant ZOO_TESTNET_CHAIN_ID = 200201;
uint256 constant LUX_DEV_CHAIN_ID = 1337;

/**
 * @title Lux Mainnet Addresses (Chain ID: 96369)
 */
library LuxMainnet {
    // Core
    address constant WLUX = 0x55750d6CA62a041c06a8E28626b10Be6c688f471;
    address constant MULTICALL3 = 0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F;

    // Bridge Tokens
    address constant LETH = 0xAA3AE95816A4a6FBC6B8eD5A6c06f22A96A80C8c;
    address constant LBTC = 0x526903E35e7106D62Ed3B5d77E14e51D024aA1D3;
    address constant LUSD = 0x4b1bFA76Ed63F1A0aD2e4F40b3F46c45e8f7A4e2;

    // AMM V2 (QuantumSwap)
    address constant V2_FACTORY = 0xd9a95609DbB228A13568Bd9f9A285105E7596970;
    address constant V2_ROUTER = 0x1F6cbC7d3bc7D803ee76D80F0eEE25767431e674;

    // AMM V3 (Concentrated Liquidity)
    address constant V3_FACTORY = 0xb732BD88F25EdD9C3456638671fB37685D4B4e3f;
    address constant V3_SWAP_ROUTER = 0xE8fb25086C8652c92f5AF90D730Bac7C63Fc9A58;
    address constant V3_SWAP_ROUTER_02 = 0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E;
    address constant V3_QUOTER = 0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275;
    address constant V3_QUOTER_V2 = 0x15C729fdd833Ba675edd466Dfc63E1B737925A4c;
    address constant V3_TICK_LENS = 0x57A22965AdA0e52D785A9Aa155beF423D573b879;
    address constant V3_NFT_POSITION_MANAGER = 0x7a4C48B9dae0b7c396569b34042fcA604150Ee28;
    address constant V3_NFT_DESCRIPTOR = 0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5;
}

/**
 * @title Lux Testnet Addresses (Chain ID: 96368)
 */
library LuxTestnet {
    // Core
    address constant WLUX = 0x732740c5c895C9FCF619930ed4293fc858eb44c7;
    address constant WETH = 0xd9956542B51032d940ef076d70B69410667277A3;
    address constant MULTICALL3 = 0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F;

    // Bridge Tokens
    address constant LETH = 0x60E0a8167FC13dE89348978860466C9ceC24B9ba;
    address constant LBTC = 0x1E48D32a4F5e9f08DB9aE4959163300FaF8A6C8e;
    address constant LUSD = 0xB84112AC9318a0B2319aa11d4D10E9762b25F7F4;

    // AMM V2
    address constant V2_FACTORY = 0x81C3669B139D92909AA67DbF74a241b10540d919;
    address constant V2_ROUTER = 0xDB6c703c80BFaE5F9a56482d3c8535f27E1136EB;

    // AMM V3
    address constant V3_FACTORY = 0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84;
    address constant V3_SWAP_ROUTER = 0xE8fb25086C8652c92f5AF90D730Bac7C63Fc9A58;
    address constant V3_SWAP_ROUTER_02 = 0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E;
    address constant V3_QUOTER = 0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275;
    address constant V3_QUOTER_V2 = 0x15C729fdd833Ba675edd466Dfc63E1B737925A4c;
    address constant V3_TICK_LENS = 0x57A22965AdA0e52D785A9Aa155beF423D573b879;
    address constant V3_NFT_POSITION_MANAGER = 0x7a4C48B9dae0b7c396569b34042fcA604150Ee28;
    address constant V3_NFT_DESCRIPTOR = 0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5;
}

/**
 * @title Zoo Mainnet Addresses (Chain ID: 200200)
 */
library ZooMainnet {
    // Core
    address constant WZOO = 0x4888E4a2Ee0F03051c72D2BD3ACf755eD3498B3E;
    address constant MULTICALL3 = 0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F;

    // AMM V2
    address constant V2_FACTORY = 0xD173926A10A0C4eCd3A51B1422270b65Df0551c1;
    address constant V2_ROUTER = 0xAe2cf1E403aAFE6C05A5b8Ef63EB19ba591d8511;

    // AMM V3
    address constant V3_FACTORY = 0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84;
    address constant V3_SWAP_ROUTER_02 = 0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E;
    address constant V3_QUOTER = 0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275;
    address constant V3_TICK_LENS = 0x57A22965AdA0e52D785A9Aa155beF423D573b879;
    address constant V3_NFT_POSITION_MANAGER = 0x7a4C48B9dae0b7c396569b34042fcA604150Ee28;

    // Z-Tokens (bridged assets)
    address constant ZETH = 0x60E0a8167FC13dE89348978860466C9ceC24B9ba;
    address constant ZBTC = 0x1E48D32a4F5e9f08DB9aE4959163300FaF8A6C8e;
    address constant ZUSD = 0x848Cff46eb323f323b6Bbe1Df274E40793d7f2c2;
    address constant ZLUX = 0x5E5290f350352768bD2bfC59c2DA15DD04A7cB88;
    address constant ZSOL = 0x26B40f650156C7EbF9e087Dd0dca181Fe87625B7;
    address constant ZBNB = 0x6EdcF3645DeF09DB45050638c41157D8B9FEa1cf;
    address constant ZPOL = 0x28BfC5DD4B7E15659e41190983e5fE3df1132bB9;
    address constant ZCELO = 0x3078847F879A33994cDa2Ec1540ca52b5E0eE2e5;
    address constant ZFTM = 0x8B982132d639527E8a0eAAD385f97719af8f5e04;
    address constant ZTON = 0x3141b94b89691009b950c96e97Bff48e0C543E3C;

    // Known Pools
    address constant POOL_WZOO_ZUSD_30BPS = 0x37011bB281676f85962fb35C674f7E9EB7584452;
    address constant POOL_WZOO_ZLUX_30BPS = 0x1c000d5dbE1246Fb84Ad431e933E5563F212A62b;
}

/**
 * @title Zoo Testnet Addresses (Chain ID: 200201)
 */
library ZooTestnet {
    // Core
    address constant WZOO = 0x4888E4a2Ee0F03051c72D2BD3ACf755eD3498B3E;
    address constant MULTICALL3 = 0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F;

    // AMM V2
    address constant V2_FACTORY = 0xD173926A10A0C4eCd3A51B1422270b65Df0551c1;
    address constant V2_ROUTER = 0xAe2cf1E403aAFE6C05A5b8Ef63EB19ba591d8511;

    // AMM V3
    address constant V3_FACTORY = 0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84;
    address constant V3_SWAP_ROUTER_02 = 0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E;
    address constant V3_QUOTER = 0x12e2B76FaF4dDA5a173a4532916bb6Bfa3645275;
    address constant V3_TICK_LENS = 0x57A22965AdA0e52D785A9Aa155beF423D573b879;
    address constant V3_NFT_POSITION_MANAGER = 0x7a4C48B9dae0b7c396569b34042fcA604150Ee28;
}

/**
 * @title Lux Dev Addresses (Chain ID: 1337)
 * @dev Deterministic CREATE addresses from DeployFullStack.s.sol deployed by anvil account 0
 */
library LuxDev {
    // Core (Nonce 0)
    address constant WLUX = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant MULTICALL3 = 0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F;

    // Bridge Tokens (Deterministic deployment nonces 1-3)
    address constant LETH = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // Nonce 1
    address constant LBTC = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0; // Nonce 2
    address constant LUSD = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9; // Nonce 3

    // AMM V2
    address constant V2_FACTORY = 0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1;
    address constant V2_ROUTER = 0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE;

    // Staking
    address constant STAKED_LUX = 0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0;
}

/**
 * @title DEX Precompiles (Native AMM)
 * @notice Precompile addresses for native DEX functionality
 * @dev Address format: 0x0000...00LPNUMBER (addresses end with LP number)
 */
library DexPrecompiles {
    // Core DEX (LP-9010 series - Uniswap v4 style)
    address constant POOL_MANAGER = 0x0000000000000000000000000000000000009010;     // LP-9010
    address constant ORACLE_HUB = 0x0000000000000000000000000000000000009011;       // LP-9011
    address constant SWAP_ROUTER = 0x0000000000000000000000000000000000009012;      // LP-9012
    address constant HOOKS_REGISTRY = 0x0000000000000000000000000000000000009013;   // LP-9013
    address constant FLASH_LOAN = 0x0000000000000000000000000000000000009014;       // LP-9014
    address constant CLOB = 0x0000000000000000000000000000000000009020;             // LP-9020
    address constant VAULT = 0x0000000000000000000000000000000000009030;            // LP-9030

    // Bridges (LP-6xxx)
    address constant TELEPORT = 0x0000000000000000000000000000000000006010;         // LP-6010
}

/**
 * @title AddressResolver
 * @notice Helper to resolve addresses by chain ID
 */
library AddressResolver {
    error UnsupportedChainId(uint256 chainId);

    function getV3Factory(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET_CHAIN_ID) return LuxMainnet.V3_FACTORY;
        if (chainId == LUX_TESTNET_CHAIN_ID) return LuxTestnet.V3_FACTORY;
        if (chainId == ZOO_MAINNET_CHAIN_ID) return ZooMainnet.V3_FACTORY;
        if (chainId == ZOO_TESTNET_CHAIN_ID) return ZooTestnet.V3_FACTORY;
        revert UnsupportedChainId(chainId);
    }

    function getV3Router(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET_CHAIN_ID) return LuxMainnet.V3_SWAP_ROUTER_02;
        if (chainId == LUX_TESTNET_CHAIN_ID) return LuxTestnet.V3_SWAP_ROUTER_02;
        if (chainId == ZOO_MAINNET_CHAIN_ID) return ZooMainnet.V3_SWAP_ROUTER_02;
        if (chainId == ZOO_TESTNET_CHAIN_ID) return ZooTestnet.V3_SWAP_ROUTER_02;
        revert UnsupportedChainId(chainId);
    }

    function getWrappedNative(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET_CHAIN_ID) return LuxMainnet.WLUX;
        if (chainId == LUX_TESTNET_CHAIN_ID) return LuxTestnet.WLUX;
        if (chainId == ZOO_MAINNET_CHAIN_ID) return ZooMainnet.WZOO;
        if (chainId == ZOO_TESTNET_CHAIN_ID) return ZooTestnet.WZOO;
        if (chainId == LUX_DEV_CHAIN_ID) return LuxDev.WLUX;
        revert UnsupportedChainId(chainId);
    }

    function getMulticall3(uint256 chainId) internal pure returns (address) {
        // Multicall3 is deployed at same address on all chains
        if (chainId == LUX_MAINNET_CHAIN_ID) return LuxMainnet.MULTICALL3;
        if (chainId == LUX_TESTNET_CHAIN_ID) return LuxTestnet.MULTICALL3;
        if (chainId == ZOO_MAINNET_CHAIN_ID) return ZooMainnet.MULTICALL3;
        if (chainId == ZOO_TESTNET_CHAIN_ID) return ZooTestnet.MULTICALL3;
        if (chainId == LUX_DEV_CHAIN_ID) return LuxDev.MULTICALL3;
        revert UnsupportedChainId(chainId);
    }
}
