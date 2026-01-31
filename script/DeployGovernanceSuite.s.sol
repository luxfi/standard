// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Additional Governance
import {VotingLUX} from "../contracts/governance/VotingLUX.sol";
import {Strategy} from "../contracts/governance/Strategy.sol";
import {Governor} from "../contracts/governance/Governor.sol";

// DeFi Suite
import {StableSwapFactory} from "../contracts/amm/StableSwapFactory.sol";
import {Options} from "../contracts/options/Options.sol";
import {Streams} from "../contracts/streaming/Streams.sol";
import {IntentRouter} from "../contracts/router/IntentRouter.sol";
import {Cover} from "../contracts/insurance/Cover.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployGovernanceSuite
 * @notice Deploys full governance stack and DeFi suite on top of existing deployment
 *
 * Already deployed on devnet (phases 1-12):
 * - WLUX: 0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec
 * - DLUX: 0x316520ca05eaC5d2418F562a116091F1b22Bf6e0
 * - Timelock: 0x80f3bd0Bdf7861487dDDA61bc651243ecB8B5072
 * - vLUX: 0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a
 * - DAO Treasury: 0xC764A58Ee3C5bAE3008C034E566352424be933F3
 * - Markets: 0x6fc44509a32E513bE1aa00d27bb298e63830C6A8
 *
 * NOTE: FHE contracts are abstract and require FHE precompile infrastructure.
 *       They will be deployed separately when Q-Chain FHE is enabled.
 */
contract DeployGovernanceSuite is Script {
    // Already deployed addresses from phases 1-12
    address constant WLUX = 0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec;
    address constant DLUX = 0x316520ca05eaC5d2418F562a116091F1b22Bf6e0;
    address constant DLUX_MINTER = 0xcd7ee976df9C8a2709a14bda8463af43e6097A56;
    address constant TIMELOCK = 0x80f3bd0Bdf7861487dDDA61bc651243ecB8B5072;
    address constant AMM_FACTORY = 0x0570b2c59976E87D37d3a9915750BFf131d295D6;
    address constant STAKED_LUX = 0x191067f88d61f9506555E88CEab9CF71deeD61A9;
    address constant KARMA = 0x97c265001EB088E1dE2F77A13a62B708014c9e68;
    address constant VLUX = 0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a;
    address constant GAUGE_CONTROLLER = 0x26328AC03d07BD9A7Caaafbde39F9b56B5449240;
    address constant VOTES_TOKEN = 0xE77E1cB5E303ed0EcB10d0d13914AaA2ED9B3b8C;
    address constant BRIDGED_USDC = 0x7fC4f8a926E47Fa3587C0d7658C00E7489e67916;
    address constant BRIDGED_DAI = 0xC64BD67b39765127ae5DBdd750Fb6a9f62c3269f;
    address constant BRIDGED_USDT = 0x51c3408B9A6a0B2446CCB78c72C846CEB76201FA;
    address constant DAO_TREASURY = 0xC764A58Ee3C5bAE3008C034E566352424be933F3;
    address constant TREASURY_ROUTER = 0xF9aEC94ED6F098509EbCD5690AE2Cb126cd8a3Ee;
    address constant MARKETS = 0x6fc44509a32E513bE1aa00d27bb298e63830C6A8;
    address constant PERP = 0xb2ee1CE7b84853b83AA08702aD0aD4D79711882D;
    address constant FEE_GOV = 0x92d057F8B4132Ca8Aa237fbd4C41F9c57079582E;
    address constant AI_TOKEN = 0x62Ea1B27CDD922dbAaE0572f4CD4862Ca939C24c;
    address constant ORACLE = 0x6fc44509a32E513bE1aa00d27bb298e63830C6A8; // Markets doubles as oracle

    // Governance
    VotingLUX public votingLUX;
    Strategy public strategy;
    Governor public governor;

    // DeFi Suite
    StableSwapFactory public stableSwapFactory;
    Options public options;
    Streams public streams;
    IntentRouter public intentRouter;
    Cover public cover;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey == 0) {
            string memory mnemonic = vm.envString("LUX_MNEMONIC");
            deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        }

        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== Deploying Governance Suite ===");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 13: Advanced Governance (Strategy + Governor + VotingLUX)
        _deployPhase13AdvancedGovernance(deployer);

        // Phase 14: DeFi Suite
        _deployPhase14DeFiSuite(deployer);

        vm.stopBroadcast();

        _printSummary();
    }

    function _deployPhase13AdvancedGovernance(address deployer) internal {
        console.log("--- Phase 13: Advanced Governance ---");

        // Deploy VotingLUX (aggregated voting power = xLUX + DLUX)
        // Using VLUX (which is the vLUX contract address) for xLUX and DLUX for rebasing tokens
        votingLUX = new VotingLUX(VLUX, DLUX);
        console.log("VotingLUX:", address(votingLUX));

        // Deploy Strategy (uses initializer pattern)
        strategy = new Strategy();
        console.log("Strategy:", address(strategy));

        // Deploy Governor (uses initializer pattern)
        governor = new Governor();
        console.log("Governor:", address(governor));
        console.log("");
    }

    function _deployPhase14DeFiSuite(address deployer) internal {
        console.log("--- Phase 14: DeFi Suite ---");

        // StableSwap Factory (Curve-style AMM for stables)
        stableSwapFactory = new StableSwapFactory(deployer, DAO_TREASURY);
        console.log("StableSwapFactory:", address(stableSwapFactory));

        // Options protocol (requires oracle)
        options = new Options(ORACLE, DAO_TREASURY, deployer);
        console.log("Options:", address(options));

        // Payment Streams
        streams = new Streams(DAO_TREASURY, deployer);
        console.log("Streams:", address(streams));

        // Intent Router (for aggregated swaps)
        intentRouter = new IntentRouter(DAO_TREASURY, deployer);
        console.log("IntentRouter:", address(intentRouter));

        // Cover Protocol (insurance)
        cover = new Cover(WLUX, DAO_TREASURY, DAO_TREASURY, deployer);
        console.log("Cover:", address(cover));
        console.log("");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("                    GOVERNANCE SUITE DEPLOYMENT COMPLETE");
        console.log("================================================================================");
        console.log("");
        console.log("ADVANCED GOVERNANCE:");
        console.log("  VotingLUX:    ", address(votingLUX));
        console.log("  Strategy:     ", address(strategy));
        console.log("  Governor:     ", address(governor));
        console.log("");
        console.log("DEFI SUITE:");
        console.log("  StableSwapFactory:", address(stableSwapFactory));
        console.log("  Options:          ", address(options));
        console.log("  Streams:          ", address(streams));
        console.log("  IntentRouter:     ", address(intentRouter));
        console.log("  Cover:            ", address(cover));
        console.log("");
        console.log("NOTE: FHE Governance (ConfidentialGovernor, etc.) requires FHE precompiles.");
        console.log("      Deploy on Q-Chain when FHE infrastructure is enabled.");
        console.log("");
        console.log("================================================================================");
        console.log("               PHASES 13-14 DEPLOYED - GOVERNANCE + DEFI COMPLETE");
        console.log("================================================================================");
    }
}
