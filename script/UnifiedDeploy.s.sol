// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/LUX.sol";
import "../src/Bridge.sol";
import "../src/Farm.sol";
import "../src/Market.sol";
import "../src/Auction.sol";
import "../src/Drop.sol";
import "../src/DropNFTs.sol";
import "../src/dao/LuxDAO.sol";
import "../src/multicall/Multicall3.sol";
import "../src/uni/WLUX.sol";

/**
 * @title UnifiedDeploy
 * @notice Unified deployment script for all Lux Standard contracts
 * @dev Run with: forge script script/UnifiedDeploy.s.sol:UnifiedDeploy --rpc-url $RPC_URL --broadcast
 */
contract UnifiedDeploy is Script {
    // Deployment addresses
    address public luxToken;
    address public wluxToken;
    address public bridge;
    address public farm;
    address public market;
    address public auction;
    address public drop;
    address public dropNFTs;
    address public dao;
    address public multicall3;
    
    // Configuration
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; // 1B tokens
    uint256 public constant FARM_REWARD_PER_BLOCK = 100 * 10**18;
    uint256 public constant DAO_TREASURY_ALLOCATION = 100_000_000 * 10**18; // 100M tokens
    
    // Network configurations
    struct NetworkConfig {
        string name;
        uint256 chainId;
        address feeRecipient;
        bool shouldVerify;
    }
    
    mapping(uint256 => NetworkConfig) public networkConfigs;
    
    function setUp() public {
        // Setup network configurations
        networkConfigs[31337] = NetworkConfig({
            name: "localhost",
            chainId: 31337,
            feeRecipient: msg.sender,
            shouldVerify: false
        });
        
        networkConfigs[96368] = NetworkConfig({
            name: "testnet",
            chainId: 96368,
            feeRecipient: 0x000000000000000000000000000000000000dEaD,
            shouldVerify: true
        });
        
        networkConfigs[96369] = NetworkConfig({
            name: "mainnet",
            chainId: 96369,
            feeRecipient: 0x000000000000000000000000000000000000dEaD,
            shouldVerify: true
        });
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get network config
        NetworkConfig memory config = networkConfigs[block.chainid];
        console.log("Deploying to network:", config.name);
        
        // Deploy core contracts
        deployCore();
        
        // Deploy DeFi contracts
        deployDeFi();
        
        // Deploy utility contracts
        deployUtilities();
        
        // Setup post-deployment configuration
        postDeploymentSetup();
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        saveDeploymentAddresses();
        
        // Verify contracts if needed
        if (config.shouldVerify) {
            verifyContracts();
        }
    }
    
    function deployCore() internal {
        console.log("\n=== Deploying Core Contracts ===");
        
        // Deploy LUX token
        luxToken = address(new LUX());
        console.log("LUX Token deployed at:", luxToken);
        
        // Deploy WLUX
        wluxToken = address(new WLUX());
        console.log("WLUX deployed at:", wluxToken);
        
        // Deploy Bridge
        bridge = address(new Bridge());
        console.log("Bridge deployed at:", bridge);
    }
    
    function deployDeFi() internal {
        console.log("\n=== Deploying DeFi Contracts ===");
        
        // Deploy Farm
        farm = address(new Farm(
            IERC20(luxToken),
            FARM_REWARD_PER_BLOCK,
            block.number,
            block.number + 100000 // End block
        ));
        console.log("Farm deployed at:", farm);
        
        // Deploy Market
        market = address(new Market());
        console.log("Market deployed at:", market);
        
        // Deploy Auction
        auction = address(new Auction());
        console.log("Auction deployed at:", auction);
        
        // Deploy Drop contracts
        drop = address(new Drop());
        console.log("Drop deployed at:", drop);
        
        dropNFTs = address(new DropNFTs(
            "Lux Drop NFTs",
            "LDROP"
        ));
        console.log("DropNFTs deployed at:", dropNFTs);
    }
    
    function deployUtilities() internal {
        console.log("\n=== Deploying Utility Contracts ===");
        
        // Deploy Multicall3
        multicall3 = address(new Multicall3());
        console.log("Multicall3 deployed at:", multicall3);
        
        // Deploy DAO
        dao = address(new LuxDAO());
        console.log("LuxDAO deployed at:", dao);
    }
    
    function postDeploymentSetup() internal {
        console.log("\n=== Post-Deployment Setup ===");
        
        // Setup Bridge permissions
        LUX(luxToken).addBridge(bridge);
        console.log("Bridge added to LUX token");
        
        // Transfer tokens to Farm for rewards
        LUX(luxToken).transfer(farm, 10_000_000 * 10**18);
        console.log("Transferred 10M LUX to Farm");
        
        // Add LUX pool to Farm
        Farm(farm).add(1000, IERC20(luxToken), false);
        console.log("Added LUX pool to Farm");
        
        // Transfer tokens to DAO treasury
        LUX(luxToken).transfer(dao, DAO_TREASURY_ALLOCATION);
        console.log("Transferred 100M LUX to DAO treasury");
        
        // Setup Market
        Market(market).setProtocolFeeRecipient(dao);
        Market(market).setProtocolFeeBPS(250); // 2.5%
        console.log("Market protocol fee configured");
    }
    
    function saveDeploymentAddresses() internal {
        console.log("\n=== Deployment Addresses ===");
        console.log("LUX Token:", luxToken);
        console.log("WLUX:", wluxToken);
        console.log("Bridge:", bridge);
        console.log("Farm:", farm);
        console.log("Market:", market);
        console.log("Auction:", auction);
        console.log("Drop:", drop);
        console.log("DropNFTs:", dropNFTs);
        console.log("Multicall3:", multicall3);
        console.log("LuxDAO:", dao);
        
        // Write to file
        string memory json = "{";
        json = string.concat(json, '"LUX":"', vm.toString(luxToken), '",');
        json = string.concat(json, '"WLUX":"', vm.toString(wluxToken), '",');
        json = string.concat(json, '"Bridge":"', vm.toString(bridge), '",');
        json = string.concat(json, '"Farm":"', vm.toString(farm), '",');
        json = string.concat(json, '"Market":"', vm.toString(market), '",');
        json = string.concat(json, '"Auction":"', vm.toString(auction), '",');
        json = string.concat(json, '"Drop":"', vm.toString(drop), '",');
        json = string.concat(json, '"DropNFTs":"', vm.toString(dropNFTs), '",');
        json = string.concat(json, '"Multicall3":"', vm.toString(multicall3), '",');
        json = string.concat(json, '"LuxDAO":"', vm.toString(dao));
        json = string.concat(json, "}");
        
        NetworkConfig memory config = networkConfigs[block.chainid];
        string memory filename = string.concat("deployments/", config.name, "/addresses.json");
        vm.writeFile(filename, json);
        
        console.log("\nAddresses saved to:", filename);
    }
    
    function verifyContracts() internal {
        console.log("\n=== Verifying Contracts ===");
        
        // Note: Verification commands would be run separately
        console.log("Run the following commands to verify:");
        console.log("forge verify-contract", luxToken, "LUX --chain", block.chainid);
        console.log("forge verify-contract", bridge, "Bridge --chain", block.chainid);
        // ... etc
    }
}

/**
 * @title DeployLocal
 * @notice Quick deployment for local testing
 */
contract DeployLocal is UnifiedDeploy {
    function run() public override {
        require(block.chainid == 31337, "This script is for local deployment only");
        super.run();
        
        // Additional local setup
        setupLocalTestEnvironment();
    }
    
    function setupLocalTestEnvironment() internal {
        console.log("\n=== Setting up local test environment ===");
        
        // Create test users
        address alice = address(0x1);
        address bob = address(0x2);
        
        // Fund test users with LUX
        LUX(luxToken).transfer(alice, 1000 * 10**18);
        LUX(luxToken).transfer(bob, 1000 * 10**18);
        
        console.log("Test users funded");
    }
}

/**
 * @title DeployTestnet
 * @notice Deployment for testnet with specific configurations
 */
contract DeployTestnet is UnifiedDeploy {
    function run() public override {
        require(block.chainid == 96368, "This script is for testnet deployment only");
        super.run();
    }
}

/**
 * @title DeployMainnet
 * @notice Deployment for mainnet with safety checks
 */
contract DeployMainnet is UnifiedDeploy {
    function run() public override {
        require(block.chainid == 96369, "This script is for mainnet deployment only");
        
        // Additional safety check
        console.log("\n⚠️  WARNING: About to deploy to MAINNET!");
        console.log("Press Ctrl+C to cancel, or wait 10 seconds to continue...");
        vm.sleep(10);
        
        super.run();
    }
}