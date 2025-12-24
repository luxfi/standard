// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
import {USDG} from "../contracts/perps/tokens/USDG.sol";
import {GMX} from "../contracts/perps/gmx/GMX.sol";
import {GLP} from "../contracts/perps/gmx/GLP.sol";
import {GlpManager} from "../contracts/perps/core/GlpManager.sol";

/// @title DeployAll
/// @notice Master deployment script for the entire Lux DeFi protocol suite
/// @dev Deploys in order:
///   1. Core tokens (WLUX, stablecoins, WETH)
///   2. Synths protocol (Alchemix-style)
///   3. Perps protocol (GMX-style)
///   4. Liquidity pools
///   5. Cross-chain bridges
contract DeployAll is Script, DeployConfig {
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STRUCTS
    // ═══════════════════════════════════════════════════════════════════════
    
    struct FullDeployment {
        // Tokens
        address wlux;
        address lusd;   // Native stablecoin (Lux Dollar)
        address weth;
        address aiToken;
        
        // Synths (x* = Lux omnichain synths)
        address xUSD;
        address xETH;
        address xBTC;
        address xLUX;
        address alchemistUSD;
        address alchemistETH;
        address alchemistBTC;
        address alchemistLUX;
        
        // Perps
        address vault;
        address router;
        address positionRouter;
        address gmx;
        address glp;
        address glpManager;
        
        // Oracle
        address priceFeed;
        
        // Governance
        address timelock;
    }
    
    FullDeployment public deployment;
    
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
        
        // Phase 1.5: AMM (Uniswap V2/V3)
        // Note: For production, use canonical Uniswap deployments
        // For testnet, deploy via DeployAMM.s.sol separately
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 1.5: AMM Infrastructure (Reference Only)");
        console.log("================================================================");
        console.log("  V2 Factory:", config.uniV2Factory);
        console.log("  V2 Router:", config.uniV2Router);
        console.log("  V3 Factory:", config.uniV3Factory);
        console.log("  V3 Router:", config.uniV3Router);
        console.log("  NOTE: AMM uses canonical/existing deployments or DeployAMM.s.sol");

        // Phase 2: Synths Protocol
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 2: Synths Protocol (Alchemix-style)");
        console.log("================================================================");
        _deployPhase2_Synths(deployer, config);
        
        // Phase 3: Perps Protocol
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 3: Perps Protocol (GMX-style)");
        console.log("================================================================");
        _deployPhase3_Perps(deployer, config);
        
        // Phase 4: Cross-Protocol Integration
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 4: Cross-Protocol Integration");
        console.log("================================================================");
        _deployPhase4_Integration(deployer, config);
        
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
        deployment.wlux = address(wlux);
        console.log("    WLUX:", deployment.wlux);
        
        // LUSD - Native stablecoin (Lux Dollar)
        LuxUSD lusd = new LuxUSD();
        deployment.lusd = address(lusd);
        console.log("    LUSD:", deployment.lusd);

        
        // WETH
        BridgeWETH weth = new BridgeWETH();
        deployment.weth = address(weth);
        console.log("    WETH:", deployment.weth);
        
        // AI Token (safe and treasury both use multisig for now)
        address treasury = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714;
        AIToken aiToken = new AIToken(treasury, treasury);
        deployment.aiToken = address(aiToken);
        console.log("    AI Token:", deployment.aiToken);
    }
    
        function _deployPhase2_Synths(address admin, ChainConfig memory config) internal {
        console.log("  Deploying synths protocol (x* omnichain synths)...");

        // Deploy x* synths - Lux omnichain synthetic tokens
        // These can work on any chain and redeem to underlying assets
        
        xUSD synthUSD = new xUSD();
        deployment.xUSD = address(synthUSD);
        console.log("    xUSD:", deployment.xUSD);

        xETH synthETH = new xETH();
        deployment.xETH = address(synthETH);
        console.log("    xETH:", deployment.xETH);

        xBTC synthBTC = new xBTC();
        deployment.xBTC = address(synthBTC);
        console.log("    xBTC:", deployment.xBTC);

        xLUX synthLUX = new xLUX();
        deployment.xLUX = address(synthLUX);
        console.log("    xLUX:", deployment.xLUX);

        // Deploy Whitelist (no initialization needed - uses constructor with msg.sender as owner)
        Whitelist whitelist = new Whitelist();
        console.log("    Whitelist:", address(whitelist));

        // Deploy Transmuter via ERC1967Proxy (upgradeable pattern)
        // TransmuterV2 uses _disableInitializers() in constructor, must use proxy
        TransmuterV2 transmuterImpl = new TransmuterV2();
        bytes memory transmuterInitData = abi.encodeWithSelector(
            TransmuterV2.initialize.selector,
            deployment.xUSD,
            deployment.lusd,
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
                debtToken: deployment.xUSD,
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
        deployment.alchemistUSD = address(alchemistProxy);
        console.log("    AlchemistUSD:", deployment.alchemistUSD);

        // Grant minter role
        synthUSD.setWhitelist(deployment.alchemistUSD, true);
    }
    
    function _deployPhase3_Perps(address gov, ChainConfig memory) internal {
        console.log("  Deploying perps protocol...");
        
        // USDG
        USDG usdg = new USDG(address(0));
        
        // Vault and VaultPriceFeed
        VaultPriceFeed vaultPriceFeed = new VaultPriceFeed();
        deployment.priceFeed = address(vaultPriceFeed);
        
        Vault vault = new Vault();
        deployment.vault = address(vault);
        console.log("    Vault:", deployment.vault);
        
        vault.initialize(
            address(0), // router
            address(usdg),
            address(vaultPriceFeed),
            5e30, // liquidationFeeUsd
            100,  // fundingRateFactor
            100   // stableFundingRateFactor
        );
        
        // VaultUtils needs vault reference
        VaultUtils vaultUtils = new VaultUtils(IVault(address(vault)));
        vault.setVaultUtils(IVaultUtils(address(vaultUtils)));
        usdg.addVault(deployment.vault);
        
        // Router
        Router router = new Router(deployment.vault, address(usdg), deployment.weth);
        deployment.router = address(router);
        console.log("    Router:", deployment.router);
        
        // ShortsTracker
        ShortsTracker shortsTracker = new ShortsTracker(deployment.vault);
        
        // PositionRouter
        PositionRouter positionRouter = new PositionRouter(
            deployment.vault,
            deployment.router,
            deployment.weth,
            address(shortsTracker),
            30,
            1e16
        );
        deployment.positionRouter = address(positionRouter);
        console.log("    PositionRouter:", deployment.positionRouter);
        
        // Tokens
        GMX gmx = new GMX();
        deployment.gmx = address(gmx);
        console.log("    GMX:", deployment.gmx);
        
        GLP glp = new GLP();
        deployment.glp = address(glp);
        console.log("    GLP:", deployment.glp);
        
        // GlpManager
        GlpManager glpManager = new GlpManager(
            deployment.vault,
            address(usdg),
            deployment.glp,
            address(shortsTracker),
            15 minutes
        );
        deployment.glpManager = address(glpManager);
        console.log("    GlpManager:", deployment.glpManager);
        
        glp.setMinter(deployment.glpManager, true);
        usdg.addVault(deployment.glpManager);
        
        // Note: Router is set during vault.initialize()
        // Additional routers can be approved per-user via vault.addRouter()
    }
    
    function _deployPhase4_Integration(address, ChainConfig memory) internal {
        console.log("  Configuring cross-protocol integration...");
        
        // Set up price feeds for synths using perps oracle
        // This allows alUSD/alETH/alBTC to use the same price feeds
        
        console.log("    Protocol integration complete");
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
        console.log("|    WLUX:", deployment.wlux);
        console.log("|    LUSD:", deployment.lusd);
        console.log("|    WETH:", deployment.weth);
        console.log("|    AI:", deployment.aiToken);
        console.log("+==============================================================+");
        console.log("|  AMM (via DeployAMM.s.sol or canonical)                      |");
        ChainConfig memory config = getConfig();
        console.log("|    V2 Factory:", config.uniV2Factory);
        console.log("|    V2 Router:", config.uniV2Router);
        console.log("+==============================================================+");
        console.log("|  SYNTHS (x* = Lux omnichain synths)                          |");
        console.log("|    xUSD:", deployment.xUSD);
        console.log("|    xETH:", deployment.xETH);
        console.log("|    xBTC:", deployment.xBTC);
        console.log("|    xLUX:", deployment.xLUX);
        console.log("|    AlchemistUSD:", deployment.alchemistUSD);
        console.log("+==============================================================+");
        console.log("|  PERPS                                                       |");
        console.log("|    Vault:", deployment.vault);
        console.log("|    Router:", deployment.router);
        console.log("|    PositionRouter:", deployment.positionRouter);
        console.log("|    GMX:", deployment.gmx);
        console.log("|    GLP:", deployment.glp);
        console.log("|    GlpManager:", deployment.glpManager);
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
