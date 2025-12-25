// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/// @title ProtocolRegistry
/// @notice Registry of all supported DeFi protocols across chains
/// @dev Use this as reference for adapter development
library ProtocolRegistry {

    /*//////////////////////////////////////////////////////////////
                              EVM - DEX
    //////////////////////////////////////////////////////////////*/

    // Uniswap V4 (Singleton PoolManager)
    address constant UNISWAP_V4_POOL_MANAGER_ETH = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant UNISWAP_V4_ROUTER_ETH = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address constant UNISWAP_V4_POOL_MANAGER_OP = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
    address constant UNISWAP_V4_POOL_MANAGER_BSC = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;

    // Uniswap V3 (Ethereum, Arbitrum, Optimism, Polygon, Base, BSC, Avalanche)
    address constant UNISWAP_V3_ROUTER_ETH = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_V3_QUOTER_ETH = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address constant UNISWAP_V3_FACTORY_ETH = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // Uniswap V2 (Legacy but still used)
    address constant UNISWAP_V2_ROUTER_ETH = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant UNISWAP_V2_FACTORY_ETH = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    // PancakeSwap (BSC)
    address constant PANCAKE_V3_ROUTER_BSC = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address constant PANCAKE_V2_ROUTER_BSC = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // SushiSwap (Multi-chain)
    address constant SUSHI_ROUTER_ETH = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    // Curve Finance (Ethereum)
    address constant CURVE_ROUTER_ETH = 0x99a58482BD75cbab83b27EC03CA68fF489b5788f;
    address constant CURVE_REGISTRY_ETH = 0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5;

    // Balancer V2 (Ethereum)
    address constant BALANCER_VAULT_ETH = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // 1inch Aggregator (Multi-chain)
    address constant ONEINCH_ROUTER_ETH = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant ONEINCH_ROUTER_BSC = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant ONEINCH_ROUTER_ARB = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    // Camelot (Arbitrum)
    address constant CAMELOT_ROUTER_ARB = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    // TraderJoe (Avalanche)
    address constant TRADERJOE_ROUTER_AVAX = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;

    // Velodrome (Optimism)
    address constant VELODROME_ROUTER_OP = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;

    // Aerodrome (Base)
    address constant AERODROME_ROUTER_BASE = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    // Katana (Polygon CDK OP Stack) - Chain ID: 747474
    address constant KATANA_SUSHI_ROUTER = 0x0000000000000000000000000000000000000000; // TODO: Add actual address
    address constant KATANA_MORPHO = 0xD50F2DffFd62f94Ee4AEd9ca05C61d0753268aBc;
    address constant KATANA_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

    /*//////////////////////////////////////////////////////////////
                            EVM - LENDING
    //////////////////////////////////////////////////////////////*/

    // Aave V3 (Multi-chain)
    address constant AAVE_V3_POOL_ETH = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_V3_PROVIDER_ETH = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant AAVE_V3_POOL_ARB = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_V3_POOL_OP = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_V3_POOL_POLYGON = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_V3_POOL_BASE = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant AAVE_V3_POOL_AVAX = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    // Compound V3 (Comet)
    address constant COMPOUND_V3_USDC_ETH = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant COMPOUND_V3_WETH_ETH = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    address constant COMPOUND_V3_USDC_ARB = 0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA;
    address constant COMPOUND_V3_USDC_BASE = 0xb125E6687d4313864e53df431d5425969c15Eb2F;

    // Venus (BSC - Compound fork)
    address constant VENUS_COMPTROLLER_BSC = 0xfD36E2c2a6789Db23113685031d7F16329158384;

    // Radiant (Arbitrum)
    address constant RADIANT_POOL_ARB = 0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1;

    // Spark (Ethereum - MakerDAO)
    address constant SPARK_POOL_ETH = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;

    // Morpho (Ethereum)
    address constant MORPHO_BLUE_ETH = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    /*//////////////////////////////////////////////////////////////
                             EVM - PERPS
    //////////////////////////////////////////////////////////////*/

    // GMX V2 (Arbitrum, Avalanche)
    address constant GMX_ROUTER_ARB = 0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8;
    address constant GMX_VAULT_ARB = 0x489ee077994B6658eAfA855C308275EAd8097C4A;

    // Aster (BSC, Arbitrum) - Already integrated
    address constant ASTER_TRADING_BSC = 0x1b6F2d3844C6ae7D56ceb3C3643b9060ba28FEb0;

    // Gains Network (Arbitrum, Polygon)
    address constant GAINS_TRADING_ARB = 0xFF162c694eAA571f685030649814282eA457f169;

    // Kwenta (Optimism)
    address constant KWENTA_MARKET_OP = 0x1af06c904f7D7b8957A0a3B0fD4B1f0cf4F29551;

    /*//////////////////////////////////////////////////////////////
                            EVM - STAKING
    //////////////////////////////////////////////////////////////*/

    // Lido (Ethereum)
    address constant LIDO_STETH_ETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant LIDO_WSTETH_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    // Rocket Pool (Ethereum)
    address constant RETH_ETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // Frax (Ethereum)
    address constant SFRXETH_ETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;

    /*//////////////////////////////////////////////////////////////
                             EVM - BRIDGE
    //////////////////////////////////////////////////////////////*/

    // LayerZero V2 (OFT/ONFT)
    address constant LAYERZERO_ENDPOINT_ETH = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LAYERZERO_ENDPOINT_ARB = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LAYERZERO_ENDPOINT_OP = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LAYERZERO_ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LAYERZERO_ENDPOINT_BSC = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LAYERZERO_ENDPOINT_AVAX = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LAYERZERO_ENDPOINT_POLYGON = 0x1a44076050125825900e736c501f859c50fE728c;

    // Axelar
    address constant AXELAR_GATEWAY_ETH = 0x4F4495243837681061C4743b74B3eEdf548D56A5;
    address constant AXELAR_GATEWAY_ARB = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address constant AXELAR_GATEWAY_OP = 0xe432150cce91c13a887f7D836923d5597adD8E31;
    address constant AXELAR_GATEWAY_BSC = 0x304acf330bbE08d1e512eefaa92F6a57871fD895;
    address constant AXELAR_GATEWAY_AVAX = 0x5029C0EFf6C34351a0CEc334542cDb22c7928f78;
    address constant AXELAR_GAS_SERVICE_ETH = 0x2d5d7d31F671F86C782533cc367F14109a082712;

    // Wormhole
    address constant WORMHOLE_CORE_ETH = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address constant WORMHOLE_CORE_ARB = 0xa5f208e072434bC67592E4C49C1B991BA79BCA46;
    address constant WORMHOLE_CORE_BSC = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;

    // Stargate V2 (LayerZero)
    address constant STARGATE_V2_ETH = 0x77b2043768d28E9C9aB44E1aBfC95944bcE57931;
    address constant STARGATE_V2_ARB = 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9;
    address constant STARGATE_V2_OP = 0xCF80FF29AdFFc5C9b2AcEE6B8AA04e4023aA96aB;
    address constant STARGATE_ROUTER_ETH = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;

    // Across Protocol
    address constant ACROSS_SPOKE_ETH = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address constant ACROSS_SPOKE_ARB = 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A;
    address constant ACROSS_SPOKE_OP = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;

    // Hop Protocol
    address constant HOP_BRIDGE_ETH = 0xb8901acB165ed027E32754E0FFe830802919727f;

    /*//////////////////////////////////////////////////////////////
                             ORACLES
    //////////////////////////////////////////////////////////////*/

    // Chainlink (Multi-chain)
    address constant CHAINLINK_ETH_USD_ETH = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_BTC_USD_ETH = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant CHAINLINK_LINK_USD_ETH = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    address constant CHAINLINK_REGISTRY_ETH = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf;

    // Pyth Network
    address constant PYTH_ETH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address constant PYTH_ARB = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
    address constant PYTH_OP = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
    address constant PYTH_BSC = 0x4D7E825f80bDf85e913E0DD2A2D54927e9dE1594;
    address constant PYTH_AVAX = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address constant PYTH_BASE = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;

    // Redstone (Modular Oracles)
    address constant REDSTONE_ETH = 0x7C2FA0a5F97F8b7B16f5d7D9bDE4dEB2C1D7e7e9;

    /*//////////////////////////////////////////////////////////////
                          XRPL EVM SIDECHAIN
    //////////////////////////////////////////////////////////////*/

    // XRPL EVM Sidechain (Chain ID: 1440001)
    string constant XRPL_EVM_BRIDGE = "https://bridge.xrplevm.org";
    // XRP wrapped as ERC20 on EVM chains
    address constant WXRP_ETH = 0x628F76eAB0C1298F7a24d337bBbF1ef8A1Ea6A24;

    /*//////////////////////////////////////////////////////////////
                          BITCOIN BRIDGES
    //////////////////////////////////////////////////////////////*/

    // WBTC (Wrapped Bitcoin - Most liquid)
    address constant WBTC_ETH = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WBTC_ARB = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // tBTC (Threshold/Keep Network - Trustless)
    address constant TBTC_ETH = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
    address constant TBTC_ARB = 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40;

    // cbBTC (Coinbase Wrapped Bitcoin)
    address constant CBBTC_ETH = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant CBBTC_BASE = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // sBTC (Stacks - Native Bitcoin DeFi)
    string constant SBTC_STACKS = "SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.sbtc-token";

    // rBTC (RSK - Bitcoin Sidechain)
    string constant RBTC_RSK_RPC = "https://public-node.rsk.co";

    /*//////////////////////////////////////////////////////////////
                          SOLANA - ADDRESSES (Base58)
    //////////////////////////////////////////////////////////////*/

    // Jupiter (Aggregator) - Program IDs
    string constant JUPITER_V6_PROGRAM = "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4";

    // Raydium AMM
    string constant RAYDIUM_AMM_PROGRAM = "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8";
    string constant RAYDIUM_CLMM_PROGRAM = "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK";

    // Meteora DLMM
    string constant METEORA_DLMM_PROGRAM = "LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo";

    // Orca Whirlpool
    string constant ORCA_WHIRLPOOL_PROGRAM = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc";

    // Marinade (Liquid Staking)
    string constant MARINADE_PROGRAM = "MarBmsSgKXdrN1egZf5sqe1TMai9K1rChYNDJgjq7aD";

    // Solend (Lending)
    string constant SOLEND_PROGRAM = "So1endDq2YkqhipRh3WViPa8hdiSpxWy6z3Z6tMCpAo";

    // Kamino (Lending)
    string constant KAMINO_PROGRAM = "KLend2g3cP87ber41GXWsSZQq8pKd8Xvw5p2xJrg9";

    /*//////////////////////////////////////////////////////////////
                           TON - ADDRESSES
    //////////////////////////////////////////////////////////////*/

    // STON.fi DEX
    string constant STONFI_ROUTER = "EQB3ncyBUTjZUA5EnFKR5_EnOMI9V1tTEAAPaiU71gc4TiUt";
    string constant STONFI_FACTORY = "EQBfBWT7X2BHg9tXAxzhz2aKiNTU1tpt5NsiK0uSDW_YAJ67";

    // DeDust DEX
    string constant DEDUST_VAULT = "EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_";
    string constant DEDUST_FACTORY = "EQBfBWT7X2BHg9tXAxzhz2aKiNTU1tpt5NsiK0uSDW_YAJ67";

    // Evaa Lending
    string constant EVAA_MASTER = "EQC8rUZqR_pWV1BylWUlPNBzyiTYVoBEmQkMIQDZXICfnuRr";

    /*//////////////////////////////////////////////////////////////
                         PROTOCOL METADATA
    //////////////////////////////////////////////////////////////*/

    struct ProtocolInfo {
        string name;
        uint32 chainId;     // 1=ETH, 56=BSC, 42161=ARB, etc
        uint8 protocolType; // 0=DEX, 1=Lending, 2=Perps, 3=Staking, 4=Bridge
        address mainContract;
        string docs;
    }

    /// @notice Get all supported EVM protocols
    function getEVMProtocols() internal pure returns (ProtocolInfo[] memory) {
        ProtocolInfo[] memory protocols = new ProtocolInfo[](25);

        // DEXes
        protocols[0] = ProtocolInfo("Uniswap V3", 1, 0, UNISWAP_V3_ROUTER_ETH, "docs.uniswap.org");
        protocols[1] = ProtocolInfo("PancakeSwap", 56, 0, PANCAKE_V3_ROUTER_BSC, "docs.pancakeswap.finance");
        protocols[2] = ProtocolInfo("Curve", 1, 0, CURVE_ROUTER_ETH, "curve.readthedocs.io");
        protocols[3] = ProtocolInfo("Balancer", 1, 0, BALANCER_VAULT_ETH, "docs.balancer.fi");
        protocols[4] = ProtocolInfo("1inch", 1, 0, ONEINCH_ROUTER_ETH, "docs.1inch.io");
        protocols[5] = ProtocolInfo("Camelot", 42161, 0, CAMELOT_ROUTER_ARB, "docs.camelot.exchange");
        protocols[6] = ProtocolInfo("TraderJoe", 43114, 0, TRADERJOE_ROUTER_AVAX, "docs.traderjoexyz.com");
        protocols[7] = ProtocolInfo("Velodrome", 10, 0, VELODROME_ROUTER_OP, "docs.velodrome.finance");
        protocols[8] = ProtocolInfo("Aerodrome", 8453, 0, AERODROME_ROUTER_BASE, "aerodrome.finance/docs");

        // Lending
        protocols[9] = ProtocolInfo("Aave V3", 1, 1, AAVE_V3_POOL_ETH, "docs.aave.com");
        protocols[10] = ProtocolInfo("Compound V3", 1, 1, COMPOUND_V3_USDC_ETH, "docs.compound.finance");
        protocols[11] = ProtocolInfo("Venus", 56, 1, VENUS_COMPTROLLER_BSC, "docs.venus.io");
        protocols[12] = ProtocolInfo("Radiant", 42161, 1, RADIANT_POOL_ARB, "docs.radiant.capital");
        protocols[13] = ProtocolInfo("Spark", 1, 1, SPARK_POOL_ETH, "docs.spark.fi");
        protocols[14] = ProtocolInfo("Morpho", 1, 1, MORPHO_BLUE_ETH, "docs.morpho.org");

        // Perps
        protocols[15] = ProtocolInfo("GMX V2", 42161, 2, GMX_ROUTER_ARB, "docs.gmx.io");
        protocols[16] = ProtocolInfo("Aster", 56, 2, ASTER_TRADING_BSC, "docs.asterdex.com");
        protocols[17] = ProtocolInfo("Gains", 42161, 2, GAINS_TRADING_ARB, "gains.trade/docs");
        protocols[18] = ProtocolInfo("Kwenta", 10, 2, KWENTA_MARKET_OP, "docs.kwenta.io");

        // Staking
        protocols[19] = ProtocolInfo("Lido", 1, 3, LIDO_STETH_ETH, "docs.lido.fi");
        protocols[20] = ProtocolInfo("Rocket Pool", 1, 3, RETH_ETH, "docs.rocketpool.net");
        protocols[21] = ProtocolInfo("Frax", 1, 3, SFRXETH_ETH, "docs.frax.finance");

        // Bridges
        protocols[22] = ProtocolInfo("Stargate", 1, 4, STARGATE_ROUTER_ETH, "stargateprotocol.gitbook.io");
        protocols[23] = ProtocolInfo("Across", 1, 4, ACROSS_SPOKE_ETH, "docs.across.to");
        protocols[24] = ProtocolInfo("Hop", 1, 4, HOP_BRIDGE_ETH, "docs.hop.exchange");

        return protocols;
    }
}
