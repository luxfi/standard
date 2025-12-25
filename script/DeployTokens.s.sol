// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Use explicit contract imports to avoid ERC20 conflicts
// WLUX uses solmate ERC20
import {WLUX} from "../contracts/tokens/WLUX.sol";

// These contracts use @luxfi/standard ERC20 - import with aliases
import {USDC as BridgeUSDC} from "../contracts/bridge/USDC.sol";
import {USDT as BridgeUSDT} from "../contracts/bridge/USDT.sol";
import {DAI as BridgeDAI} from "../contracts/bridge/DAI.sol";
import {WETH as BridgeWETH} from "../contracts/bridge/WETH.sol";
import {AIToken} from "../contracts/ai/AIToken.sol";

/// @title DeployTokens
/// @notice Deploy core tokens for the Lux ecosystem
/// @dev Includes:
///   - WLUX (Wrapped LUX)
///   - Stablecoins (USDC, USDT, DAI)
///   - WETH (Wrapped ETH bridge)
///   - AI Token (compute mining)
contract DeployTokens is Script, DeployConfig {

    // =======================================================================
    // DEPLOYMENT PARAMETERS
    // =======================================================================

    // Initial supply for test tokens (1 billion with 18 decimals)
    uint256 constant INITIAL_SUPPLY = 1_000_000_000e18;

    // Minting caps
    uint256 constant USDC_CAP = 10_000_000_000e6; // 10B USDC (6 decimals)
    uint256 constant USDT_CAP = 10_000_000_000e6; // 10B USDT (6 decimals)
    uint256 constant DAI_CAP = 10_000_000_000e18; // 10B DAI (18 decimals)

    // =======================================================================
    // DEPLOYED ADDRESSES
    // =======================================================================

    struct DeployedTokens {
        address wlux;
        address usdc;
        address usdt;
        address dai;
        address weth;
        address aiToken;
    }

    DeployedTokens public deployed;

    // =======================================================================
    // MAIN DEPLOYMENT
    // =======================================================================

    function run() external {
        _initConfigs();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Token Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy WLUX
        _deployWLUX();

        // Deploy stablecoins
        _deployStablecoins(deployer);

        // Deploy WETH
        _deployWETH();

        // Deploy AI Token
        _deployAIToken(deployer);

        vm.stopBroadcast();

        _printDeploymentSummary();
    }

    // =======================================================================
    // DEPLOYMENT STEPS
    // =======================================================================

    function _deployWLUX() internal {
        console.log("Deploying WLUX...");

        WLUX wlux = new WLUX();
        deployed.wlux = address(wlux);

        console.log("  WLUX:", deployed.wlux);
    }

    function _deployStablecoins(address) internal {
        console.log("Deploying Stablecoins...");

        // USDC
        BridgeUSDC usdc = new BridgeUSDC();
        deployed.usdc = address(usdc);
        console.log("  USDC:", deployed.usdc);

        // USDT
        BridgeUSDT usdt = new BridgeUSDT();
        deployed.usdt = address(usdt);
        console.log("  USDT:", deployed.usdt);

        // DAI
        BridgeDAI dai = new BridgeDAI();
        deployed.dai = address(dai);
        console.log("  DAI:", deployed.dai);
    }

    function _deployWETH() internal {
        console.log("Deploying WETH...");

        BridgeWETH weth = new BridgeWETH();
        deployed.weth = address(weth);

        console.log("  WETH:", deployed.weth);
    }

    function _deployAIToken(address admin) internal {
        console.log("Deploying AI Token...");

        // AIToken constructor needs (safe, treasury)
        // Use admin for both initially - can be updated later
        AIToken aiToken = new AIToken(admin, admin);
        deployed.aiToken = address(aiToken);

        console.log("  AI Token:", deployed.aiToken);
    }

    // =======================================================================
    // OUTPUT
    // =======================================================================

    function _printDeploymentSummary() internal view {
        console.log("");
        console.log("=== Token Deployment Summary ===");
        console.log("");
        console.log("Native:");
        console.log("  WLUX:", deployed.wlux);
        console.log("");
        console.log("Stablecoins:");
        console.log("  USDC:", deployed.usdc);
        console.log("  USDT:", deployed.usdt);
        console.log("  DAI:", deployed.dai);
        console.log("");
        console.log("Bridged:");
        console.log("  WETH:", deployed.weth);
        console.log("");
        console.log("AI:");
        console.log("  AI Token:", deployed.aiToken);
        console.log("");
    }
}

/// @title DeployTestTokens
/// @notice Deploy test tokens with faucet functionality
contract DeployTestTokens is Script, DeployConfig {

    function run() external {
        _initConfigs();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        require(isTestnet(), "Only deploy test tokens on testnet");

        console.log("=== Test Token Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy test tokens with initial supply
        // These tokens have faucet functionality for testing

        vm.stopBroadcast();
    }
}
