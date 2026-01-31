// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Governance
import {Governor} from "../contracts/governance/Governor.sol";
import {Strategy} from "../contracts/governance/Strategy.sol";
import {FreezeGuard} from "../contracts/governance/freeze/FreezeGuard.sol";
import {FreezeVoting} from "../contracts/governance/freeze/FreezeVoting.sol";
import {VotesToken} from "../contracts/governance/VotesToken.sol";

// Safe (re-exported from @safe-global)
import {Safe, SafeL2, SafeProxyFactory, MultiSendCallOnly, CompatibilityFallbackHandler} from "../contracts/safe/Safe.sol";

/**
 * @title DeployLocal
 * @notice Deploy Lux governance contracts to local Anvil for development
 * @dev Minimal deployment without external dependencies
 *
 * Usage:
 *   anvil --chain-id 1337
 *   forge script script/DeployLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
 */
contract DeployLocal is Script {
    // Deployed contracts
    SafeL2 public safeSingleton;
    SafeProxyFactory public safeFactory;
    MultiSendCallOnly public multiSend;
    CompatibilityFallbackHandler public fallbackHandler;

    Governor public governor;
    Strategy public strategy;
    FreezeGuard public freezeGuard;
    FreezeVoting public freezeVoting;
    VotesToken public votesToken;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey == 0) {
            // Default Anvil private key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }

        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== Deploying Lux Governance to Local Anvil ===");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Safe Infrastructure
        _deploySafeInfrastructure();

        // Phase 2: Governance Contracts
        _deployGovernance(deployer);

        vm.stopBroadcast();

        _printSummary();
    }

    function _deploySafeInfrastructure() internal {
        console.log("--- Phase 1: Safe Infrastructure ---");

        safeSingleton = new SafeL2();
        console.log("SafeL2:", address(safeSingleton));

        safeFactory = new SafeProxyFactory();
        console.log("SafeProxyFactory:", address(safeFactory));

        multiSend = new MultiSendCallOnly();
        console.log("MultiSendCallOnly:", address(multiSend));

        fallbackHandler = new CompatibilityFallbackHandler();
        console.log("CompatibilityFallbackHandler:", address(fallbackHandler));
        console.log("");
    }

    function _deployGovernance(address deployer) internal {
        console.log("--- Phase 2: Governance ---");

        // Deploy VotesToken (ERC20 with voting)
        VotesToken.Allocation[] memory allocations = new VotesToken.Allocation[](1);
        allocations[0] = VotesToken.Allocation({
            recipient: deployer,
            amount: 1_000_000 ether  // 1M tokens to deployer
        });

        votesToken = new VotesToken(
            "Lux Governance",  // name
            "vLUX",            // symbol
            allocations,       // initial allocations
            deployer,          // owner
            0,                 // maxSupply (0 = unlimited)
            false              // locked (false = transferable)
        );
        console.log("VotesToken:", address(votesToken));

        // Deploy Strategy (voting strategy) - uses initializer pattern
        strategy = new Strategy();
        console.log("Strategy:", address(strategy));

        // Deploy Governor (main governance) - uses initializer pattern
        governor = new Governor();
        console.log("Governor:", address(governor));

        // Deploy FreezeGuard - uses initializer pattern
        freezeGuard = new FreezeGuard();
        console.log("FreezeGuard:", address(freezeGuard));

        // Deploy FreezeVoting - uses initializer pattern
        freezeVoting = new FreezeVoting();
        console.log("FreezeVoting:", address(freezeVoting));
        console.log("");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("                    LOCAL DEPLOYMENT COMPLETE");
        console.log("================================================================================");
        console.log("");
        console.log("SAFE INFRASTRUCTURE:");
        console.log("  SafeL2:                      ", address(safeSingleton));
        console.log("  SafeProxyFactory:            ", address(safeFactory));
        console.log("  MultiSendCallOnly:           ", address(multiSend));
        console.log("  CompatibilityFallbackHandler:", address(fallbackHandler));
        console.log("");
        console.log("GOVERNANCE:");
        console.log("  VotesToken:   ", address(votesToken));
        console.log("  Strategy:     ", address(strategy));
        console.log("  Governor:     ", address(governor));
        console.log("  FreezeGuard:  ", address(freezeGuard));
        console.log("  FreezeVoting: ", address(freezeVoting));
        console.log("");
        console.log("================================================================================");
    }
}
