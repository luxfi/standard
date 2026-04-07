// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/bridge/TeleportProposalBridge.sol";
import "../contracts/bridge/teleport/Teleporter.sol";
import "../contracts/bridge/chains/BitcoinL2ChainIds.sol";

/// @title Register OP_NET as a Teleport locale and deploy LBTC Teleporter
/// @notice OP_NET is a non-EVM Bitcoin L1 chain (AssemblyScript/btc-runtime).
///         Virtual chain ID: 4294967299 (Bitcoin L1 virtual ID).
///
/// Usage:
///   forge script script/RegisterOPNET.s.sol \
///     --rpc-url $LUX_RPC \
///     --broadcast
contract RegisterOPNET is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address bridge = vm.envAddress("TELEPORT_BRIDGE");
        address lbtc = vm.envAddress("LBTC_TOKEN");
        address mpcSigner = vm.envAddress("MPC_SIGNER");

        vm.startBroadcast(deployerKey);

        // 1. Register OP_NET locale on TeleportProposalBridge
        TeleportProposalBridge(bridge).registerLocale(
            BitcoinL2ChainIds.OPNET,
            "OP_NET (Bitcoin L1)",
            address(0) // Non-EVM -- no on-chain bridge endpoint
        );

        // 2. Deploy Teleporter instance for LBTC with OP_NET as source
        Teleporter teleporter = new Teleporter(lbtc, mpcSigner);

        console.log("OP_NET locale registered, chainId:", BitcoinL2ChainIds.OPNET);
        console.log("LBTC Teleporter:", address(teleporter));
        console.log("LBTC token:", lbtc);
        console.log("MPC Signer:", mpcSigner);

        vm.stopBroadcast();
    }
}
