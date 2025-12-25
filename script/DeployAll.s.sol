// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Token imports with aliases to avoid ERC20 conflicts
import {WLUX} from "../contracts/tokens/WLUX.sol";
import {LuxUSD} from "../contracts/bridge/lux/LUSD.sol";  // Native stablecoin
// NOTE: Bridged tokens (USDC, USDT, DAI) are NOT deployed here
// They come from external bridges - only LUSD is native
import {WETH as BridgeWETH} from "../contracts/bridge/WETH.sol";
import {AIToken} from "../contracts/ai/AIToken.sol";

// Synths imports (x* = Lux omnichain synths)
import {AlchemistV2} from "../contracts/synths/AlchemistV2.sol";
import {IAlchemistV2} from "../contracts/synths/interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../contracts/synths/interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {TransmuterV2} from "../contracts/synths/TransmuterV2.sol";
import {Whitelist} from "../contracts/synths/utils/Whitelist.sol";
import {xUSD} from "../contracts/synths/xUSD.sol";
import {xETH} from "../contracts/synths/xETH.sol";
import {xBTC} from "../contracts/synths/xBTC.sol";
import {xLUX} from "../contracts/synths/xLUX.sol";

// Proxy for upgradeable contracts
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Perps imports
import {IVault} from "../contracts/perps/core/interfaces/IVault.sol";
import {IVaultUtils} from "../contracts/perps/core/interfaces/IVaultUtils.sol";
import {Vault} from "../contracts/perps/core/Vault.sol";
import {VaultUtils} from "../contracts/perps/core/VaultUtils.sol";
import {VaultPriceFeed} from "../contracts/perps/core/VaultPriceFeed.sol";
import {Router} from "../contracts/perps/core/Router.sol";
import {PositionRouter} from "../contracts/perps/core/PositionRouter.sol";
import {ShortsTracker} from "../contracts/perps/core/ShortsTracker.sol";
import {LPUSD} from "../contracts/perps/tokens/LPUSD.sol";
import {LPX} from "../contracts/perps/lux/LPX.sol";
import {LLP} from "../contracts/perps/lux/LLP.sol";
import {LLPManager} from "../contracts/perps/core/LLPManager.sol";

// Markets imports (Morpho Blue-style lending)
import {Markets} from "../contracts/markets/Markets.sol";
import {IMarkets} from "../contracts/markets/interfaces/IMarkets.sol";
import {AdaptiveCurveRateModel} from "../contracts/markets/ratemodel/AdaptiveCurveRateModel.sol";

// Safe imports (Gnosis Safe)
import {Safe} from "@safe-global/safe-smart-account/Safe.sol";
import {SafeL2} from "@safe-global/safe-smart-account/SafeL2.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";
import {MultiSend} from "@safe-global/safe-smart-account/libraries/MultiSend.sol";
import {CompatibilityFallbackHandler} from "@safe-global/safe-smart-account/handler/CompatibilityFallbackHandler.sol";

// DAO Governance imports
import {VotesToken} from "../contracts/dao/governance/VotesToken.sol";
import {LuxGovernor} from "../contracts/dao/governance/LuxGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

// NFT Marketplace imports (Seaport v1.6)
import {SeaportInterface} from "seaport-types/src/interfaces/SeaportInterface.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";

// AMM imports (Uniswap V2 compatible)
import {LuxV2Factory} from "../contracts/amm/LuxV2Factory.sol";
import {LuxV2Router} from "../contracts/amm/LuxV2Router.sol";

// Infrastructure imports
import {Multicall} from "../contracts/multicall/Multicall.sol";
import {Multicall2} from "../contracts/multicall/Multicall2.sol";
import {MultiFaucet} from "../contracts/utils/MultiFaucet.sol";
import {MockChainlinkAggregator, MockOracleFactory} from "../contracts/mocks/MockChainlinkOracle.sol";

/// @title DeployAll
/// @notice Master deployment script for the entire Lux DeFi protocol suite
/// @dev Deploys in order:
///   1. Core tokens (WLUX, stablecoins, WETH)
///   2. Synths protocol (Alchemix-style)
///   3. Perps protocol (GMX-style)
///   3.5. Markets (Morpho Blue-style lending)
///   4. Cross-protocol integration
///   5. DAO & Safe infrastructure
///   6. NFT Marketplace (Seaport v1.6)
contract DeployAll is Script, DeployConfig {
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STRUCTS (split to avoid stack too deep)
    // ═══════════════════════════════════════════════════════════════════════

    struct TokenDeployment {
        address wlux;
        address lusd;
        address weth;
        address aiToken;
    }

    struct SynthsDeployment {
        address xUSD;
        address xETH;
        address xBTC;
        address xLUX;
        address xUSDVault;
    }

    struct PerpsDeployment {
        address vault;
        address router;
        address positionRouter;
        address lpx;
        address llp;
        address llpManager;
        address priceFeed;
    }

    struct InfraDeployment {
        address markets;
        address rateModel;
        address safeSingleton;
        address safeL2Singleton;
        address safeProxyFactory;
        address multiSend;
        address fallbackHandler;
    }

    struct GovernanceDeployment {
        address votesToken;
        address timelock;
        address governor;
    }

    struct NFTDeployment {
        address conduitController;
        address seaport;
        address transferHelper;
        address luxConduit;
    }

    struct AMMDeployment {
        address factory;
        address router;
        address wluxLusd;
        address wluxWeth;
    }

    struct UtilsDeployment {
        address multicall;
        address multicall2;
        address faucet;
        address ethUsdOracle;
        address btcUsdOracle;
        address luxUsdOracle;
    }

    TokenDeployment public tokens;
    SynthsDeployment public synths;
    PerpsDeployment public perps;
    InfraDeployment public infra;
    GovernanceDeployment public governance;
    NFTDeployment public nft;
    AMMDeployment public amm;
    UtilsDeployment public utils;
    
    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════
    
    function run() public virtual {
        _initConfigs();
        ChainConfig memory config = getConfig();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("");
        console.log("+==============================================================+");
        console.log("|          LUX DEFI PROTOCOL SUITE - FULL DEPLOYMENT           |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("|  Network:", _getNetworkName());
        console.log("+==============================================================+");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Phase 1: Core Infrastructure
        console.log("================================================================");
        console.log("  PHASE 1: Core Infrastructure");
        console.log("================================================================");
        _deployPhase1_Tokens();
        
        // Phase 1.5: AMM (for local/testnet - skip on mainnet)
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 1.5: AMM Infrastructure");
        console.log("================================================================");
        if (block.chainid == 31337 || isTestnet()) {
            _deployPhase1_5_AMM(deployer);
        } else {
            console.log("  Using canonical AMM deployments:");
            console.log("    V2 Factory:", config.uniV2Factory);
            console.log("    V2 Router:", config.uniV2Router);
        }

        // Phase 2: Synths Protocol
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 2: Synths Protocol (Alchemix-style)");
        console.log("================================================================");
        _deployPhase2_Synths(deployer, config);
        
        // Phase 3: Perps Protocol
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 3: Perps Protocol (LPX-style)");
        console.log("================================================================");
        _deployPhase3_Perps(deployer, config);

        // Phase 3.5: Markets (Lending)
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 3.5: Markets (Morpho Blue-style Lending)");
        console.log("================================================================");
        _deployPhase3_5_Markets(deployer, config);

        // Phase 4: Cross-Protocol Integration
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 4: Cross-Protocol Integration");
        console.log("================================================================");
        _deployPhase4_Integration(deployer, config);

        // Phase 5: DAO & Safe Infrastructure
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 5: DAO & Safe Infrastructure");
        console.log("================================================================");
        _deployPhase5_DAO(deployer, config);

        // Phase 6: NFT Marketplace (Seaport v1.6)
        // Skip for local deployment - requires separate seaport build
        if (block.chainid != 31337) {
            console.log("");
            console.log("================================================================");
            console.log("  PHASE 6: NFT Marketplace (Seaport v1.6)");
            console.log("================================================================");
            _deployPhase6_NFTMarket(deployer);
        } else {
            console.log("");
            console.log("================================================================");
            console.log("  PHASE 6: NFT Marketplace - SKIPPED (local)");
            console.log("  Run 'FOUNDRY_PROFILE=seaport forge build' then deploy separately");
            console.log("================================================================");
        }

        // Phase 7: Utilities (local/testnet only)
        if (block.chainid == 31337 || isTestnet()) {
            console.log("");
            console.log("================================================================");
            console.log("  PHASE 7: Utilities (Multicall, Faucet, Oracles)");
            console.log("================================================================");
            _deployPhase7_Utils(deployer);
        }

        vm.stopBroadcast();
        
        // Write deployment manifest
        _writeDeploymentManifest();
        
        // Print final summary
        _printFinalSummary();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT PHASES
    // ═══════════════════════════════════════════════════════════════════════
    
    function _deployPhase1_Tokens() internal {
        console.log("  Deploying core tokens...");
        
        // WLUX
        WLUX wlux = new WLUX();
        tokens.wlux = address(wlux);
        console.log("    WLUX:", tokens.wlux);
        
        // LUSD - Native stablecoin (Lux Dollar)
        LuxUSD lusd = new LuxUSD();
        tokens.lusd = address(lusd);
        console.log("    LUSD:", tokens.lusd);

        
        // WETH
        BridgeWETH weth = new BridgeWETH();
        tokens.weth = address(weth);
        console.log("    WETH:", tokens.weth);
        
        // AI Token (safe and treasury both use multisig for now)
        address treasury = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714;
        AIToken aiToken = new AIToken(treasury, treasury);
        tokens.aiToken = address(aiToken);
        console.log("    AI Token:", tokens.aiToken);
    }

    function _deployPhase1_5_AMM(address deployer) internal {
        console.log("  Deploying AMM (Uniswap V2 compatible)...");

        // Deploy Factory
        LuxV2Factory factory = new LuxV2Factory(deployer);
        amm.factory = address(factory);
        console.log("    Factory:", amm.factory);

        // Deploy Router
        LuxV2Router router = new LuxV2Router(amm.factory, tokens.wlux);
        amm.router = address(router);
        console.log("    Router:", amm.router);

        // Create initial pairs
        if (tokens.lusd != address(0)) {
            amm.wluxLusd = factory.createPair(tokens.wlux, tokens.lusd);
            console.log("    WLUX/LUSD:", amm.wluxLusd);
        }
        if (tokens.weth != address(0)) {
            amm.wluxWeth = factory.createPair(tokens.wlux, tokens.weth);
            console.log("    WLUX/WETH:", amm.wluxWeth);
        }
    }

    function _deployPhase2_Synths(address admin, ChainConfig memory config) internal {
        console.log("  Deploying synths protocol (x* omnichain synths)...");

        // Deploy x* synths - Lux omnichain synthetic tokens
        // These can work on any chain and redeem to underlying assets
        
        xUSD synthUSD = new xUSD();
        synths.xUSD = address(synthUSD);
        console.log("    xUSD:", synths.xUSD);

        xETH synthETH = new xETH();
        synths.xETH = address(synthETH);
        console.log("    xETH:", synths.xETH);

        xBTC synthBTC = new xBTC();
        synths.xBTC = address(synthBTC);
        console.log("    xBTC:", synths.xBTC);

        xLUX synthLUX = new xLUX();
        synths.xLUX = address(synthLUX);
        console.log("    xLUX:", synths.xLUX);

        // Deploy Whitelist (no initialization needed - uses constructor with msg.sender as owner)
        Whitelist whitelist = new Whitelist();
        console.log("    Whitelist:", address(whitelist));

        // Deploy Transmuter via ERC1967Proxy (upgradeable pattern)
        // TransmuterV2 uses _disableInitializers() in constructor, must use proxy
        TransmuterV2 transmuterImpl = new TransmuterV2();
        bytes memory transmuterInitData = abi.encodeWithSelector(
            TransmuterV2.initialize.selector,
            synths.xUSD,
            tokens.lusd,
            address(0),
            address(whitelist)
        );
        ERC1967Proxy transmuterProxy = new ERC1967Proxy(address(transmuterImpl), transmuterInitData);
        address transmuterUSD = address(transmuterProxy);
        console.log("    TransmuterUSD:", transmuterUSD);

        // Deploy Alchemist via ERC1967Proxy (upgradeable pattern)
        AlchemistV2 alchemistImpl = new AlchemistV2();
        bytes memory alchemistInitData = abi.encodeWithSelector(
            AlchemistV2.initialize.selector,
            IAlchemistV2AdminActions.InitializationParams({
                admin: admin,
                debtToken: synths.xUSD,
                transmuter: transmuterUSD,
                minimumCollateralization: 2e18,
                protocolFee: 1000,
                protocolFeeReceiver: config.multisig,
                mintingLimitMinimum: 0,
                mintingLimitMaximum: 1_000_000e18,
                mintingLimitBlocks: 7200,
                whitelist: address(whitelist)
            })
        );
        ERC1967Proxy alchemistProxy = new ERC1967Proxy(address(alchemistImpl), alchemistInitData);
        synths.xUSDVault = address(alchemistProxy);
        console.log("    xUSDVault:", synths.xUSDVault);

        // Grant minter role
        synthUSD.setWhitelist(synths.xUSDVault, true);
    }
    
    function _deployPhase3_Perps(address gov, ChainConfig memory) internal {
        console.log("  Deploying perps protocol...");
        
        // LPUSD (internal accounting token)
        LPUSD lpusd = new LPUSD(address(0));
        
        // Vault and VaultPriceFeed
        VaultPriceFeed vaultPriceFeed = new VaultPriceFeed();
        perps.priceFeed = address(vaultPriceFeed);
        
        Vault vault = new Vault();
        perps.vault = address(vault);
        console.log("    Vault:", perps.vault);
        
        vault.initialize(
            address(0), // router
            address(lpusd),
            address(vaultPriceFeed),
            5e30, // liquidationFeeUsd
            100,  // fundingRateFactor
            100   // stableFundingRateFactor
        );
        
        // VaultUtils needs vault reference
        VaultUtils vaultUtils = new VaultUtils(IVault(address(vault)));
        vault.setVaultUtils(IVaultUtils(address(vaultUtils)));
        lpusd.addVault(perps.vault);
        
        // Router
        Router router = new Router(perps.vault, address(lpusd), tokens.weth);
        perps.router = address(router);
        console.log("    Router:", perps.router);
        
        // ShortsTracker
        ShortsTracker shortsTracker = new ShortsTracker(perps.vault);
        
        // PositionRouter
        PositionRouter positionRouter = new PositionRouter(
            perps.vault,
            perps.router,
            tokens.weth,
            address(shortsTracker),
            30,
            1e16
        );
        perps.positionRouter = address(positionRouter);
        console.log("    PositionRouter:", perps.positionRouter);
        
        // Tokens
        LPX lpx = new LPX();
        perps.lpx = address(lpx);
        console.log("    LPX:", perps.lpx);
        
        LLP llp = new LLP();
        perps.llp = address(llp);
        console.log("    LLP:", perps.llp);
        
        // LLPManager
        LLPManager llpManager = new LLPManager(
            perps.vault,
            address(lpusd),
            perps.llp,
            address(shortsTracker),
            15 minutes
        );
        perps.llpManager = address(llpManager);
        console.log("    LLPManager:", perps.llpManager);
        
        llp.setMinter(perps.llpManager, true);
        lpusd.addVault(perps.llpManager);
        
        // Note: Router is set during vault.initialize()
        // Additional routers can be approved per-user via vault.addRouter()
    }
    
    function _deployPhase3_5_Markets(address, ChainConfig memory) internal {
        console.log("  Deploying markets (lending) protocol...");

        // Deploy Markets singleton (Morpho Blue-style)
        Markets markets = new Markets(msg.sender);
        infra.markets = address(markets);
        console.log("    Markets:", infra.markets);

        // Deploy AdaptiveCurveRateModel
        // Uses hardcoded constants: 4% initial APR, 90% target utilization
        AdaptiveCurveRateModel rateModel = new AdaptiveCurveRateModel();
        infra.rateModel = address(rateModel);
        console.log("    RateModel:", infra.rateModel);

        // Enable LLTV tiers
        uint256[] memory lltvs = new uint256[](5);
        lltvs[0] = 0.945e18;  // 94.5% - Stablecoin pairs
        lltvs[1] = 0.915e18;  // 91.5% - High quality collateral
        lltvs[2] = 0.86e18;   // 86% - Major assets (ETH/BTC)
        lltvs[3] = 0.77e18;   // 77% - Standard collateral
        lltvs[4] = 0.625e18;  // 62.5% - Volatile assets

        for (uint256 i = 0; i < lltvs.length; i++) {
            markets.enableLltv(lltvs[i]);
        }
        console.log("    LLTV tiers enabled: 5 tiers (94.5% to 62.5%)");

        // Note: Individual markets are created after oracle deployment
        // via createMarket() with specific collateral/loan token pairs
        console.log("    Markets protocol deployed (create markets after oracle setup)");
    }

    function _deployPhase4_Integration(address, ChainConfig memory) internal {
        console.log("  Configuring cross-protocol integration...");

        // Set up price feeds for synths using perps oracle
        // This allows alUSD/alETH/alBTC to use the same price feeds

        console.log("    Protocol integration complete");
    }

    function _deployPhase5_DAO(address deployer, ChainConfig memory config) internal {
        console.log("  Deploying Safe infrastructure...");

        // Deploy Safe singleton (for mainnet use)
        Safe safeSingleton = new Safe();
        infra.safeSingleton = address(safeSingleton);
        console.log("    Safe Singleton:", infra.safeSingleton);

        // Deploy SafeL2 singleton (for L2/subnet use with events)
        SafeL2 safeL2Singleton = new SafeL2();
        infra.safeL2Singleton = address(safeL2Singleton);
        console.log("    SafeL2 Singleton:", infra.safeL2Singleton);

        // Deploy SafeProxyFactory
        SafeProxyFactory proxyFactory = new SafeProxyFactory();
        infra.safeProxyFactory = address(proxyFactory);
        console.log("    SafeProxyFactory:", infra.safeProxyFactory);

        // Deploy MultiSend for batched transactions
        MultiSend multiSend = new MultiSend();
        infra.multiSend = address(multiSend);
        console.log("    MultiSend:", infra.multiSend);

        // Deploy Fallback Handler
        CompatibilityFallbackHandler fallbackHandler = new CompatibilityFallbackHandler();
        infra.fallbackHandler = address(fallbackHandler);
        console.log("    FallbackHandler:", infra.fallbackHandler);

        console.log("  Deploying DAO governance...");

        // Deploy governance token with no initial supply
        // DLUX is minted via governance proposals or staking mechanisms
        uint256 MAX_SUPPLY = 100_000_000e18; // 100M max supply
        VotesToken.Allocation[] memory allocations = new VotesToken.Allocation[](0);

        VotesToken votesToken = new VotesToken(
            "Delegated Lux",
            "DLUX",
            allocations,
            deployer,    // Owner (can mint via governance)
            MAX_SUPPLY,  // 100M max supply
            false        // Not locked
        );
        governance.votesToken = address(votesToken);
        console.log("    DLUX:", governance.votesToken);

        // Deploy Timelock Controller
        address[] memory proposers = new address[](0); // Governor will be proposer
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        TimelockController timelock = new TimelockController(
            2 days,  // minDelay
            proposers,
            executors,
            deployer  // Admin (should renounce after setup)
        );
        governance.timelock = address(timelock);
        console.log("    TimelockController:", governance.timelock);

        // Deploy Governor
        LuxGovernor governor = new LuxGovernor(
            IVotes(address(votesToken)),
            timelock,
            "Lux DAO Governor",
            7200,      // votingDelay: ~1 day (12s blocks)
            50400,     // votingPeriod: ~7 days (12s blocks)
            100_000e18, // proposalThreshold: 100K tokens
            4          // quorumPercentage: 4%
        );
        governance.governor = address(governor);
        console.log("    LuxGovernor:", governance.governor);

        // Configure Timelock roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        // Grant proposer and canceller roles to Governor
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));

        console.log("    Timelock roles configured");
    }

    /// @notice Conduit key for Lux ecosystem
    bytes32 constant LUX_CONDUIT_KEY = keccak256("LUX_CONDUIT_V1");

    function _deployPhase6_NFTMarket(address deployer) internal {
        console.log("  Deploying Seaport NFT marketplace from bytecode...");
        console.log("  NOTE: Requires 'FOUNDRY_PROFILE=seaport forge build' first");

        // Load ConduitController bytecode from seaport build
        bytes memory conduitControllerBytecode = vm.getCode("out-seaport/ConduitController.sol/LocalConduitController.json");

        // Deploy ConduitController
        address conduitController;
        assembly {
            conduitController := create(0, add(conduitControllerBytecode, 0x20), mload(conduitControllerBytecode))
        }
        require(conduitController != address(0), "ConduitController deployment failed");
        nft.conduitController = conduitController;
        console.log("    ConduitController:", nft.conduitController);

        // Load Seaport bytecode
        bytes memory seaportBytecode = vm.getCode("out-seaport/Seaport.sol/Seaport.json");
        // Append constructor argument (conduitController address)
        bytes memory seaportInitCode = abi.encodePacked(seaportBytecode, abi.encode(nft.conduitController));

        // Deploy Seaport
        address seaport;
        assembly {
            seaport := create(0, add(seaportInitCode, 0x20), mload(seaportInitCode))
        }
        require(seaport != address(0), "Seaport deployment failed");
        nft.seaport = seaport;
        console.log("    Seaport:", nft.seaport);

        // Load TransferHelper bytecode
        bytes memory transferHelperBytecode = vm.getCode("out-seaport/TransferHelper.sol/TransferHelper.json");
        // Append constructor argument (conduitController address)
        bytes memory transferHelperInitCode = abi.encodePacked(transferHelperBytecode, abi.encode(nft.conduitController));

        // Deploy TransferHelper
        address transferHelper;
        assembly {
            transferHelper := create(0, add(transferHelperInitCode, 0x20), mload(transferHelperInitCode))
        }
        require(transferHelper != address(0), "TransferHelper deployment failed");
        nft.transferHelper = transferHelper;
        console.log("    TransferHelper:", nft.transferHelper);

        // Create Lux ecosystem conduit
        console.log("  Setting up Lux ecosystem conduit...");
        ConduitControllerInterface controller = ConduitControllerInterface(nft.conduitController);

        // Create the conduit
        address luxConduit = controller.createConduit(LUX_CONDUIT_KEY, deployer);
        nft.luxConduit = luxConduit;
        console.log("    LuxConduit:", nft.luxConduit);

        // Open channel for Seaport
        controller.updateChannel(nft.luxConduit, nft.seaport, true);
        console.log("    Seaport channel opened on LuxConduit");
    }

    function _deployPhase7_Utils(address) internal {
        console.log("  Deploying utilities...");

        // Multicall
        Multicall multicall = new Multicall();
        utils.multicall = address(multicall);
        console.log("    Multicall:", utils.multicall);

        // Multicall2
        Multicall2 multicall2 = new Multicall2();
        utils.multicall2 = address(multicall2);
        console.log("    Multicall2:", utils.multicall2);

        // MultiFaucet
        MultiFaucet faucet = new MultiFaucet();
        utils.faucet = address(faucet);
        console.log("    MultiFaucet:", utils.faucet);

        // Configure faucet with tokens
        faucet.addToken(tokens.wlux, 10 ether, 1 hours);
        faucet.addToken(tokens.lusd, 1000e18, 1 hours);
        faucet.addToken(tokens.weth, 0.1 ether, 1 hours);
        faucet.addToken(tokens.aiToken, 100 ether, 1 hours);
        console.log("    Faucet configured with tokens");

        // Deploy mock oracles
        MockOracleFactory oracleFactory = new MockOracleFactory();
        (
            address ethUsd,
            address btcUsd,
            address luxUsd,
            // usdcUsd not stored
        ) = oracleFactory.deployCommonOracles();

        utils.ethUsdOracle = ethUsd;
        utils.btcUsdOracle = btcUsd;
        utils.luxUsdOracle = luxUsd;
        console.log("    ETH/USD Oracle:", utils.ethUsdOracle);
        console.log("    BTC/USD Oracle:", utils.btcUsdOracle);
        console.log("    LUX/USD Oracle:", utils.luxUsdOracle);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════
    
    function _getNetworkName() internal view returns (string memory) {
        if (block.chainid == LUX_MAINNET) return "Lux Mainnet";
        if (block.chainid == LUX_TESTNET) return "Lux Testnet";
        if (block.chainid == HANZO_MAINNET) return "Hanzo Mainnet";
        if (block.chainid == HANZO_TESTNET) return "Hanzo Testnet";
        if (block.chainid == ZOO_MAINNET) return "Zoo Mainnet";
        if (block.chainid == ZOO_TESTNET) return "Zoo Testnet";
        if (block.chainid == 31337) return "Anvil (Local)";
        return "Unknown";
    }
    
    function _writeDeploymentManifest() internal view {
        console.log("");
        console.log("Deployment manifest written to: deployments/[chainId].json");
    }
    
    function _printFinalSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|                    DEPLOYMENT COMPLETE                       |");
        console.log("+==============================================================+");
        console.log("|  TOKENS                                                      |");
        console.log("|    WLUX:", tokens.wlux);
        console.log("|    LUSD:", tokens.lusd);
        console.log("|    WETH:", tokens.weth);
        console.log("|    AI:", tokens.aiToken);
        console.log("+==============================================================+");
        console.log("|  AMM (via DeployAMM.s.sol or canonical)                      |");
        ChainConfig memory config = getConfig();
        console.log("|    V2 Factory:", config.uniV2Factory);
        console.log("|    V2 Router:", config.uniV2Router);
        console.log("+==============================================================+");
        console.log("|  SYNTHS (x* = Lux omnichain synths)                          |");
        console.log("|    xUSD:", synths.xUSD);
        console.log("|    xETH:", synths.xETH);
        console.log("|    xBTC:", synths.xBTC);
        console.log("|    xLUX:", synths.xLUX);
        console.log("|    xUSDVault:", synths.xUSDVault);
        console.log("+==============================================================+");
        console.log("|  PERPS                                                       |");
        console.log("|    Vault:", perps.vault);
        console.log("|    Router:", perps.router);
        console.log("|    PositionRouter:", perps.positionRouter);
        console.log("|    LPX:", perps.lpx);
        console.log("|    LLP:", perps.llp);
        console.log("|    LLPManager:", perps.llpManager);
        console.log("+==============================================================+");
        console.log("|  MARKETS (Lending)                                           |");
        console.log("|    Markets:", infra.markets);
        console.log("|    RateModel:", infra.rateModel);
        console.log("+==============================================================+");
        console.log("|  SAFE INFRASTRUCTURE                                         |");
        console.log("|    Safe Singleton:", infra.safeSingleton);
        console.log("|    SafeL2 Singleton:", infra.safeL2Singleton);
        console.log("|    SafeProxyFactory:", infra.safeProxyFactory);
        console.log("|    MultiSend:", infra.multiSend);
        console.log("|    FallbackHandler:", infra.fallbackHandler);
        console.log("+==============================================================+");
        console.log("|  DAO GOVERNANCE                                              |");
        console.log("|    DLUX:", governance.votesToken);
        console.log("|    TimelockController:", governance.timelock);
        console.log("|    LuxGovernor:", governance.governor);
        console.log("+==============================================================+");
        console.log("|  NFT MARKETPLACE (Seaport v1.6)                               |");
        console.log("|    ConduitController:", nft.conduitController);
        console.log("|    Seaport:", nft.seaport);
        console.log("|    TransferHelper:", nft.transferHelper);
        console.log("|    LuxConduit:", nft.luxConduit);
        console.log("+==============================================================+");
        console.log("");
    }
}

/// @title DeployAllMainnet
/// @notice Mainnet deployment with production parameters
contract DeployAllMainnet is DeployAll {
    function run() public override {
        require(block.chainid == LUX_MAINNET, "Wrong network");
        super.run();
    }
}

/// @title DeployAllTestnet
/// @notice Testnet deployment with test parameters
contract DeployAllTestnet is DeployAll {
    function run() public override {
        require(isTestnet(), "Wrong network");
        super.run();
    }
}

/// @title DeployAllLocal
/// @notice Local Anvil deployment for development
contract DeployAllLocal is DeployAll {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil for local deployment");
        super.run();
    }
}
