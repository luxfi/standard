// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Remaining contracts to deploy
import {Governor} from "../contracts/governance/Governor.sol";
import {StableSwapFactory} from "../contracts/amm/StableSwapFactory.sol";
import {Options} from "../contracts/options/Options.sol";
import {Streams} from "../contracts/streaming/Streams.sol";

/**
 * @title DeployGovernanceRemaining
 * @notice Deploys remaining Phase 13-14 contracts that failed to broadcast
 *
 * Already deployed (from previous attempts):
 * - VotingLUX: 0x43222597839515180E7aD564C94a3b5c16EB987C
 * - Strategy: 0x4EC24Da7d598CAC1540F2E8078D05869e36a4ef1
 * - IntentRouter: 0x5ED08c64FbF027966C04E6fc87E6b58a91De4dB2
 * - Cover: 0x92d057F8B4132Ca8Aa237fbd4C41F9c57079582E
 *
 * Still need to deploy:
 * - Governor
 * - StableSwapFactory
 * - Options
 * - Streams
 */
contract DeployGovernanceRemaining is Script {
    // Already deployed addresses
    address constant WLUX = 0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec;
    address constant DAO_TREASURY = 0xC764A58Ee3C5bAE3008C034E566352424be933F3;
    address constant MARKETS = 0x6fc44509a32E513bE1aa00d27bb298e63830C6A8;
    address constant ORACLE = MARKETS; // Markets doubles as oracle

    // Contracts to deploy
    Governor public governor;
    StableSwapFactory public stableSwapFactory;
    Options public options;
    Streams public streams;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey == 0) {
            string memory mnemonic = vm.envString("LUX_MNEMONIC");
            deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        }

        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== Deploying Remaining Governance Suite ===");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Governor (uses initializer pattern)
        governor = new Governor();
        console.log("Governor:", address(governor));

        // StableSwap Factory (Curve-style AMM for stables)
        stableSwapFactory = new StableSwapFactory(deployer, DAO_TREASURY);
        console.log("StableSwapFactory:", address(stableSwapFactory));

        // Options protocol (requires oracle)
        options = new Options(ORACLE, DAO_TREASURY, deployer);
        console.log("Options:", address(options));

        // Payment Streams
        streams = new Streams(DAO_TREASURY, deployer);
        console.log("Streams:", address(streams));

        vm.stopBroadcast();

        _printSummary();
    }

    function _printSummary() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("                  REMAINING CONTRACTS DEPLOYED");
        console.log("================================================================================");
        console.log("");
        console.log("NEW DEPLOYMENTS:");
        console.log("  Governor:          ", address(governor));
        console.log("  StableSwapFactory: ", address(stableSwapFactory));
        console.log("  Options:           ", address(options));
        console.log("  Streams:           ", address(streams));
        console.log("");
        console.log("ALREADY DEPLOYED:");
        console.log("  VotingLUX:     0x43222597839515180E7aD564C94a3b5c16EB987C");
        console.log("  Strategy:      0x4EC24Da7d598CAC1540F2E8078D05869e36a4ef1");
        console.log("  IntentRouter:  0x5ED08c64FbF027966C04E6fc87E6b58a91De4dB2");
        console.log("  Cover:         0x92d057F8B4132Ca8Aa237fbd4C41F9c57079582E");
        console.log("");
        console.log("================================================================================");
        console.log("             PHASES 13-14 NOW COMPLETE");
        console.log("================================================================================");
    }
}
