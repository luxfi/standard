// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Additional Governance
import {VotingLUX} from "../contracts/governance/VotingLUX.sol";
import {Governor} from "../contracts/governance/Governor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

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
    // Phase 1-12 addresses — read from env, fallback to devnet/testnet defaults
    address public WLUX;
    address public DLUX;
    address public TIMELOCK;
    address public VLUX;
    address public VOTES_TOKEN;
    address public MARKETS;
    address public DAO_TREASURY;

    function _loadAddresses() internal {
        WLUX = vm.envOr("WLUX", address(0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec));
        DLUX = vm.envOr("DLUX", address(0x316520ca05eaC5d2418F562a116091F1b22Bf6e0));
        TIMELOCK = vm.envOr("TIMELOCK", address(0x80f3bd0Bdf7861487dDDA61bc651243ecB8B5072));
        VLUX = vm.envOr("VLUX", address(0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a));
        VOTES_TOKEN = vm.envOr("VOTES_TOKEN", address(0xE77E1cB5E303ed0EcB10d0d13914AaA2ED9B3b8C));
        MARKETS = vm.envOr("MARKETS", address(0x6fc44509a32E513bE1aa00d27bb298e63830C6A8));
        DAO_TREASURY = vm.envOr("DAO_TREASURY", address(0xC764A58Ee3C5bAE3008C034E566352424be933F3));
    }

    // Governance
    VotingLUX public votingLUX;
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
        _loadAddresses();
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
        votingLUX = new VotingLUX(VLUX, DLUX);
        console.log("VotingLUX:", address(votingLUX));

        // Governor requires TimelockController + IVotes — deploy with Timelock and VotesToken
        governor = new Governor(
            IVotes(VOTES_TOKEN),
            TimelockController(payable(TIMELOCK)),
            1 days,    // votingDelay
            1 weeks,   // votingPeriod
            100e18,    // proposalThreshold (100 tokens)
            4          // quorumNumerator (4%)
        );
        console.log("Governor:", address(governor));
        console.log("");
    }

    function _deployPhase14DeFiSuite(address deployer) internal {
        console.log("--- Phase 14: DeFi Suite ---");

        // StableSwap Factory (Curve-style AMM for stables)
        stableSwapFactory = new StableSwapFactory(deployer, DAO_TREASURY);
        console.log("StableSwapFactory:", address(stableSwapFactory));

        // Options protocol (requires oracle — use Markets as oracle)
        options = new Options(MARKETS, DAO_TREASURY, deployer);
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
