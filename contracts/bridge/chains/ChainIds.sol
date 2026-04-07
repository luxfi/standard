// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Omnichain Registry — Every chain Lux Bridge can reach
/// @notice 200+ chains: all known EVM chain IDs + virtual IDs for non-EVM
/// @dev EVM chains use their native chain ID. Non-EVM chains use virtual IDs
///      (deterministic encoding of chain name) for bridge message routing.
///      Virtual IDs live in the range > 2^32 to avoid collision with EVM chain IDs.
library ChainIds {

    // ================================================================
    //  LUX NETWORK (home chains)
    // ================================================================
    uint64 constant LUX_MAINNET         = 96369;
    uint64 constant LUX_TESTNET         = 96368;
    uint64 constant LUX_DEVNET          = 96370;
    uint64 constant LUX_ZOO             = 200200;
    uint64 constant LUX_ZOO_TESTNET     = 200201;
    uint64 constant LUX_ZOO_DEVNET      = 200202;
    uint64 constant LUX_HANZO           = 36963;
    uint64 constant LUX_HANZO_TESTNET   = 36964;
    uint64 constant LUX_SPC             = 36911;
    uint64 constant LUX_SPC_TESTNET     = 36910;
    uint64 constant LUX_PARS            = 494949;
    uint64 constant LUX_PARS_TESTNET    = 494950;
    uint64 constant LUX_PARS_DEVNET     = 494951;

    // ================================================================
    //  LIQUIDITY.IO (Satschel private L1)
    // ================================================================
    uint64 constant LIQUID_MAINNET      = 8675309;
    uint64 constant LIQUID_TESTNET      = 8675310;
    uint64 constant LIQUID_DEVNET       = 8675311;

    // ================================================================
    //  ETHEREUM ECOSYSTEM
    // ================================================================

    // --- Ethereum L1 ---
    uint64 constant ETHEREUM            = 1;
    uint64 constant ETHEREUM_SEPOLIA    = 11155111;
    uint64 constant ETHEREUM_HOLESKY    = 17000;

    // --- Ethereum L2: Optimistic Rollups ---
    uint64 constant OPTIMISM            = 10;
    uint64 constant OPTIMISM_SEPOLIA    = 11155420;
    uint64 constant BASE                = 8453;
    uint64 constant BASE_SEPOLIA        = 84532;
    uint64 constant ARBITRUM            = 42161;
    uint64 constant ARBITRUM_SEPOLIA    = 421614;
    uint64 constant ARBITRUM_NOVA       = 42170;
    uint64 constant BLAST               = 81457;
    uint64 constant BLAST_SEPOLIA       = 168587773;
    uint64 constant MANTLE              = 5000;
    uint64 constant MANTLE_SEPOLIA      = 5003;
    uint64 constant MODE                = 34443;
    uint64 constant MODE_SEPOLIA        = 919;
    uint64 constant ZORA                = 7777777;
    uint64 constant ZORA_SEPOLIA        = 999999999;
    uint64 constant MINT                = 185;
    uint64 constant REDSTONE            = 690;
    uint64 constant LISK                = 1135;
    uint64 constant CYBER               = 7560;
    uint64 constant FRAXTAL             = 252;
    uint64 constant WORLDCHAIN          = 480;
    uint64 constant INK                 = 57073;
    uint64 constant SONEIUM             = 1868;
    uint64 constant UNICHAIN            = 130;
    uint64 constant SHAPE               = 360;
    uint64 constant SWAN                = 254;
    uint64 constant DERIVE              = 957;
    uint64 constant KROMA               = 255;
    uint64 constant BOB                 = 60808;
    uint64 constant BOB_SEPOLIA         = 808813;
    uint64 constant METAL_L2            = 1750;

    // --- Ethereum L2: ZK Rollups ---
    uint64 constant ZKSYNC              = 324;
    uint64 constant ZKSYNC_SEPOLIA      = 300;
    uint64 constant SCROLL              = 534352;
    uint64 constant SCROLL_SEPOLIA      = 534351;
    uint64 constant LINEA               = 59144;
    uint64 constant LINEA_SEPOLIA       = 59141;
    uint64 constant POLYGON_ZKEVM       = 1101;
    uint64 constant POLYGON_ZKEVM_TEST  = 2442;
    uint64 constant STARKNET            = 23448594291968334; // SN_MAIN
    uint64 constant TAIKO               = 167000;
    uint64 constant TAIKO_HEKLA         = 167009;
    uint64 constant MORPH               = 2818;
    uint64 constant MANTA               = 169;
    uint64 constant MANTA_SEPOLIA       = 3441006;
    uint64 constant ZKFAIR              = 42766;
    uint64 constant ZIRCUIT             = 48900;
    uint64 constant ABSTRACT            = 2741;
    uint64 constant IMMUTABLE_ZKEVM     = 13371;

    // ================================================================
    //  EVM L1s & SIDECHAINS
    // ================================================================
    uint64 constant BSC                 = 56;
    uint64 constant BSC_TESTNET         = 97;
    uint64 constant POLYGON             = 137;
    uint64 constant POLYGON_AMOY        = 80002;
    uint64 constant AVALANCHE           = 43114;
    uint64 constant AVALANCHE_FUJI      = 43113;
    uint64 constant FANTOM              = 250;
    uint64 constant FANTOM_TESTNET      = 4002;
    uint64 constant CRONOS              = 25;
    uint64 constant CRONOS_TESTNET      = 338;
    uint64 constant GNOSIS              = 100;
    uint64 constant GNOSIS_CHIADO       = 10200;
    uint64 constant CELO                = 42220;
    uint64 constant CELO_ALFAJORES      = 44787;
    uint64 constant MOONBEAM            = 1284;
    uint64 constant MOONRIVER           = 1285;
    uint64 constant MOONBASE_ALPHA      = 1287;
    uint64 constant HARMONY             = 1666600000;
    uint64 constant HARMONY_TESTNET     = 1666700000;
    uint64 constant KAVA                = 2222;
    uint64 constant KAVA_TESTNET        = 2221;
    uint64 constant METIS               = 1088;
    uint64 constant METIS_SEPOLIA       = 59902;
    uint64 constant AURORA              = 1313161554;
    uint64 constant AURORA_TESTNET      = 1313161555;
    uint64 constant KLAYTN              = 8217;
    uint64 constant KLAYTN_BAOBAB       = 1001;
    uint64 constant FUSE                = 122;
    uint64 constant EVMOS               = 9001;
    uint64 constant EVMOS_TESTNET       = 9000;
    uint64 constant VELAS               = 106;
    uint64 constant OASIS_EMERALD       = 42262;
    uint64 constant OASIS_SAPPHIRE      = 23294;
    uint64 constant TELOS               = 40;
    uint64 constant TELOS_TESTNET       = 41;
    uint64 constant WEMIX               = 1111;
    uint64 constant NEON                = 245022934;
    uint64 constant FLARE               = 14;
    uint64 constant SONGBIRD            = 19;
    uint64 constant BOBA                = 288;
    uint64 constant ASTAR_EVM           = 592;
    uint64 constant SHIDEN              = 336;
    uint64 constant ELASTOS             = 20;
    uint64 constant IOTEX               = 4689;
    uint64 constant THUNDERCORE         = 108;
    uint64 constant PALM                = 11297108109;
    uint64 constant ROOTSTOCK           = 30;
    uint64 constant ROOTSTOCK_TESTNET   = 31;
    uint64 constant CHILIZ              = 88888;
    uint64 constant CHILIZ_SPICY        = 88882;

    // ================================================================
    //  DeFi / TRADING CHAINS (EVM)
    // ================================================================
    uint64 constant HYPERLIQUID         = 999;
    uint64 constant SEI                 = 1329;
    uint64 constant SEI_TESTNET         = 1328;
    uint64 constant INJECTIVE_EVM       = 1738; // inEVM
    uint64 constant BERACHAIN           = 80094;
    uint64 constant BERACHAIN_BARTIO    = 80084;
    uint64 constant SONIC               = 146;  // prev Fantom rebranded
    uint64 constant SONIC_TESTNET       = 64165;

    // ================================================================
    //  BITCOIN L2s (ALL EVM-compatible)
    // ================================================================
    uint64 constant MERLIN              = 4200;
    uint64 constant MERLIN_TESTNET      = 686868;
    uint64 constant BITLAYER            = 200901;
    uint64 constant BITLAYER_TESTNET    = 200810;
    uint64 constant BEVM                = 11501;
    uint64 constant BEVM_TESTNET        = 11503;
    uint64 constant CORE_DAO            = 1116;
    uint64 constant CORE_TESTNET        = 1115;
    uint64 constant CITREA              = 5115;
    uint64 constant CITREA_TESTNET      = 62298;
    uint64 constant BOUNCEBIT           = 6001;
    uint64 constant B2_NETWORK          = 223;
    uint64 constant MAP_PROTOCOL        = 22776;
    uint64 constant CORN                = 21000000;
    uint64 constant BOTANIX             = 3636;
    uint64 constant EXSAT               = 7200;
    uint64 constant BSQUARED            = 223;
    uint64 constant AILAYER             = 2649;
    uint64 constant BITFINITY           = 355113;

    // ================================================================
    //  APPCHAIN / GAMING / SOCIAL (EVM)
    // ================================================================
    uint64 constant RONIN               = 2020;
    uint64 constant RONIN_SAIGON        = 2021;
    uint64 constant IMMUTABLE_X         = 13371;
    uint64 constant XDAI                = 100; // = Gnosis
    uint64 constant SKALE_EUROPA        = 2046399126;
    uint64 constant XPLA                = 37;
    uint64 constant OASYS               = 248;
    uint64 constant BEAM                = 4337;
    uint64 constant TREASURE            = 61166;
    uint64 constant ANCIENT8            = 888888888;
    uint64 constant XAI                 = 660279;
    uint64 constant PROOF_OF_PLAY       = 70700;
    uint64 constant DEGEN               = 666666666;
    uint64 constant HAM                 = 5112;
    uint64 constant SANKO               = 1996;
    uint64 constant APEX                = 70700;

    // ================================================================
    //  PRIVACY / ZK CHAINS (EVM)
    // ================================================================
    uint64 constant FHENIX              = 8008135;
    uint64 constant INCO                = 9090;
    uint64 constant AZTEC               = 677868; // when mainnet
    uint64 constant ALEO_EVM            = 3940; // Bridge endpoint

    // ================================================================
    //  ADDITIONAL EVM L1s (requested: Kaia, VeChain, etc.)
    // ================================================================
    uint64 constant KAIA                = 8217;   // Kaia (ex-Klaytn) mainnet
    uint64 constant KAIA_KAIROS         = 1001;   // Kaia testnet
    uint64 constant VECHAIN             = 100009; // VeChain mainnet
    uint64 constant VECHAIN_TESTNET     = 100010;
    uint64 constant FLARE_COSTON2       = 114;
    uint64 constant XDC                 = 50;     // XDC Network
    uint64 constant XDC_TESTNET         = 51;
    uint64 constant CANTO               = 7700;
    uint64 constant STEP_NETWORK        = 1234;
    uint64 constant NUMBERS             = 10507;
    uint64 constant PLUME               = 98865;
    uint64 constant STORY               = 1514;

    // ================================================================
    //  ROLLUP-AS-A-SERVICE / MODULAR (EVM)
    // ================================================================
    uint64 constant CELESTIA_BLOBSTREAM = 123456; // placeholder for Celestia DA
    uint64 constant DYMENSION           = 1100;
    uint64 constant ECLIPSE             = 17172; // SVM on Ethereum
    uint64 constant FUEL_EVM            = 9889;   // Fuel Ignition (EVM bridge endpoint)

    // ================================================================
    //  TRON (TVM — near-EVM, Solidity-compatible)
    // ================================================================
    uint64 constant TRON                = 728126;
    uint64 constant TRON_SHASTA         = 2494104990;
    uint64 constant TRON_NILE           = 3448148188;

    // ================================================================
    //  NON-EVM: VIRTUAL CHAIN IDs
    //  These are deterministic encodings used in bridge messages only.
    //  Range: > 2^32 (avoids collision with EVM chain IDs)
    // ================================================================

    // --- Bitcoin ecosystem ---
    uint64 constant BITCOIN_MAINNET     = 4294967296; // 2^32 + 0
    uint64 constant BITCOIN_TESTNET     = 4294967297; // 2^32 + 1
    uint64 constant BITCOIN_SIGNET      = 4294967298;
    uint64 constant OPNET               = 4294967299; // OP_NET on Bitcoin L1
    uint64 constant LIGHTNING           = 4294967300;

    // --- Solana ---
    uint64 constant SOLANA              = 4294967310;
    uint64 constant SOLANA_DEVNET       = 4294967311;
    uint64 constant SOLANA_TESTNET      = 4294967312;

    // --- TON ---
    uint64 constant TON_MAINNET         = 4294967320;
    uint64 constant TON_TESTNET         = 4294967321;

    // --- Move VMs ---
    uint64 constant SUI                 = 4294967330;
    uint64 constant SUI_TESTNET         = 4294967331;
    uint64 constant SUI_DEVNET          = 4294967332;
    uint64 constant APTOS               = 4294967340;
    uint64 constant APTOS_TESTNET       = 4294967341;
    uint64 constant APTOS_DEVNET        = 4294967342;
    uint64 constant MOVEMENT            = 4294967343; // Movement L2 (Move on Ethereum)

    // --- Cosmos / IBC ---
    uint64 constant COSMOS_HUB          = 4294967350;
    uint64 constant OSMOSIS             = 4294967351;
    uint64 constant NOBLE               = 4294967352;
    uint64 constant CELESTIA            = 4294967353;
    uint64 constant DYDX                = 4294967354;
    uint64 constant STRIDE              = 4294967355;
    uint64 constant AKASH               = 4294967356;
    uint64 constant JUNO                = 4294967357;
    uint64 constant NEUTRON             = 4294967358;
    uint64 constant ARCHWAY             = 4294967359;
    uint64 constant TERRA               = 4294967360;
    uint64 constant SECRET              = 4294967361;
    uint64 constant FETCH_AI            = 4294967362;
    uint64 constant BAND                = 4294967363;
    uint64 constant UMEE                = 4294967364;
    uint64 constant PERSISTENCE         = 4294967365;
    uint64 constant SOMMELIER           = 4294967366;
    uint64 constant AXELAR              = 4294967367;
    uint64 constant KUJIRA              = 4294967368;
    uint64 constant MARS                = 4294967369;

    // --- Polkadot / Substrate ---
    uint64 constant POLKADOT            = 4294967380;
    uint64 constant KUSAMA              = 4294967381;
    uint64 constant ASTAR_SUBSTRATE     = 4294967382;
    uint64 constant PHALA               = 4294967383;
    uint64 constant ACALA               = 4294967384;
    uint64 constant PARALLEL            = 4294967385;
    uint64 constant BIFROST             = 4294967386;
    uint64 constant CENTRIFUGE          = 4294967387;
    uint64 constant HYDRADX             = 4294967388;
    uint64 constant INTERLAY            = 4294967389;
    uint64 constant PENDULUM            = 4294967390;
    uint64 constant UNIQUE              = 4294967391;
    uint64 constant ZEITGEIST           = 4294967392;
    uint64 constant FREQUENCY           = 4294967393;

    // --- NEAR ---
    uint64 constant NEAR_MAINNET        = 4294967400;
    uint64 constant NEAR_TESTNET_V      = 4294967401;

    // --- Stellar ---
    uint64 constant STELLAR_MAINNET     = 4294967410;
    uint64 constant STELLAR_TESTNET     = 4294967411;

    // --- XRPL ---
    uint64 constant XRPL_MAINNET        = 4294967420;
    uint64 constant XRPL_TESTNET        = 4294967421;
    uint64 constant XRPL_DEVNET         = 4294967422;

    // --- Cardano ---
    uint64 constant CARDANO_MAINNET     = 4294967430;
    uint64 constant CARDANO_PREPROD     = 4294967431;
    uint64 constant CARDANO_PREVIEW     = 4294967432;

    // --- Stacks (Bitcoin L2) ---
    uint64 constant STACKS_MAINNET      = 4294967440;
    uint64 constant STACKS_TESTNET      = 4294967441;

    // --- Algorand ---
    uint64 constant ALGORAND_MAINNET    = 4294967450;
    uint64 constant ALGORAND_TESTNET    = 4294967451;

    // --- MultiversX (ex-Elrond) ---
    uint64 constant MULTIVERSX          = 4294967460;
    uint64 constant MULTIVERSX_DEVNET   = 4294967461;

    // --- Hedera ---
    uint64 constant HEDERA_MAINNET      = 295;  // EVM chain ID
    uint64 constant HEDERA_TESTNET      = 296;

    // --- Casper ---
    uint64 constant CASPER_MAINNET      = 4294967470;
    uint64 constant CASPER_TESTNET      = 4294967471;

    // --- Mina ---
    uint64 constant MINA_MAINNET        = 4294967480;
    uint64 constant MINA_TESTNET        = 4294967481;

    // --- Internet Computer (ICP) ---
    uint64 constant ICP                 = 4294967490;

    // --- Flow ---
    uint64 constant FLOW_MAINNET        = 747;   // Flow EVM
    uint64 constant FLOW_TESTNET        = 545;

    // --- Tezos ---
    uint64 constant TEZOS_MAINNET       = 4294967500;
    uint64 constant TEZOS_GHOSTNET      = 4294967501;
    uint64 constant ETHERLINK           = 42793; // Tezos L2 (EVM)

    // --- Filecoin ---
    uint64 constant FILECOIN            = 314;   // FEVM
    uint64 constant FILECOIN_CALIBNET   = 314159;

    // --- ZetaChain ---
    uint64 constant ZETACHAIN           = 7000;
    uint64 constant ZETACHAIN_TESTNET   = 7001;

    // --- Fuel (Sway/FuelVM — UTXO parallel execution) ---
    uint64 constant FUEL_MAINNET        = 4294967520;
    uint64 constant FUEL_TESTNET        = 4294967521;

    // --- Sui ecosystem L2s ---
    uint64 constant WALRUS              = 4294967510; // Sui DA layer

    // ================================================================
    //  HELPER: Chain family classification
    // ================================================================

    /// @notice Returns true if the chain ID is in the non-EVM virtual range
    function isVirtualChain(uint64 chainId) internal pure returns (bool) {
        return chainId >= 4294967296; // >= 2^32
    }

    /// @notice Returns true if the chain is an EVM chain (native Teleporter.sol)
    function isEVMChain(uint64 chainId) internal pure returns (bool) {
        return chainId < 4294967296 && chainId > 0;
    }
}
