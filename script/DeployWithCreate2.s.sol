// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../src/LUX.sol";
import "../src/Bridge.sol";
import "../src/Farm.sol";
import "../src/Market.sol";
import "../src/Auction.sol";
import "../src/multicall/Multicall3.sol";
import "../src/uni/WLUX.sol";

/**
 * @title DeployWithCreate2
 * @notice Deployment script using OpenZeppelin's CREATE2 for deterministic addresses
 * @dev All contracts will have deterministic addresses across all chains
 */
contract DeployWithCreate2 is Script {
    // Contract version for salt generation
    string constant VERSION = "1.0.0";
    
    // Deployment configuration
    uint256 constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 constant FARM_REWARD_PER_BLOCK = 100 * 10**18;
    
    // Deployed addresses (deterministic across all chains)
    address public luxToken;
    address public wluxToken;
    address public bridge;
    address public farm;
    address public market;
    address public auction;
    address public multicall3;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== CREATE2 Deterministic Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy all contracts with CREATE2
        deployContracts();
        
        // Post-deployment setup
        setupContracts();
        
        vm.stopBroadcast();
        
        // Print and save deployment summary
        printDeploymentSummary();
    }
    
    function deployContracts() internal {
        // Deploy LUX Token
        bytes memory luxBytecode = type(LUX).creationCode;
        bytes32 luxSalt = generateSalt("LUX");
        luxToken = deployWithCreate2(luxBytecode, luxSalt, 0);
        console.log("LUX deployed at:", luxToken);
        
        // Deploy WLUX
        bytes memory wluxBytecode = type(WLUX).creationCode;
        bytes32 wluxSalt = generateSalt("WLUX");
        wluxToken = deployWithCreate2(wluxBytecode, wluxSalt, 0);
        console.log("WLUX deployed at:", wluxToken);
        
        // Deploy Bridge
        bytes memory bridgeBytecode = type(Bridge).creationCode;
        bytes32 bridgeSalt = generateSalt("Bridge");
        bridge = deployWithCreate2(bridgeBytecode, bridgeSalt, 0);
        console.log("Bridge deployed at:", bridge);
        
        // Deploy Farm with constructor args
        bytes memory farmBytecode = abi.encodePacked(
            type(Farm).creationCode,
            abi.encode(
                IERC20(luxToken),
                FARM_REWARD_PER_BLOCK,
                block.number,
                block.number + 1000000
            )
        );
        bytes32 farmSalt = generateSalt("Farm");
        farm = deployWithCreate2(farmBytecode, farmSalt, 0);
        console.log("Farm deployed at:", farm);
        
        // Deploy Market
        bytes memory marketBytecode = type(Market).creationCode;
        bytes32 marketSalt = generateSalt("Market");
        market = deployWithCreate2(marketBytecode, marketSalt, 0);
        console.log("Market deployed at:", market);
        
        // Deploy Auction
        bytes memory auctionBytecode = type(Auction).creationCode;
        bytes32 auctionSalt = generateSalt("Auction");
        auction = deployWithCreate2(auctionBytecode, auctionSalt, 0);
        console.log("Auction deployed at:", auction);
        
        // Deploy Multicall3
        bytes memory multicallBytecode = type(Multicall3).creationCode;
        bytes32 multicallSalt = generateSalt("Multicall3");
        multicall3 = deployWithCreate2(multicallBytecode, multicallSalt, 0);
        console.log("Multicall3 deployed at:", multicall3);
    }
    
    function deployWithCreate2(
        bytes memory bytecode,
        bytes32 salt,
        uint256 value
    ) internal returns (address) {
        // Check if already deployed
        address predictedAddress = Create2.computeAddress(
            salt,
            keccak256(bytecode)
        );
        
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(predictedAddress)
        }
        
        if (codeSize > 0) {
            console.log("Already deployed at:", predictedAddress);
            return predictedAddress;
        }
        
        // Deploy using OpenZeppelin's Create2
        return Create2.deploy(value, salt, bytecode);
    }
    
    function generateSalt(string memory contractName) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractName, ":", VERSION));
    }
    
    function setupContracts() internal {
        console.log("\nSetting up contracts...");
        
        // Setup Bridge permissions on LUX token
        LUX(luxToken).addBridge(bridge);
        console.log("✓ Bridge added to LUX token");
        
        // Transfer tokens to Farm
        LUX(luxToken).transfer(farm, 10_000_000 * 10**18);
        console.log("✓ Transferred 10M LUX to Farm");
        
        // Add LUX pool to Farm
        Farm(farm).add(1000, IERC20(luxToken), false);
        console.log("✓ Added LUX pool to Farm");
        
        // Setup Market fees
        Market(market).setProtocolFeeRecipient(msg.sender); // TODO: Use DAO address
        Market(market).setProtocolFeeBPS(250); // 2.5%
        console.log("✓ Market fees configured");
    }
    
    function printDeploymentSummary() internal view {
        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETE - DETERMINISTIC ADDRESSES");
        console.log("========================================");
        console.log("These addresses are the same on ALL chains:");
        console.log("");
        console.log("LUX Token:  ", luxToken);
        console.log("WLUX:       ", wluxToken);
        console.log("Bridge:     ", bridge);
        console.log("Farm:       ", farm);
        console.log("Market:     ", market);
        console.log("Auction:    ", auction);
        console.log("Multicall3: ", multicall3);
        console.log("========================================");
        
        // Generate deployment JSON
        string memory json = string.concat(
            '{\n',
            '  "contracts": {\n',
            '    "LUX": "', vm.toString(luxToken), '",\n',
            '    "WLUX": "', vm.toString(wluxToken), '",\n',
            '    "Bridge": "', vm.toString(bridge), '",\n',
            '    "Farm": "', vm.toString(farm), '",\n',
            '    "Market": "', vm.toString(market), '",\n',
            '    "Auction": "', vm.toString(auction), '",\n',
            '    "Multicall3": "', vm.toString(multicall3), '"\n',
            '  },\n',
            '  "version": "', VERSION, '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployer": "', vm.toString(msg.sender), '"\n',
            '}'
        );
        
        // Save to file
        string memory filename = string.concat(
            "deployments/create2/",
            vm.toString(block.chainid),
            ".json"
        );
        vm.writeFile(filename, json);
        console.log("\nDeployment data saved to:", filename);
    }
}

/**
 * @title ComputeCreate2Addresses
 * @notice Compute addresses before deployment
 */
contract ComputeCreate2Addresses is Script {
    string constant VERSION = "1.0.0";
    
    function run() public view {
        console.log("\n=== Computing CREATE2 Addresses ===");
        console.log("Using OpenZeppelin Create2 library");
        console.log("");
        
        // Compute addresses for each contract
        console.log("Expected addresses on ALL chains:");
        console.log("");
        
        // LUX Token
        bytes32 luxSalt = generateSalt("LUX");
        address luxAddr = Create2.computeAddress(
            luxSalt,
            keccak256(type(LUX).creationCode)
        );
        console.log("LUX:       ", luxAddr);
        
        // WLUX
        bytes32 wluxSalt = generateSalt("WLUX");
        address wluxAddr = Create2.computeAddress(
            wluxSalt,
            keccak256(type(WLUX).creationCode)
        );
        console.log("WLUX:      ", wluxAddr);
        
        // Bridge
        bytes32 bridgeSalt = generateSalt("Bridge");
        address bridgeAddr = Create2.computeAddress(
            bridgeSalt,
            keccak256(type(Bridge).creationCode)
        );
        console.log("Bridge:    ", bridgeAddr);
        
        // Market
        bytes32 marketSalt = generateSalt("Market");
        address marketAddr = Create2.computeAddress(
            marketSalt,
            keccak256(type(Market).creationCode)
        );
        console.log("Market:    ", marketAddr);
        
        // Auction
        bytes32 auctionSalt = generateSalt("Auction");
        address auctionAddr = Create2.computeAddress(
            auctionSalt,
            keccak256(type(Auction).creationCode)
        );
        console.log("Auction:   ", auctionAddr);
        
        // Multicall3
        bytes32 multicallSalt = generateSalt("Multicall3");
        address multicallAddr = Create2.computeAddress(
            multicallSalt,
            keccak256(type(Multicall3).creationCode)
        );
        console.log("Multicall3:", multicallAddr);
        
        console.log("\nThese addresses will be identical on every chain!");
    }
    
    function generateSalt(string memory contractName) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(contractName, ":", VERSION));
    }
}