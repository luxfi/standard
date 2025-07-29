// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/LUX.sol";
import "../src/Bridge.sol";
import "../src/DropNFTs.sol";

contract DeployScript is Script {
    function run() external {
        // Read deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy LUX token
        LUX lux = new LUX();
        console.log("LUX deployed at:", address(lux));
        
        // Deploy Bridge
        Bridge bridge = new Bridge();
        console.log("Bridge deployed at:", address(bridge));
        
        // Deploy DropNFTs
        DropNFTs dropNFTs = new DropNFTs();
        console.log("DropNFTs deployed at:", address(dropNFTs));
        
        // Configure contracts
        lux.configure(address(bridge));
        console.log("LUX configured with bridge");
        
        // Stop broadcast
        vm.stopBroadcast();
    }
}

contract DeployTestnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy with specific configuration for testnet
        LUX lux = new LUX();
        Bridge bridge = new Bridge();
        
        // Configure
        lux.configure(address(bridge));
        
        // Unpause for testnet
        lux.unpause();
        
        console.log("Testnet deployment complete:");
        console.log("LUX:", address(lux));
        console.log("Bridge:", address(bridge));
        
        vm.stopBroadcast();
    }
}

contract DeployMainnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("MAINNET_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy in paused state for mainnet
        LUX lux = new LUX();
        Bridge bridge = new Bridge();
        
        // Configure
        lux.configure(address(bridge));
        
        // Mainnet starts paused
        lux.pause();
        
        console.log("Mainnet deployment complete:");
        console.log("LUX:", address(lux));
        console.log("Bridge:", address(bridge));
        console.log("WARNING: Contracts are deployed in PAUSED state");
        
        vm.stopBroadcast();
    }
}