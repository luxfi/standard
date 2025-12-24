// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// AMM imports
import {LuxV2Factory} from "../contracts/amm/LuxV2Factory.sol";
import {LuxV2Pair} from "../contracts/amm/LuxV2Pair.sol";
import {LuxV2Router} from "../contracts/amm/LuxV2Router.sol";

// Token imports for initial pairs
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DeployAMM
/// @notice Deploys Uniswap V2 compatible AMM infrastructure
/// @dev Deploys Factory, Router, and creates initial liquidity pairs
contract DeployAMM is Script, DeployConfig {

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STRUCT
    // ═══════════════════════════════════════════════════════════════════════

    struct AMMDeployment {
        address factory;
        address router;
        // Initial pairs
        address wluxLusd;    // WLUX/LUSD pair
        address wluxWeth;    // WLUX/WETH pair
        address lusdWeth;    // LUSD/WETH pair
    }

    AMMDeployment public deployment;

    // ═══════════════════════════════════════════════════════════════════════
    // EXTERNAL TOKEN ADDRESSES (set before deployment)
    // ═══════════════════════════════════════════════════════════════════════

    address public wlux;
    address public lusd;
    address public weth;

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════

    function run() public virtual {
        _initConfigs();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|          LUX AMM (UNISWAP V2) DEPLOYMENT                     |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("|  Network:", _getNetworkName());
        console.log("+==============================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy core AMM
        _deployAMMCore(deployer);

        vm.stopBroadcast();

        _printSummary();
    }

    /// @notice Deploy with pre-existing token addresses
    function runWithTokens(address _wlux, address _lusd, address _weth) public {
        wlux = _wlux;
        lusd = _lusd;
        weth = _weth;
        run();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT LOGIC
    // ═══════════════════════════════════════════════════════════════════════

    function _deployAMMCore(address deployer) internal {
        console.log("  Deploying AMM core contracts...");

        // Deploy Factory
        LuxV2Factory factory = new LuxV2Factory(deployer);
        deployment.factory = address(factory);
        console.log("    LuxV2Factory:", deployment.factory);

        // Use configured WLUX or fallback
        address wluxAddr = wlux != address(0) ? wlux : getConfig().wlux;
        require(wluxAddr != address(0), "WLUX address not set");

        // Deploy Router
        LuxV2Router router = new LuxV2Router(deployment.factory, wluxAddr);
        deployment.router = address(router);
        console.log("    LuxV2Router:", deployment.router);

        // Create initial pairs if token addresses are set
        if (wlux != address(0) && lusd != address(0)) {
            deployment.wluxLusd = factory.createPair(wlux, lusd);
            console.log("    WLUX/LUSD Pair:", deployment.wluxLusd);
        }

        if (wlux != address(0) && weth != address(0)) {
            deployment.wluxWeth = factory.createPair(wlux, weth);
            console.log("    WLUX/WETH Pair:", deployment.wluxWeth);
        }

        if (lusd != address(0) && weth != address(0)) {
            deployment.lusdWeth = factory.createPair(lusd, weth);
            console.log("    LUSD/WETH Pair:", deployment.lusdWeth);
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
        console.log("|                AMM DEPLOYMENT COMPLETE                       |");
        console.log("+==============================================================+");
        console.log("|  CORE CONTRACTS                                              |");
        console.log("|    LuxV2Factory:", deployment.factory);
        console.log("|    LuxV2Router:", deployment.router);
        console.log("+--------------------------------------------------------------+");
        console.log("|  INITIAL PAIRS                                               |");
        if (deployment.wluxLusd != address(0)) {
            console.log("|    WLUX/LUSD:", deployment.wluxLusd);
        }
        if (deployment.wluxWeth != address(0)) {
            console.log("|    WLUX/WETH:", deployment.wluxWeth);
        }
        if (deployment.lusdWeth != address(0)) {
            console.log("|    LUSD/WETH:", deployment.lusdWeth);
        }
        console.log("+==============================================================+");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAIR CREATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Create a new pair
    function createPair(address tokenA, address tokenB) public returns (address pair) {
        require(deployment.factory != address(0), "Factory not deployed");
        return LuxV2Factory(deployment.factory).createPair(tokenA, tokenB);
    }

    /// @notice Get pair address
    function getPair(address tokenA, address tokenB) public view returns (address) {
        require(deployment.factory != address(0), "Factory not deployed");
        return LuxV2Factory(deployment.factory).getPair(tokenA, tokenB);
    }
}

/// @title DeployAMMLocal
/// @notice Local Anvil deployment
contract DeployAMMLocal is DeployAMM {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil");
        super.run();
    }
}

/// @title DeployAMMTestnet
/// @notice Testnet deployment
contract DeployAMMTestnet is DeployAMM {
    function run() public override {
        require(isTestnet(), "Wrong network");
        super.run();
    }
}
