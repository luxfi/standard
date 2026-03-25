// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import { Script, console } from "forge-std/Script.sol";
import { DIDRegistry } from "@luxfi/contracts/identity/DIDRegistry.sol";

/// @title Deploy DIDRegistry only
/// @notice Standalone script to deploy DIDRegistry with sufficient gas
/// @dev Uses explicit gas limit to avoid OOG on chains with different gas costs
contract DeployDIDRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("LUX_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        DIDRegistry didRegistry = new DIDRegistry(deployer, "lux", true);
        console.log("DIDRegistry:", address(didRegistry));

        vm.stopBroadcast();
    }
}
