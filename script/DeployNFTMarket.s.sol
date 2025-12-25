// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Seaport interface imports (compatible with 0.8.28)
import {SeaportInterface} from "seaport-types/src/interfaces/SeaportInterface.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {TransferHelperInterface} from "seaport-types/src/interfaces/TransferHelperInterface.sol";

/// @title DeployNFTMarket
/// @notice Deploys Seaport NFT marketplace infrastructure for Lux Network
/// @dev Uses pre-compiled Seaport bytecode (compiled separately with solc 0.8.24)
///      Run: FOUNDRY_PROFILE=seaport forge build
///      Then deploy using this script
contract DeployNFTMarket is Script, DeployConfig {

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    struct NFTMarketDeployment {
        // Core Infrastructure
        address conduitController;
        address seaport;
        address transferHelper;

        // Lux Conduit
        address luxConduit;
        bytes32 luxConduitKey;
    }

    NFTMarketDeployment public deployment;

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    // Conduit configuration
    bytes32 public constant LUX_CONDUIT_KEY = keccak256("LUX_CONDUIT_V1");

    // Pre-computed bytecode hashes (from FOUNDRY_PROFILE=seaport forge build)
    // These are loaded from out-seaport/ directory

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════

    function run() public virtual {
        _initConfigs();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|          LUX NFT MARKETPLACE DEPLOYMENT                       |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("|  Network:", _getNetworkName());
        console.log("+==============================================================+");
        console.log("");
        console.log("  NOTE: First compile Seaport with:");
        console.log("    FOUNDRY_PROFILE=seaport forge build");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Core Infrastructure
        console.log("================================================================");
        console.log("  PHASE 1: Seaport Core Infrastructure");
        console.log("================================================================");
        _deploySeaportCore();

        // Phase 2: Lux Conduit
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 2: Lux Conduit Setup");
        console.log("================================================================");
        _deployLuxConduit(deployer);

        vm.stopBroadcast();

        _printSummary();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT PHASES
    // ═══════════════════════════════════════════════════════════════════════

    function _deploySeaportCore() internal {
        console.log("  Deploying Seaport core contracts from bytecode...");

        // Load ConduitController bytecode from seaport build
        bytes memory conduitControllerBytecode = vm.getCode("out-seaport/ConduitController.sol/LocalConduitController.json");

        // Deploy ConduitController
        address conduitController;
        assembly {
            conduitController := create(0, add(conduitControllerBytecode, 0x20), mload(conduitControllerBytecode))
        }
        require(conduitController != address(0), "ConduitController deployment failed");
        deployment.conduitController = conduitController;
        console.log("    ConduitController:", deployment.conduitController);

        // Load Seaport bytecode
        bytes memory seaportBytecode = vm.getCode("out-seaport/Seaport.sol/Seaport.json");
        // Append constructor argument (conduitController address)
        bytes memory seaportInitCode = abi.encodePacked(seaportBytecode, abi.encode(deployment.conduitController));

        // Deploy Seaport
        address seaport;
        assembly {
            seaport := create(0, add(seaportInitCode, 0x20), mload(seaportInitCode))
        }
        require(seaport != address(0), "Seaport deployment failed");
        deployment.seaport = seaport;
        console.log("    Seaport:", deployment.seaport);

        // Load TransferHelper bytecode
        bytes memory transferHelperBytecode = vm.getCode("out-seaport/TransferHelper.sol/TransferHelper.json");
        // Append constructor argument (conduitController address)
        bytes memory transferHelperInitCode = abi.encodePacked(transferHelperBytecode, abi.encode(deployment.conduitController));

        // Deploy TransferHelper
        address transferHelper;
        assembly {
            transferHelper := create(0, add(transferHelperInitCode, 0x20), mload(transferHelperInitCode))
        }
        require(transferHelper != address(0), "TransferHelper deployment failed");
        deployment.transferHelper = transferHelper;
        console.log("    TransferHelper:", deployment.transferHelper);
    }

    function _deployLuxConduit(address deployer) internal {
        console.log("  Setting up Lux ecosystem conduit...");

        // Create conduit for Lux ecosystem
        ConduitControllerInterface controller = ConduitControllerInterface(deployment.conduitController);

        // Check if conduit exists
        (address conduit, bool exists) = controller.getConduit(LUX_CONDUIT_KEY);

        if (!exists) {
            // Create the conduit
            address createdConduit = controller.createConduit(LUX_CONDUIT_KEY, deployer);
            deployment.luxConduit = createdConduit;
            deployment.luxConduitKey = LUX_CONDUIT_KEY;
            console.log("    LuxConduit:", deployment.luxConduit);

            // Open channel for Seaport
            controller.updateChannel(deployment.luxConduit, deployment.seaport, true);
            console.log("    Seaport channel opened on LuxConduit");
        } else {
            deployment.luxConduit = conduit;
            deployment.luxConduitKey = LUX_CONDUIT_KEY;
            console.log("    LuxConduit (existing):", deployment.luxConduit);
        }
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

    function _printSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|              NFT MARKETPLACE DEPLOYMENT COMPLETE              |");
        console.log("+==============================================================+");
        console.log("|  SEAPORT CORE                                                 |");
        console.log("|    ConduitController:", deployment.conduitController);
        console.log("|    Seaport:", deployment.seaport);
        console.log("|    TransferHelper:", deployment.transferHelper);
        console.log("+--------------------------------------------------------------+");
        console.log("|  LUX CONDUIT                                                  |");
        console.log("|    LuxConduit:", deployment.luxConduit);
        console.log("|    ConduitKey:", vm.toString(deployment.luxConduitKey));
        console.log("+==============================================================+");
        console.log("");
        console.log("  Seaport v1.6 deployed - ready for NFT trading!");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER: Conduit Management
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Helper to add a marketplace contract as a channel on the Lux conduit
    /// @param marketplace Address of the marketplace to add
    function addMarketplaceChannel(address marketplace) public {
        ConduitControllerInterface controller = ConduitControllerInterface(deployment.conduitController);
        controller.updateChannel(deployment.luxConduit, marketplace, true);
    }

    /// @notice Helper to remove a marketplace from the Lux conduit
    /// @param marketplace Address of the marketplace to remove
    function removeMarketplaceChannel(address marketplace) public {
        ConduitControllerInterface controller = ConduitControllerInterface(deployment.conduitController);
        controller.updateChannel(deployment.luxConduit, marketplace, false);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GETTER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get Seaport contract interface
    function seaport() public view returns (SeaportInterface) {
        return SeaportInterface(deployment.seaport);
    }

    /// @notice Get ConduitController interface
    function conduitController() public view returns (ConduitControllerInterface) {
        return ConduitControllerInterface(deployment.conduitController);
    }
}

/// @title DeployNFTMarketLocal
/// @notice Local Anvil deployment
contract DeployNFTMarketLocal is DeployNFTMarket {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil");
        super.run();
    }
}

/// @title DeployNFTMarketTestnet
/// @notice Testnet deployment
contract DeployNFTMarketTestnet is DeployNFTMarket {
    function run() public override {
        require(isTestnet(), "Wrong network");
        super.run();
    }
}

/// @title DeployNFTMarketMainnet
/// @notice Mainnet deployment
contract DeployNFTMarketMainnet is DeployNFTMarket {
    function run() public override {
        require(block.chainid == LUX_MAINNET, "Wrong network");
        super.run();
    }
}
