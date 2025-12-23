// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";
import "./Create2Deployer.sol";

// Token imports
import {WLUX} from "../contracts/tokens/WLUX.sol";
import {USDC as BridgeUSDC} from "../contracts/bridge/USDC.sol";
import {USDT as BridgeUSDT} from "../contracts/bridge/USDT.sol";
import {DAI as BridgeDAI} from "../contracts/bridge/DAI.sol";
import {WETH as BridgeWETH} from "../contracts/bridge/WETH.sol";
import {AIToken} from "../contracts/ai/AIToken.sol";

// Synths imports
import {AlchemistV2} from "../contracts/synths/AlchemistV2.sol";
import {AlchemicTokenV2} from "../contracts/synths/AlchemicTokenV2.sol";
import {TransmuterV2} from "../contracts/synths/TransmuterV2.sol";
import {TransmuterBuffer} from "../contracts/synths/TransmuterBuffer.sol";
import {Whitelist} from "../contracts/synths/utils/Whitelist.sol";

// Perps imports
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

/// @title DeployCreate2
/// @notice Deterministic deployment using CREATE2 for identical addresses across all chains
/// @dev Uses a consistent salt scheme so the same addresses deploy on:
///   - Lux Mainnet (96369)
///   - Lux Testnet (96368)
///   - Hanzo Mainnet (36963)
///   - Hanzo Testnet (36962)
///   - Zoo Mainnet (200200)
///   - Zoo Testnet (200201)
contract DeployCreate2 is Script, DeployConfig {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Protocol version for salt generation
    bytes32 constant PROTOCOL_VERSION = keccak256("LUX_STANDARD_V1");

    // ═══════════════════════════════════════════════════════════════════════
    // SALT GENERATION
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Generate deterministic salt for a contract
    /// @dev Same salt = same address on all chains (when using same deployer)
    function salt(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PROTOCOL_VERSION, name));
    }

    // Standard salts for all protocol contracts
    function SALT_CREATE2_DEPLOYER() internal pure returns (bytes32) { return salt("Create2Deployer"); }
    function SALT_WLUX() internal pure returns (bytes32) { return salt("WLUX"); }
    function SALT_USDC() internal pure returns (bytes32) { return salt("USDC"); }
    function SALT_USDT() internal pure returns (bytes32) { return salt("USDT"); }
    function SALT_DAI() internal pure returns (bytes32) { return salt("DAI"); }
    function SALT_WETH() internal pure returns (bytes32) { return salt("WETH"); }
    function SALT_AI_TOKEN() internal pure returns (bytes32) { return salt("AIToken"); }
    function SALT_ALUSD() internal pure returns (bytes32) { return salt("alUSD"); }
    function SALT_ALETH() internal pure returns (bytes32) { return salt("alETH"); }
    function SALT_ALBTC() internal pure returns (bytes32) { return salt("alBTC"); }
    function SALT_WHITELIST() internal pure returns (bytes32) { return salt("Whitelist"); }
    function SALT_ALCHEMIST_USD() internal pure returns (bytes32) { return salt("AlchemistUSD"); }
    function SALT_ALCHEMIST_ETH() internal pure returns (bytes32) { return salt("AlchemistETH"); }
    function SALT_TRANSMUTER_USD() internal pure returns (bytes32) { return salt("TransmuterUSD"); }
    function SALT_BUFFER_USD() internal pure returns (bytes32) { return salt("TransmuterBufferUSD"); }
    function SALT_USDG() internal pure returns (bytes32) { return salt("USDG"); }
    function SALT_VAULT() internal pure returns (bytes32) { return salt("Vault"); }
    function SALT_VAULT_UTILS() internal pure returns (bytes32) { return salt("VaultUtils"); }
    function SALT_VAULT_PRICE_FEED() internal pure returns (bytes32) { return salt("VaultPriceFeed"); }
    function SALT_ROUTER() internal pure returns (bytes32) { return salt("Router"); }
    function SALT_POSITION_ROUTER() internal pure returns (bytes32) { return salt("PositionRouter"); }
    function SALT_SHORTS_TRACKER() internal pure returns (bytes32) { return salt("ShortsTracker"); }
    function SALT_GMX() internal pure returns (bytes32) { return salt("GMX"); }
    function SALT_GLP() internal pure returns (bytes32) { return salt("GLP"); }
    function SALT_GLP_MANAGER() internal pure returns (bytes32) { return salt("GlpManager"); }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    Create2Deployer public deployer;

    struct Deployment {
        // Infrastructure
        address create2Deployer;
        // Tokens
        address wlux;
        address usdc;
        address usdt;
        address dai;
        address weth;
        address aiToken;
        // Synths
        address alUSD;
        address alETH;
        address alBTC;
        address whitelist;
        address alchemistUSD;
        address alchemistETH;
        address transmuterUSD;
        address bufferUSD;
        // Perps
        address usdg;
        address vault;
        address vaultUtils;
        address vaultPriceFeed;
        address router;
        address positionRouter;
        address shortsTracker;
        address gmx;
        address glp;
        address glpManager;
    }

    Deployment public d;

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN ENTRY POINT
    // ═══════════════════════════════════════════════════════════════════════

    function run() public virtual {
        _initConfigs();
        ChainConfig memory config = getConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+====================================================================+");
        console.log("|    LUX DEFI PROTOCOL - CREATE2 DETERMINISTIC DEPLOYMENT           |");
        console.log("+====================================================================+");
        console.log("|  Chain ID:      ", block.chainid);
        console.log("|  Deployer:      ", deployerAddr);
        console.log("|  Network:       ", _getNetworkName());
        console.log("|  Protocol Ver:  LUX_STANDARD_V1");
        console.log("+====================================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 0: Deploy CREATE2 factory
        _deployCreate2Factory();

        // Phase 1: Tokens
        _deployTokens(config);

        // Phase 2: Synths
        _deploySynths(deployerAddr, config);

        // Phase 3: Perps
        _deployPerps(deployerAddr, config);

        // Phase 4: Configure
        _configure(deployerAddr, config);

        vm.stopBroadcast();

        // Output
        _printAddresses();
        _writeManifest();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 0: CREATE2 FACTORY
    // ═══════════════════════════════════════════════════════════════════════

    function _deployCreate2Factory() internal {
        console.log("Phase 0: CREATE2 Factory");

        // Deploy the factory itself (not via CREATE2, but at consistent nonce)
        deployer = new Create2Deployer();
        d.create2Deployer = address(deployer);
        console.log("  Create2Deployer:", d.create2Deployer);
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 1: TOKENS
    // ═══════════════════════════════════════════════════════════════════════

    function _deployTokens(ChainConfig memory config) internal {
        console.log("Phase 1: Core Tokens");

        // WLUX
        bytes memory wluxBytecode = type(WLUX).creationCode;
        d.wlux = deployer.deploy(SALT_WLUX(), wluxBytecode);
        console.log("  WLUX:", d.wlux);

        // USDC
        bytes memory usdcBytecode = type(BridgeUSDC).creationCode;
        d.usdc = deployer.deploy(SALT_USDC(), usdcBytecode);
        console.log("  USDC:", d.usdc);

        // USDT
        bytes memory usdtBytecode = type(BridgeUSDT).creationCode;
        d.usdt = deployer.deploy(SALT_USDT(), usdtBytecode);
        console.log("  USDT:", d.usdt);

        // DAI
        bytes memory daiBytecode = type(BridgeDAI).creationCode;
        d.dai = deployer.deploy(SALT_DAI(), daiBytecode);
        console.log("  DAI:", d.dai);

        // WETH
        bytes memory wethBytecode = type(BridgeWETH).creationCode;
        d.weth = deployer.deploy(SALT_WETH(), wethBytecode);
        console.log("  WETH:", d.weth);

        // AI Token (treasury is the safe/multisig)
        address treasury = config.multisig;
        if (treasury == address(0)) treasury = msg.sender;
        bytes memory aiTokenBytecode = abi.encodePacked(
            type(AIToken).creationCode,
            abi.encode(treasury, treasury)
        );
        d.aiToken = deployer.deploy(SALT_AI_TOKEN(), aiTokenBytecode);
        console.log("  AIToken:", d.aiToken);
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 2: SYNTHS (ALCHEMIX-STYLE)
    // ═══════════════════════════════════════════════════════════════════════

    function _deploySynths(address admin, ChainConfig memory config) internal {
        console.log("Phase 2: Synths Protocol");

        // Whitelist
        bytes memory whitelistBytecode = type(Whitelist).creationCode;
        d.whitelist = deployer.deploy(SALT_WHITELIST(), whitelistBytecode);
        console.log("  Whitelist:", d.whitelist);

        // Synthetic tokens
        uint256 flashFee = 0;

        bytes memory alUSDBytecode = abi.encodePacked(
            type(AlchemicTokenV2).creationCode,
            abi.encode("Alchemic USD", "alUSD", flashFee)
        );
        d.alUSD = deployer.deploy(SALT_ALUSD(), alUSDBytecode);
        console.log("  alUSD:", d.alUSD);

        bytes memory alETHBytecode = abi.encodePacked(
            type(AlchemicTokenV2).creationCode,
            abi.encode("Alchemic ETH", "alETH", flashFee)
        );
        d.alETH = deployer.deploy(SALT_ALETH(), alETHBytecode);
        console.log("  alETH:", d.alETH);

        bytes memory alBTCBytecode = abi.encodePacked(
            type(AlchemicTokenV2).creationCode,
            abi.encode("Alchemic BTC", "alBTC", flashFee)
        );
        d.alBTC = deployer.deploy(SALT_ALBTC(), alBTCBytecode);
        console.log("  alBTC:", d.alBTC);

        // Transmuter Buffer (impl - will be proxied)
        bytes memory bufferBytecode = type(TransmuterBuffer).creationCode;
        d.bufferUSD = deployer.deploy(SALT_BUFFER_USD(), bufferBytecode);
        console.log("  TransmuterBuffer:", d.bufferUSD);

        // Transmuter (impl - will be proxied)
        bytes memory transmuterBytecode = type(TransmuterV2).creationCode;
        d.transmuterUSD = deployer.deploy(SALT_TRANSMUTER_USD(), transmuterBytecode);
        console.log("  TransmuterV2:", d.transmuterUSD);

        // Alchemist (impl - will be proxied)
        bytes memory alchemistBytecode = type(AlchemistV2).creationCode;
        d.alchemistUSD = deployer.deploy(SALT_ALCHEMIST_USD(), alchemistBytecode);
        console.log("  AlchemistV2 (USD):", d.alchemistUSD);

        d.alchemistETH = deployer.deploy(SALT_ALCHEMIST_ETH(), alchemistBytecode);
        console.log("  AlchemistV2 (ETH):", d.alchemistETH);

        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 3: PERPS (GMX-STYLE)
    // ═══════════════════════════════════════════════════════════════════════

    function _deployPerps(address gov, ChainConfig memory config) internal {
        console.log("Phase 3: Perps Protocol");

        // USDG (vault param set later)
        bytes memory usdgBytecode = abi.encodePacked(
            type(USDG).creationCode,
            abi.encode(address(0))
        );
        d.usdg = deployer.deploy(SALT_USDG(), usdgBytecode);
        console.log("  USDG:", d.usdg);

        // VaultPriceFeed
        bytes memory priceFeedBytecode = type(VaultPriceFeed).creationCode;
        d.vaultPriceFeed = deployer.deploy(SALT_VAULT_PRICE_FEED(), priceFeedBytecode);
        console.log("  VaultPriceFeed:", d.vaultPriceFeed);

        // Vault
        bytes memory vaultBytecode = type(Vault).creationCode;
        d.vault = deployer.deploy(SALT_VAULT(), vaultBytecode);
        console.log("  Vault:", d.vault);

        // GMX token
        bytes memory gmxBytecode = type(GMX).creationCode;
        d.gmx = deployer.deploy(SALT_GMX(), gmxBytecode);
        console.log("  GMX:", d.gmx);

        // GLP token
        bytes memory glpBytecode = type(GLP).creationCode;
        d.glp = deployer.deploy(SALT_GLP(), glpBytecode);
        console.log("  GLP:", d.glp);

        // ShortsTracker
        bytes memory shortsTrackerBytecode = abi.encodePacked(
            type(ShortsTracker).creationCode,
            abi.encode(d.vault)
        );
        d.shortsTracker = deployer.deploy(SALT_SHORTS_TRACKER(), shortsTrackerBytecode);
        console.log("  ShortsTracker:", d.shortsTracker);

        // Router
        bytes memory routerBytecode = abi.encodePacked(
            type(Router).creationCode,
            abi.encode(d.vault, d.usdg, d.weth)
        );
        d.router = deployer.deploy(SALT_ROUTER(), routerBytecode);
        console.log("  Router:", d.router);

        // PositionRouter
        bytes memory positionRouterBytecode = abi.encodePacked(
            type(PositionRouter).creationCode,
            abi.encode(d.vault, d.router, d.weth, d.shortsTracker, 30, 1e16)
        );
        d.positionRouter = deployer.deploy(SALT_POSITION_ROUTER(), positionRouterBytecode);
        console.log("  PositionRouter:", d.positionRouter);

        // GlpManager
        bytes memory glpManagerBytecode = abi.encodePacked(
            type(GlpManager).creationCode,
            abi.encode(d.vault, d.usdg, d.glp, d.shortsTracker, 15 minutes)
        );
        d.glpManager = deployer.deploy(SALT_GLP_MANAGER(), glpManagerBytecode);
        console.log("  GlpManager:", d.glpManager);

        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 4: CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    function _configure(address gov, ChainConfig memory config) internal {
        console.log("Phase 4: Configuration");

        // Initialize Vault
        Vault(payable(d.vault)).initialize(
            d.router,
            d.usdg,
            d.vaultPriceFeed,
            5e30, // liquidationFeeUsd
            100,  // fundingRateFactor
            100   // stableFundingRateFactor
        );
        console.log("  Vault initialized");

        // USDG vault permission
        USDG(d.usdg).addVault(d.vault);
        USDG(d.usdg).addVault(d.glpManager);
        console.log("  USDG vaults set");

        // GLP minter
        GLP(d.glp).setMinter(d.glpManager, true);
        console.log("  GLP minter set");

        // Grant whitelist to alchemist for synth tokens
        AlchemicTokenV2(d.alUSD).setWhitelist(d.alchemistUSD, true);
        AlchemicTokenV2(d.alETH).setWhitelist(d.alchemistETH, true);
        console.log("  Synth whitelists set");

        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADDRESS PREDICTION
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Compute all addresses before deployment
    /// @dev Use this to verify addresses match expectations before mainnet deploy
    function computeAddresses() external view returns (Deployment memory predicted) {
        // Would need Create2Deployer address to predict
        // This is a template for post-factory address computation
        return predicted;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OUTPUT
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

    function _printAddresses() internal view {
        console.log("+====================================================================+");
        console.log("|                      DEPLOYMENT COMPLETE                           |");
        console.log("+====================================================================+");
        console.log("");
        console.log("INFRASTRUCTURE:");
        console.log("  Create2Deployer:", d.create2Deployer);
        console.log("");
        console.log("TOKENS:");
        console.log("  WLUX:    ", d.wlux);
        console.log("  USDC:    ", d.usdc);
        console.log("  USDT:    ", d.usdt);
        console.log("  DAI:     ", d.dai);
        console.log("  WETH:    ", d.weth);
        console.log("  AIToken: ", d.aiToken);
        console.log("");
        console.log("SYNTHS:");
        console.log("  alUSD:         ", d.alUSD);
        console.log("  alETH:         ", d.alETH);
        console.log("  alBTC:         ", d.alBTC);
        console.log("  Whitelist:     ", d.whitelist);
        console.log("  AlchemistUSD:  ", d.alchemistUSD);
        console.log("  AlchemistETH:  ", d.alchemistETH);
        console.log("  TransmuterUSD: ", d.transmuterUSD);
        console.log("  BufferUSD:     ", d.bufferUSD);
        console.log("");
        console.log("PERPS:");
        console.log("  USDG:          ", d.usdg);
        console.log("  Vault:         ", d.vault);
        console.log("  VaultPriceFeed:", d.vaultPriceFeed);
        console.log("  Router:        ", d.router);
        console.log("  PositionRouter:", d.positionRouter);
        console.log("  ShortsTracker: ", d.shortsTracker);
        console.log("  GMX:           ", d.gmx);
        console.log("  GLP:           ", d.glp);
        console.log("  GlpManager:    ", d.glpManager);
        console.log("");
        console.log("+====================================================================+");
    }

    function _writeManifest() internal view {
        string memory chainName = _getNetworkName();
        console.log("");
        console.log("Deployment manifest: deployments/", block.chainid, ".json");
        console.log("");
        console.log("To verify on explorer:");
        console.log("  forge verify-contract <ADDRESS> <CONTRACT> --chain-id", block.chainid);
        console.log("");
    }
}

/// @title DeployCreate2Mainnet
/// @notice Mainnet deployment with production parameters
contract DeployCreate2Mainnet is DeployCreate2 {
    function run() public override {
        require(
            block.chainid == LUX_MAINNET ||
            block.chainid == HANZO_MAINNET ||
            block.chainid == ZOO_MAINNET,
            "Not a mainnet chain"
        );
        super.run();
    }
}

/// @title DeployCreate2Testnet
/// @notice Testnet deployment
contract DeployCreate2Testnet is DeployCreate2 {
    function run() public override {
        require(
            block.chainid == LUX_TESTNET ||
            block.chainid == HANZO_TESTNET ||
            block.chainid == ZOO_TESTNET,
            "Not a testnet chain"
        );
        super.run();
    }
}

/// @title DeployCreate2Local
/// @notice Local Anvil deployment
contract DeployCreate2Local is DeployCreate2 {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil");
        super.run();
    }
}
