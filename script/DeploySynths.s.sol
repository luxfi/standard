// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Core Synths contracts - using named imports to avoid ERC20 conflicts
import {AlchemistV2} from "../contracts/synths/AlchemistV2.sol";
import {IAlchemistV2} from "../contracts/synths/interfaces/IAlchemistV2.sol";
import {IAlchemistV2AdminActions} from "../contracts/synths/interfaces/alchemist/IAlchemistV2AdminActions.sol";
import {AlchemicTokenV2} from "../contracts/synths/AlchemicTokenV2.sol";
import {TransmuterV2} from "../contracts/synths/TransmuterV2.sol";
import {TransmuterBuffer} from "../contracts/synths/TransmuterBuffer.sol";
import {WETHGateway} from "../contracts/synths/WETHGateway.sol";
// Note: gALCX has ERC20 conflicts - import only if needed
// import {gALCX} from "../contracts/synths/gALCX.sol";
import {Whitelist} from "../contracts/synths/utils/Whitelist.sol";

// Adapters
import {YearnTokenAdapter} from "../contracts/synths/adapters/yearn/YearnTokenAdapter.sol";

/// @title DeploySynths
/// @notice Deploy the complete Synths (Alchemix-style) protocol
/// @dev Deployment order:
///   1. AlchemicTokenV2 (alUSD, alETH, alBTC)
///   2. Whitelist
///   3. TransmuterV2 (for each synthetic)
///   4. TransmuterBuffer
///   5. AlchemistV2 (for each collateral type)
///   6. YieldAdapters (Yearn, Aave, Compound)
///   7. WETHGateway (for ETH deposits)
///   8. gALCX (governance staking)
contract DeploySynths is Script, DeployConfig {
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════
    
    // Protocol fee: 10% of yield
    uint256 constant PROTOCOL_FEE = 1000; // 10% in BPS
    
    // Minimum collateralization ratio: 200%
    uint256 constant MIN_COLLATERALIZATION = 2e18;
    
    // Minting limits
    uint256 constant MINT_LIMIT_MAXIMUM = 1_000_000e18; // 1M tokens
    uint256 constant MINT_LIMIT_BLOCKS = 7200; // ~24 hours at 12s/block
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYED ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════
    
    struct DeployedSynths {
        // Synthetic tokens
        address alUSD;
        address alETH;
        address alBTC;
        
        // Whitelists
        address whitelistUSD;
        address whitelistETH;
        address whitelistBTC;
        
        // Transmuters
        address transmuterUSD;
        address transmuterETH;
        address transmuterBTC;
        
        // Transmuter buffers
        address bufferUSD;
        address bufferETH;
        address bufferBTC;
        
        // Alchemists
        address alchemistUSD;
        address alchemistETH;
        address alchemistBTC;
        
        // Adapters
        address yearnUSDCAdapter;
        address yearnDAIAdapter;
        address yearnWETHAdapter;
        address yearnWBTCAdapter;
        
        // Utilities
        address wethGateway;
        address gALCX;
    }
    
    DeployedSynths public deployed;
    
    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════
    
    function run() public virtual {
        _initConfigs();
        ChainConfig memory config = getConfig();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Synths Protocol Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy synthetic tokens
        _deploySyntheticTokens(deployer);
        
        // Step 2: Deploy whitelists
        _deployWhitelists(deployer);
        
        // Step 3: Deploy transmuters
        _deployTransmuters(config);
        
        // Step 4: Deploy transmuter buffers
        _deployTransmuterBuffers();
        
        // Step 5: Deploy alchemists
        _deployAlchemists(deployer, config);
        
        // Step 6: Deploy yield adapters
        _deployYieldAdapters();
        
        // Step 7: Deploy WETH gateway
        _deployWETHGateway(config);
        
        // Step 8: Deploy governance staking
        _deployGovernanceStaking(config);
        
        // Step 9: Configure protocol
        _configureProtocol(deployer, config);
        
        vm.stopBroadcast();
        
        // Output deployment summary
        _printDeploymentSummary();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STEPS
    // ═══════════════════════════════════════════════════════════════════════
    
    function _deploySyntheticTokens(address admin) internal {
        console.log("Step 1: Deploying Synthetic Tokens...");
        
        // alUSD - Synthetic USD
        AlchemicTokenV2 alUSD = new AlchemicTokenV2("Alchemic USD", "alUSD", 0);
        deployed.alUSD = address(alUSD);
        console.log("  alUSD:", deployed.alUSD);
        
        // alETH - Synthetic ETH
        AlchemicTokenV2 alETH = new AlchemicTokenV2("Alchemic ETH", "alETH", 0);
        deployed.alETH = address(alETH);
        console.log("  alETH:", deployed.alETH);
        
        // alBTC - Synthetic BTC
        AlchemicTokenV2 alBTC = new AlchemicTokenV2("Alchemic BTC", "alBTC", 0);
        deployed.alBTC = address(alBTC);
        console.log("  alBTC:", deployed.alBTC);
    }
    
    function _deployWhitelists(address admin) internal {
        console.log("Step 2: Deploying Whitelists...");
        
        // USD whitelist
        Whitelist whitelistUSD = new Whitelist();
        deployed.whitelistUSD = address(whitelistUSD);
        
        // ETH whitelist  
        Whitelist whitelistETH = new Whitelist();
        deployed.whitelistETH = address(whitelistETH);
        
        // BTC whitelist
        Whitelist whitelistBTC = new Whitelist();
        deployed.whitelistBTC = address(whitelistBTC);
        
        console.log("  Whitelists deployed");
    }
    
    function _deployTransmuters(ChainConfig memory config) internal {
        console.log("Step 3: Deploying Transmuters...");
        
        // Transmuter for alUSD -> USDC/DAI
        TransmuterV2 transmuterUSD = new TransmuterV2();
        transmuterUSD.initialize(
            deployed.alUSD,
            config.usdc,
            address(0), deployed.whitelistUSD
        );
        deployed.transmuterUSD = address(transmuterUSD);
        console.log("  TransmuterUSD:", deployed.transmuterUSD);
        
        // Transmuter for alETH -> WETH
        TransmuterV2 transmuterETH = new TransmuterV2();
        transmuterETH.initialize(
            deployed.alETH,
            config.weth,
            address(0),
            deployed.whitelistETH
        );
        deployed.transmuterETH = address(transmuterETH);
        console.log("  TransmuterETH:", deployed.transmuterETH);
        
        // Transmuter for alBTC -> WBTC
        TransmuterV2 transmuterBTC = new TransmuterV2();
        transmuterBTC.initialize(
            deployed.alBTC,
            config.wbtc,
            address(0),
            deployed.whitelistBTC
        );
        deployed.transmuterBTC = address(transmuterBTC);
        console.log("  TransmuterBTC:", deployed.transmuterBTC);
    }
    
    function _deployTransmuterBuffers() internal {
        console.log("Step 4: Deploying Transmuter Buffers...");
        
        // Buffer for USD transmuter
        TransmuterBuffer bufferUSD = new TransmuterBuffer();
        bufferUSD.initialize(msg.sender, deployed.alUSD);
        deployed.bufferUSD = address(bufferUSD);
        
        // Buffer for ETH transmuter
        TransmuterBuffer bufferETH = new TransmuterBuffer();
        bufferETH.initialize(msg.sender, deployed.alETH);
        deployed.bufferETH = address(bufferETH);
        
        // Buffer for BTC transmuter
        TransmuterBuffer bufferBTC = new TransmuterBuffer();
        bufferBTC.initialize(msg.sender, deployed.alBTC);
        deployed.bufferBTC = address(bufferBTC);
        
        console.log("  Buffers deployed");
    }
    
    function _deployAlchemists(address admin, ChainConfig memory config) internal {
        console.log("Step 5: Deploying Alchemists...");
        
        // Alchemist for USD (collateral: USDC, DAI)
        AlchemistV2 alchemistUSD = new AlchemistV2();
        alchemistUSD.initialize(IAlchemistV2AdminActions.InitializationParams({
            admin: admin,
            debtToken: deployed.alUSD,
            transmuter: deployed.transmuterUSD,
            minimumCollateralization: MIN_COLLATERALIZATION,
            protocolFee: PROTOCOL_FEE,
            protocolFeeReceiver: config.multisig,
            mintingLimitMinimum: 0,
            mintingLimitMaximum: MINT_LIMIT_MAXIMUM,
            mintingLimitBlocks: MINT_LIMIT_BLOCKS,
            whitelist: deployed.whitelistUSD
        }));
        deployed.alchemistUSD = address(alchemistUSD);
        console.log("  AlchemistUSD:", deployed.alchemistUSD);
        
        // Alchemist for ETH (collateral: WETH)
        AlchemistV2 alchemistETH = new AlchemistV2();
        alchemistETH.initialize(IAlchemistV2AdminActions.InitializationParams({
            admin: admin,
            debtToken: deployed.alETH,
            transmuter: deployed.transmuterETH,
            minimumCollateralization: MIN_COLLATERALIZATION,
            protocolFee: PROTOCOL_FEE,
            protocolFeeReceiver: config.multisig,
            mintingLimitMinimum: 0,
            mintingLimitMaximum: MINT_LIMIT_MAXIMUM,
            mintingLimitBlocks: MINT_LIMIT_BLOCKS,
            whitelist: deployed.whitelistETH
        }));
        deployed.alchemistETH = address(alchemistETH);
        console.log("  AlchemistETH:", deployed.alchemistETH);
        
        // Alchemist for BTC (collateral: WBTC)
        AlchemistV2 alchemistBTC = new AlchemistV2();
        alchemistBTC.initialize(IAlchemistV2AdminActions.InitializationParams({
            admin: admin,
            debtToken: deployed.alBTC,
            transmuter: deployed.transmuterBTC,
            minimumCollateralization: MIN_COLLATERALIZATION,
            protocolFee: PROTOCOL_FEE,
            protocolFeeReceiver: config.multisig,
            mintingLimitMinimum: 0,
            mintingLimitMaximum: MINT_LIMIT_MAXIMUM,
            mintingLimitBlocks: MINT_LIMIT_BLOCKS,
            whitelist: deployed.whitelistBTC
        }));
        deployed.alchemistBTC = address(alchemistBTC);
        console.log("  AlchemistBTC:", deployed.alchemistBTC);
    }
    
    function _deployYieldAdapters() internal {
        console.log("Step 6: Deploying Yield Adapters...");
        // Yearn adapters would be deployed here
        // For now, placeholder - actual Yearn vaults need to exist
        console.log("  (Yield adapters require existing vault addresses)");
    }
    
    function _deployWETHGateway(ChainConfig memory config) internal {
        console.log("Step 7: Deploying WETH Gateway...");
        
        if (config.weth != address(0)) {
            WETHGateway gateway = new WETHGateway(
                config.weth,
                deployed.whitelistETH
            );
            deployed.wethGateway = address(gateway);
            console.log("  WETHGateway:", deployed.wethGateway);
        } else {
            console.log("  (WETH not configured, skipping gateway)");
        }
    }
    
    function _deployGovernanceStaking(ChainConfig memory) internal {
        console.log("Step 8: Deploying Governance Staking...");
        // gALCX deployment would require governance token
        console.log("  (Governance staking requires ALCX token)");
    }
    
    function _configureProtocol(address admin, ChainConfig memory config) internal {
        console.log("Step 9: Configuring Protocol...");
        
        // Grant minter roles to alchemists
        AlchemicTokenV2(deployed.alUSD).setWhitelist(deployed.alchemistUSD, true);
        AlchemicTokenV2(deployed.alETH).setWhitelist(deployed.alchemistETH, true);
        AlchemicTokenV2(deployed.alBTC).setWhitelist(deployed.alchemistBTC, true);
        
        // Set transmuter buffer sources (buffer is the collateral source)
        TransmuterV2(deployed.transmuterUSD).setCollateralSource(deployed.bufferUSD);
        TransmuterV2(deployed.transmuterETH).setCollateralSource(deployed.bufferETH);
        TransmuterV2(deployed.transmuterBTC).setCollateralSource(deployed.bufferBTC);
        
        console.log("  Protocol configured");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // OUTPUT
    // ═══════════════════════════════════════════════════════════════════════
    
    function _printDeploymentSummary() internal view {
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("");
        console.log("Synthetic Tokens:");
        console.log("  alUSD:", deployed.alUSD);
        console.log("  alETH:", deployed.alETH);
        console.log("  alBTC:", deployed.alBTC);
        console.log("");
        console.log("Alchemists:");
        console.log("  USD:", deployed.alchemistUSD);
        console.log("  ETH:", deployed.alchemistETH);
        console.log("  BTC:", deployed.alchemistBTC);
        console.log("");
        console.log("Transmuters:");
        console.log("  USD:", deployed.transmuterUSD);
        console.log("  ETH:", deployed.transmuterETH);
        console.log("  BTC:", deployed.transmuterBTC);
        console.log("");
        console.log("Utilities:");
        console.log("  WETH Gateway:", deployed.wethGateway);
        console.log("");
    }
}

/// @title DeploySynthsTestnet
/// @notice Deploy Synths with test tokens for testnet
contract DeploySynthsTestnet is DeploySynths {
    function run() public override {
        console.log("Deploying Synths to Testnet with mock tokens...");
        // Would deploy mock tokens first, then protocol
        super.run();
    }
}
