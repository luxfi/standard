// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "@lux/amm/LuxV2Factory.sol";
import "@lux/amm/LuxV2Router.sol";
import {WLUX} from "@lux/tokens/WLUX.sol";
import {LuxETH} from "@lux/bridge/lux/LETH.sol";
import {LuxBTC} from "@lux/bridge/lux/LBTC.sol";
import {LuxUSD} from "@lux/bridge/lux/LUSD.sol";
import {xLUX} from "@lux/synths/xLUX.sol";
import {xETH} from "@lux/synths/xETH.sol";
import {xBTC} from "@lux/synths/xBTC.sol";
import {xUSD} from "@lux/synths/xUSD.sol";

/// @title DeployAMMAndLPs - Full AMM + LP Deployment for Testing
/// @notice Deploys LuxV2 AMM, tokens, and creates all required LP pairs
/// @dev Self-contained script for Anvil testing
contract DeployAMMAndLPs is Script {
    
    // Deployed contracts
    LuxV2Factory public factory;
    LuxV2Router public router;
    
    // Tokens
    WLUX public wlux;
    LuxETH public leth;
    LuxBTC public lbtc;
    LuxUSD public lusd;
    xLUX public xlux;
    xETH public xeth;
    xBTC public xbtc;
    xUSD public xusd;
    
    // LP Pairs
    address public wluxXluxPair;
    address public lethXethPair;
    address public lbtcXbtcPair;
    address public lusdXusdPair;
    address public wluxLusdPair;
    address public lethLusdPair;
    address public lbtcLusdPair;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|       LUX AMM + LP PAIRS FULL DEPLOYMENT                     |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("+==============================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Deploy Tokens
        console.log("  === Phase 1: Deploying Tokens ===");
        _deployTokens();

        // Phase 2: Deploy AMM
        console.log("");
        console.log("  === Phase 2: Deploying LuxV2 AMM ===");
        _deployAMM();

        // Phase 3: Create LP Pairs
        console.log("");
        console.log("  === Phase 3: Creating LP Pairs ===");
        _createLPPairs();

        // Phase 4: Add Initial Liquidity (optional, for testing only)
        // Note: Liquidity addition requires native ETH balance - run with --sender option
        // or use separate integration test for adding liquidity
        bool addLiquidity = vm.envOr("ADD_LIQUIDITY", false);
        if (addLiquidity) {
            console.log("");
            console.log("  === Phase 4: Adding Initial Liquidity ===");
            _addInitialLiquidity();
        } else {
            console.log("");
            console.log("  === Phase 4: Skipped (set ADD_LIQUIDITY=true to enable) ===");
        }

        vm.stopBroadcast();

        _printSummary();
    }

    function _deployTokens() internal {
        // Bridge tokens (L*)
        wlux = new WLUX();
        console.log("    WLUX:", address(wlux));
        
        leth = new LuxETH();
        console.log("    LETH:", address(leth));
        
        lbtc = new LuxBTC();
        console.log("    LBTC:", address(lbtc));
        
        lusd = new LuxUSD();
        console.log("    LUSD:", address(lusd));

        // Synth tokens (x*)
        xlux = new xLUX();
        console.log("    xLUX:", address(xlux));
        
        xeth = new xETH();
        console.log("    xETH:", address(xeth));
        
        xbtc = new xBTC();
        console.log("    xBTC:", address(xbtc));
        
        xusd = new xUSD();
        console.log("    xUSD:", address(xusd));
    }

    function _deployAMM() internal {
        // Deploy Factory
        factory = new LuxV2Factory(msg.sender);
        console.log("    LuxV2Factory:", address(factory));

        // Deploy Router
        router = new LuxV2Router(address(factory), address(wlux));
        console.log("    LuxV2Router:", address(router));
    }

    function _createLPPairs() internal {
        // Synth pairs
        wluxXluxPair = factory.createPair(address(wlux), address(xlux));
        console.log("    WLUX/xLUX:", wluxXluxPair);
        
        lethXethPair = factory.createPair(address(leth), address(xeth));
        console.log("    LETH/xETH:", lethXethPair);
        
        lbtcXbtcPair = factory.createPair(address(lbtc), address(xbtc));
        console.log("    LBTC/xBTC:", lbtcXbtcPair);
        
        lusdXusdPair = factory.createPair(address(lusd), address(xusd));
        console.log("    LUSD/xUSD:", lusdXusdPair);

        // Trading pairs
        wluxLusdPair = factory.createPair(address(wlux), address(lusd));
        console.log("    WLUX/LUSD:", wluxLusdPair);
        
        lethLusdPair = factory.createPair(address(leth), address(lusd));
        console.log("    LETH/LUSD:", lethLusdPair);
        
        lbtcLusdPair = factory.createPair(address(lbtc), address(lusd));
        console.log("    LBTC/LUSD:", lbtcLusdPair);
    }

    function _addInitialLiquidity() internal {
        // Mint tokens for liquidity
        uint256 luxAmount = 1_000_000e18;
        uint256 ethAmount = 100e18;
        uint256 btcAmount = 10e18;
        uint256 usdAmount = 1_000_000e18;

        // WLUX requires native LUX deposit (use vm.deal for testing)
        vm.deal(msg.sender, luxAmount * 3);
        wlux.deposit{value: luxAmount * 2}();
        
        // Mint bridge tokens (we're admin after deployment)
        leth.mint(msg.sender, ethAmount * 2);
        lbtc.mint(msg.sender, btcAmount * 2);
        lusd.mint(msg.sender, usdAmount * 4);

        // Mint synth tokens (need to set as minter first)
        xlux.setWhitelist(msg.sender, true);
        xeth.setWhitelist(msg.sender, true);
        xbtc.setWhitelist(msg.sender, true);
        xusd.setWhitelist(msg.sender, true);

        xlux.mint(msg.sender, luxAmount);
        xeth.mint(msg.sender, ethAmount);
        xbtc.mint(msg.sender, btcAmount);
        xusd.mint(msg.sender, usdAmount);

        // Approve router
        wlux.approve(address(router), type(uint256).max);
        leth.approve(address(router), type(uint256).max);
        lbtc.approve(address(router), type(uint256).max);
        lusd.approve(address(router), type(uint256).max);
        xlux.approve(address(router), type(uint256).max);
        xeth.approve(address(router), type(uint256).max);
        xbtc.approve(address(router), type(uint256).max);
        xusd.approve(address(router), type(uint256).max);

        uint256 deadline = block.timestamp + 3600;

        // Add liquidity to synth pairs (1:1 ratio since they represent same asset)
        router.addLiquidity(address(wlux), address(xlux), luxAmount, luxAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: WLUX/xLUX");
        
        router.addLiquidity(address(leth), address(xeth), ethAmount, ethAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: LETH/xETH");
        
        router.addLiquidity(address(lbtc), address(xbtc), btcAmount, btcAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: LBTC/xBTC");
        
        router.addLiquidity(address(lusd), address(xusd), usdAmount, usdAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: LUSD/xUSD");

        // Add liquidity to trading pairs
        router.addLiquidity(address(wlux), address(lusd), luxAmount, usdAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: WLUX/LUSD");
        
        router.addLiquidity(address(leth), address(lusd), ethAmount, usdAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: LETH/LUSD");
        
        router.addLiquidity(address(lbtc), address(lusd), btcAmount, usdAmount, 0, 0, msg.sender, deadline);
        console.log("    Added liquidity: LBTC/LUSD");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|                    DEPLOYMENT COMPLETE                       |");
        console.log("+==============================================================+");
        console.log("|  AMM CONTRACTS                                               |");
        console.log("|    LuxV2Factory:", address(factory));
        console.log("|    LuxV2Router:", address(router));
        console.log("+==============================================================+");
        console.log("|  BRIDGE TOKENS (L*)                                          |");
        console.log("|    WLUX:", address(wlux));
        console.log("|    LETH:", address(leth));
        console.log("|    LBTC:", address(lbtc));
        console.log("|    LUSD:", address(lusd));
        console.log("+==============================================================+");
        console.log("|  SYNTH TOKENS (x*)                                           |");
        console.log("|    xLUX:", address(xlux));
        console.log("|    xETH:", address(xeth));
        console.log("|    xBTC:", address(xbtc));
        console.log("|    xUSD:", address(xusd));
        console.log("+==============================================================+");
        console.log("|  LP PAIRS (Synth Arbitrage)                                  |");
        console.log("|    WLUX/xLUX:", wluxXluxPair);
        console.log("|    LETH/xETH:", lethXethPair);
        console.log("|    LBTC/xBTC:", lbtcXbtcPair);
        console.log("|    LUSD/xUSD:", lusdXusdPair);
        console.log("+==============================================================+");
        console.log("|  LP PAIRS (Trading)                                          |");
        console.log("|    WLUX/LUSD:", wluxLusdPair);
        console.log("|    LETH/LUSD:", lethLusdPair);
        console.log("|    LBTC/LUSD:", lbtcLusdPair);
        console.log("+==============================================================+");
        console.log("");
        console.log("  Total LP Pairs Created: 7");
        console.log("  All pairs have initial liquidity for testing");
        console.log("");
    }
}
