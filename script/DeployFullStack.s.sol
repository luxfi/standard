// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Core tokens
import {WLUX} from "../contracts/tokens/WLUX.sol";
import {LuxUSD} from "../contracts/bridge/lux/LUSD.sol";
import {LuxETH} from "../contracts/bridge/lux/LETH.sol";
import {LuxBTC} from "../contracts/bridge/lux/LBTC.sol";

// Synth tokens
import {xUSD} from "../contracts/synths/xUSD.sol";
import {xETH} from "../contracts/synths/xETH.sol";
import {xBTC} from "../contracts/synths/xBTC.sol";
import {xLUX} from "../contracts/synths/xLUX.sol";
import {xAI} from "../contracts/synths/xAI.sol";
import {xSOL} from "../contracts/synths/xSOL.sol";
import {xTON} from "../contracts/synths/xTON.sol";
import {xADA} from "../contracts/synths/xADA.sol";
import {xAVAX} from "../contracts/synths/xAVAX.sol";
import {xBNB} from "../contracts/synths/xBNB.sol";
import {xPOL} from "../contracts/synths/xPOL.sol";
import {xZOO} from "../contracts/synths/xZOO.sol";

// Staking
import {sLUX} from "../contracts/staking/sLUX.sol";

// AMM
import {LuxV2Factory} from "../contracts/amm/LuxV2Factory.sol";
import {LuxV2Router} from "../contracts/amm/LuxV2Router.sol";
import {LuxV2Pair} from "../contracts/amm/LuxV2Pair.sol";

// Synths Protocol
import {AlchemistV2} from "../contracts/synths/AlchemistV2.sol";
import {TransmuterV2} from "../contracts/synths/TransmuterV2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployFullStack
 * @notice Deploys complete Lux DeFi stack for testing
 * 
 * Includes:
 * - Core tokens (WLUX, LUSD, LETH, LBTC)
 * - All 12 synth tokens
 * - LUX staking (sLUX)
 * - AMM (Factory, Router, Pairs)
 * - Synths protocol (AlchemistV2, TransmuterV2)
 * 
 * Usage:
 *   anvil &
 *   forge script script/DeployFullStack.s.sol --rpc-url http://localhost:8545 --broadcast
 */
contract DeployFullStack is Script {
    // Anvil default accounts
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Core tokens
    WLUX public wlux;
    LuxUSD public lusd;
    LuxETH public leth;
    LuxBTC public lbtc;

    // Staking
    sLUX public slux;

    // Synths
    xUSD public xUsd;
    xETH public xEth;
    xBTC public xBtc;
    xLUX public xLux;
    xAI public xAi;
    xSOL public xSol;
    xTON public xTon;
    xADA public xAda;
    xAVAX public xAvax;
    xBNB public xBnb;
    xPOL public xPol;
    xZOO public xZoo;

    // AMM
    LuxV2Factory public factory;
    LuxV2Router public router;

    // Synths Protocol
    AlchemistV2 public alchemistImpl;
    TransmuterV2 public transmuterImpl;

    // Initial liquidity amounts (Anvil has 10k ETH per account)
    uint256 constant INITIAL_LUX = 1_000 ether;
    uint256 constant INITIAL_LUSD = 100_000 ether;
    uint256 constant INITIAL_LP = 1_000 ether;

    function run() external {
        console.log("=== Deploying Lux Full Stack ===");
        console.log("Deployer:", DEPLOYER);
        console.log("");

        vm.startBroadcast(DEPLOYER_KEY);

        // ========== Phase 1: Core Tokens ==========
        console.log("--- Phase 1: Core Tokens ---");
        
        wlux = new WLUX();
        console.log("WLUX:", address(wlux));

        lusd = new LuxUSD();
        console.log("LUSD:", address(lusd));

        leth = new LuxETH();
        console.log("LETH:", address(leth));

        lbtc = new LuxBTC();
        console.log("LBTC:", address(lbtc));

        // Mint initial supply to deployer
        lusd.mint(DEPLOYER, INITIAL_LUSD);
        leth.mint(DEPLOYER, INITIAL_LP);
        lbtc.mint(DEPLOYER, INITIAL_LP / 100); // BTC has higher value

        // Wrap some ETH to WLUX
        wlux.deposit{value: INITIAL_LUX}();
        console.log("Minted initial tokens to deployer");
        console.log("");

        // ========== Phase 2: Staking ==========
        console.log("--- Phase 2: LUX Staking ---");
        
        slux = new sLUX(address(wlux));
        console.log("sLUX:", address(slux));

        // Stake some LUX (only 100 so we have 900 left for LPs)
        uint256 stakeAmount = 100 ether;
        wlux.approve(address(slux), stakeAmount);
        slux.stake(stakeAmount);
        console.log("Staked 100 LUX -> sLUX");
        console.log("");

        // ========== Phase 3: Synth Tokens ==========
        console.log("--- Phase 3: Synth Tokens (12) ---");
        
        xUsd = new xUSD();
        xEth = new xETH();
        xBtc = new xBTC();
        xLux = new xLUX();
        xAi = new xAI();
        xSol = new xSOL();
        xTon = new xTON();
        xAda = new xADA();
        xAvax = new xAVAX();
        xBnb = new xBNB();
        xPol = new xPOL();
        xZoo = new xZOO();

        console.log("xUSD:", address(xUsd));
        console.log("xETH:", address(xEth));
        console.log("xBTC:", address(xBtc));
        console.log("xLUX:", address(xLux));
        console.log("xAI:", address(xAi));
        console.log("xSOL:", address(xSol));
        console.log("xTON:", address(xTon));
        console.log("xADA:", address(xAda));
        console.log("xAVAX:", address(xAvax));
        console.log("xBNB:", address(xBnb));
        console.log("xPOL:", address(xPol));
        console.log("xZOO:", address(xZoo));
        console.log("");

        // ========== Phase 4: AMM ==========
        console.log("--- Phase 4: AMM ---");

        factory = new LuxV2Factory(DEPLOYER);
        console.log("LuxV2Factory:", address(factory));

        router = new LuxV2Router(address(factory), address(wlux));
        console.log("LuxV2Router:", address(router));
        console.log("");

        // ========== Phase 5: Create LP Pools ==========
        console.log("--- Phase 5: LP Pools ---");

        // Mint synths for LP creation (temporary - in production done via Alchemist)
        xUsd.setWhitelist(DEPLOYER, true);
        xEth.setWhitelist(DEPLOYER, true);
        xBtc.setWhitelist(DEPLOYER, true);
        xLux.setWhitelist(DEPLOYER, true);

        xUsd.mint(DEPLOYER, INITIAL_LP);
        xEth.mint(DEPLOYER, INITIAL_LP);
        xBtc.mint(DEPLOYER, INITIAL_LP / 100);
        xLux.mint(DEPLOYER, INITIAL_LP);

        // Create WLUX/xLUX pool
        _createPool(address(wlux), address(xLux), INITIAL_LP / 10, INITIAL_LP / 10);
        console.log("Created WLUX/xLUX pool");

        // Create LUSD/xUSD pool
        _createPool(address(lusd), address(xUsd), INITIAL_LP / 10, INITIAL_LP / 10);
        console.log("Created LUSD/xUSD pool");

        // Create LETH/xETH pool
        _createPool(address(leth), address(xEth), INITIAL_LP / 100, INITIAL_LP / 100);
        console.log("Created LETH/xETH pool");

        // Create LBTC/xBTC pool
        _createPool(address(lbtc), address(xBtc), INITIAL_LP / 1000, INITIAL_LP / 1000);
        console.log("Created LBTC/xBTC pool");

        // Create WLUX/LUSD trading pool
        _createPool(address(wlux), address(lusd), INITIAL_LP / 10, INITIAL_LP / 10);
        console.log("Created WLUX/LUSD pool");

        console.log("");

        // ========== Phase 6: Synths Protocol ==========
        console.log("--- Phase 6: Synths Protocol ---");

        alchemistImpl = new AlchemistV2();
        console.log("AlchemistV2 impl:", address(alchemistImpl));

        transmuterImpl = new TransmuterV2();
        console.log("TransmuterV2 impl:", address(transmuterImpl));

        vm.stopBroadcast();

        // ========== Summary ==========
        console.log("");
        console.log("========================================");
        console.log("       DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Core Tokens:");
        console.log("  WLUX:", address(wlux));
        console.log("  LUSD:", address(lusd));
        console.log("  LETH:", address(leth));
        console.log("  LBTC:", address(lbtc));
        console.log("");
        console.log("Staking:");
        console.log("  sLUX:", address(slux));
        console.log("");
        console.log("Synth Tokens (12):");
        console.log("  xLUX:", address(xLux));
        console.log("  xAI:", address(xAi));
        console.log("  xZOO:", address(xZoo));
        console.log("  xUSD:", address(xUsd));
        console.log("  xETH:", address(xEth));
        console.log("  xBTC:", address(xBtc));
        console.log("  xSOL:", address(xSol));
        console.log("  xTON:", address(xTon));
        console.log("  xADA:", address(xAda));
        console.log("  xAVAX:", address(xAvax));
        console.log("  xBNB:", address(xBnb));
        console.log("  xPOL:", address(xPol));
        console.log("");
        console.log("AMM:");
        console.log("  Factory:", address(factory));
        console.log("  Router:", address(router));
        console.log("");
        console.log("LP Pools Created:");
        console.log("  WLUX/xLUX, LUSD/xUSD, LETH/xETH, LBTC/xBTC, WLUX/LUSD");
        console.log("");
        console.log("Protocol:");
        console.log("  AlchemistV2:", address(alchemistImpl));
        console.log("  TransmuterV2:", address(transmuterImpl));
        console.log("========================================");
    }

    function _createPool(address tokenA, address tokenB, uint256 amountA, uint256 amountB) internal {
        IERC20(tokenA).approve(address(router), amountA);
        IERC20(tokenB).approve(address(router), amountB);

        router.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            DEPLOYER,
            block.timestamp + 1 hours
        );
    }
}
