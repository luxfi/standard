// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

// Synth Tokens (12 total)
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

// Core Protocol
import {AlchemistV2} from "../contracts/synths/AlchemistV2.sol";
import {TransmuterV2} from "../contracts/synths/TransmuterV2.sol";
import {TransmuterBuffer} from "../contracts/synths/TransmuterBuffer.sol";

// Proxy
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeploySynths
 * @notice Deploys all 12 mainnet synth tokens and core protocol contracts
 * @dev LP-9108: Synths - Self-Repaying Synthetic Assets Standard
 * 
 * Mainnet Synths (12):
 * - Native: xLUX, xAI, xZOO
 * - Stablecoin: xUSD
 * - Major L1s: xETH, xBTC, xSOL, xTON, xADA, xAVAX, xBNB, xPOL
 * 
 * Usage:
 *   forge script script/DeploySynths.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeploySynths is Script {
    // Deployed synth tokens
    xUSD public synthUSD;
    xETH public synthETH;
    xBTC public synthBTC;
    xLUX public synthLUX;
    xAI public synthAI;
    xSOL public synthSOL;
    xTON public synthTON;
    xADA public synthADA;
    xAVAX public synthAVAX;
    xBNB public synthBNB;
    xPOL public synthPOL;
    xZOO public synthZOO;

    // Core protocol (implementation + proxy)
    AlchemistV2 public alchemistImpl;
    TransmuterV2 public transmuterImpl;
    TransmuterBuffer public bufferImpl;

    // Proxies
    AlchemistV2 public xUSDVault;
    TransmuterV2 public transmuterUSD;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying Synths Protocol ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ========== Phase 1: Deploy Synth Tokens ==========
        console.log("--- Phase 1: Synth Tokens (12) ---");
        
        // Native Lux Tokens
        synthLUX = new xLUX();
        console.log("xLUX deployed:", address(synthLUX));
        
        synthAI = new xAI();
        console.log("xAI deployed:", address(synthAI));
        
        synthZOO = new xZOO();
        console.log("xZOO deployed:", address(synthZOO));
        
        // Stablecoin
        synthUSD = new xUSD();
        console.log("xUSD deployed:", address(synthUSD));
        
        // Major L1s
        synthETH = new xETH();
        console.log("xETH deployed:", address(synthETH));
        
        synthBTC = new xBTC();
        console.log("xBTC deployed:", address(synthBTC));
        
        synthSOL = new xSOL();
        console.log("xSOL deployed:", address(synthSOL));
        
        synthTON = new xTON();
        console.log("xTON deployed:", address(synthTON));
        
        synthADA = new xADA();
        console.log("xADA deployed:", address(synthADA));
        
        synthAVAX = new xAVAX();
        console.log("xAVAX deployed:", address(synthAVAX));
        
        synthBNB = new xBNB();
        console.log("xBNB deployed:", address(synthBNB));
        
        synthPOL = new xPOL();
        console.log("xPOL deployed:", address(synthPOL));
        
        console.log("");

        // ========== Phase 2: Deploy Protocol Implementations ==========
        console.log("--- Phase 2: Protocol Implementations ---");
        
        alchemistImpl = new AlchemistV2();
        console.log("AlchemistV2 impl:", address(alchemistImpl));
        
        transmuterImpl = new TransmuterV2();
        console.log("TransmuterV2 impl:", address(transmuterImpl));
        
        bufferImpl = new TransmuterBuffer();
        console.log("TransmuterBuffer impl:", address(bufferImpl));
        
        console.log("");

        // ========== Phase 3: Deploy Proxies (xUSD example) ==========
        console.log("--- Phase 3: Protocol Proxies (xUSD) ---");
        
        // Transmuter proxy for xUSD
        bytes memory transmuterInitData = abi.encodeWithSelector(
            TransmuterV2.initialize.selector,
            address(synthUSD),  // syntheticToken
            address(0),         // underlyingToken (to be set)
            address(0)          // buffer (to be set)
        );
        ERC1967Proxy transmuterProxy = new ERC1967Proxy(
            address(transmuterImpl),
            transmuterInitData
        );
        transmuterUSD = TransmuterV2(address(transmuterProxy));
        console.log("TransmuterV2 proxy (xUSD):", address(transmuterUSD));
        
        // Alchemist proxy for xUSD
        bytes memory alchemistInitData = abi.encodeWithSelector(
            AlchemistV2.initialize.selector,
            address(synthUSD),      // debtToken
            deployer                // admin
        );
        ERC1967Proxy alchemistProxy = new ERC1967Proxy(
            address(alchemistImpl),
            alchemistInitData
        );
        xUSDVault = AlchemistV2(address(alchemistProxy));
        console.log("AlchemistV2 proxy (xUSD):", address(xUSDVault));

        vm.stopBroadcast();

        // ========== Summary ==========
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("Synth Tokens (12):");
        console.log("  xLUX:  ", address(synthLUX));
        console.log("  xAI:   ", address(synthAI));
        console.log("  xZOO:  ", address(synthZOO));
        console.log("  xUSD:  ", address(synthUSD));
        console.log("  xETH:  ", address(synthETH));
        console.log("  xBTC:  ", address(synthBTC));
        console.log("  xSOL:  ", address(synthSOL));
        console.log("  xTON:  ", address(synthTON));
        console.log("  xADA:  ", address(synthADA));
        console.log("  xAVAX: ", address(synthAVAX));
        console.log("  xBNB:  ", address(synthBNB));
        console.log("  xPOL:  ", address(synthPOL));
        console.log("");
        console.log("Protocol:");
        console.log("  AlchemistV2 impl:   ", address(alchemistImpl));
        console.log("  TransmuterV2 impl:  ", address(transmuterImpl));
        console.log("  TransmuterBuffer:   ", address(bufferImpl));
        console.log("  AlchemistV2 (xUSD): ", address(xUSDVault));
        console.log("  TransmuterV2 (xUSD):", address(transmuterUSD));
    }
}
