// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {SubDAO} from "../contracts/governance/SubDAO.sol";

/**
 * @title DeploySubDAOs
 * @notice Deploys MIGA and CYRUS Sub-DAOs for Pars governance
 */
contract DeploySubDAOs is Script {
    // Deployed Governor addresses per chain
    mapping(uint256 => address) public governors;

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

        console.log("=== SubDAO Deployment ===");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("");

        // Set Governor addresses for known chains
        governors[96370] = 0x6fc44509a32E513bE1aa00d27bb298e63830C6A8; // Lux Devnet
        governors[96369] = address(0); // Lux Mainnet - to be deployed
        governors[200200] = address(0); // Zoo Mainnet - to be deployed
        governors[200201] = address(0); // Zoo Testnet - to be deployed

        address governor = governors[chainId];
        if (governor == address(0)) {
            console.log("No Governor deployed for this chain yet");
            console.log("Using deployer as mainDAO placeholder");
            governor = deployer;
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MIGA SubDAO
        migaSubDAO = new SubDAO(
            "MIGA",
            governor,
            deployer,
            51,      // 51% quorum
            7 days   // voting period
        );
        console.log("MIGA SubDAO:", address(migaSubDAO));

        // Deploy CYRUS SubDAO
        cyrusSubDAO = new SubDAO(
            "CYRUS",
            governor,
            deployer,
            51,      // 51% quorum
            7 days   // voting period
        );
        console.log("CYRUS SubDAO:", address(cyrusSubDAO));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("Main DAO (Governor):", governor);
        console.log("MIGA SubDAO:", address(migaSubDAO));
        console.log("CYRUS SubDAO:", address(cyrusSubDAO));
    }
}
