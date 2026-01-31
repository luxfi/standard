// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Governance Stack
import {VotingLUX} from "../contracts/governance/VotingLUX.sol";
import {Strategy} from "../contracts/governance/Strategy.sol";
import {Governor} from "../contracts/governance/Governor.sol";
import {Karma} from "../contracts/governance/Karma.sol";
import {DLUX} from "../contracts/governance/DLUX.sol";

// Sub-DAO System
import {SubDAO} from "../contracts/governance/SubDAO.sol";

/**
 * @title DeployMultiChainGovernance
 * @notice Deploys governance to multiple chains with sub-DAO support
 *
 * CHAINS TO DEPLOY:
 * - Lux Mainnet (96369)
 * - Lux Devnet (96370) - DONE
 * - Zoo Mainnet (200200)
 * - Zoo Testnet (200201)
 * - Ethereum Mainnet (1) - MIGA/CYRUS
 * - Arbitrum (42161) - MIGA/CYRUS
 * - Base (8453) - MIGA/CYRUS
 * - Polygon (137) - MIGA/CYRUS
 *
 * SUB-DAOs FOR PARS:
 * - MIGA SubDAO
 * - CYRUS SubDAO
 */
contract DeployMultiChainGovernance is Script {
    // Governance contracts
    VotingLUX public votingLUX;
    Strategy public strategy;
    Governor public governor;
    Karma public karma;
    DLUX public dlux;

    // Sub-DAOs
    SubDAO public migaSubDAO;
    SubDAO public cyrusSubDAO;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey == 0) {
            string memory mnemonic = vm.envString("LUX_MNEMONIC");
            deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        }

        address deployer = vm.addr(deployerPrivateKey);
        uint256 chainId = block.chainid;

        console.log("=== Multi-Chain Governance Deployment ===");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        if (chainId == 96369 || chainId == 96370) {
            // Lux chains
            _deployLuxGovernance(deployer);
        } else if (chainId == 200200 || chainId == 200201) {
            // Zoo chains
            _deployZooGovernance(deployer);
        } else {
            // EVM chains (Ethereum, Arbitrum, Base, Polygon) - Pars/MIGA/CYRUS
            _deployParsGovernance(deployer);
        }

        vm.stopBroadcast();
    }

    function _deployLuxGovernance(address deployer) internal {
        console.log("--- Deploying Lux Governance ---");

        // Already deployed on devnet, deploy fresh on mainnet
        votingLUX = new VotingLUX(
            address(0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a), // vLUX
            address(0x316520ca05eaC5d2418F562a116091F1b22Bf6e0)  // DLUX
        );
        console.log("VotingLUX:", address(votingLUX));

        strategy = new Strategy();
        console.log("Strategy:", address(strategy));

        governor = new Governor();
        console.log("Governor:", address(governor));
    }

    function _deployZooGovernance(address deployer) internal {
        console.log("--- Deploying Zoo Governance ---");

        // Zoo uses ZOO token for voting
        votingLUX = new VotingLUX(
            address(0), // vZOO - to be set
            address(0)  // DZOO - to be set
        );
        console.log("VotingZOO:", address(votingLUX));

        strategy = new Strategy();
        console.log("Strategy:", address(strategy));

        governor = new Governor();
        console.log("Governor:", address(governor));
    }

    function _deployParsGovernance(address deployer) internal {
        console.log("--- Deploying Pars Governance with Sub-DAOs ---");

        // Main governance
        strategy = new Strategy();
        console.log("Strategy:", address(strategy));

        governor = new Governor();
        console.log("Governor:", address(governor));

        // MIGA SubDAO
        migaSubDAO = new SubDAO(
            "MIGA",
            address(governor),
            deployer,
            51,  // 51% quorum
            7 days // voting period
        );
        console.log("MIGA SubDAO:", address(migaSubDAO));

        // CYRUS SubDAO
        cyrusSubDAO = new SubDAO(
            "CYRUS",
            address(governor),
            deployer,
            51,  // 51% quorum
            7 days // voting period
        );
        console.log("CYRUS SubDAO:", address(cyrusSubDAO));
    }
}
