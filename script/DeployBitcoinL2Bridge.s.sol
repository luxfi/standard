// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/bridge/teleport/Teleporter.sol";
import "../contracts/bridge/LRC20B.sol";
import "../contracts/bridge/chains/BitcoinL2ChainIds.sol";

/// @title Deploy Lux Bridge to any Bitcoin L2
/// @notice Same contracts, different chain. Run once per L2.
///
/// Usage:
///   # Deploy to BOB
///   forge script script/DeployBitcoinL2Bridge.s.sol --rpc-url https://rpc.gobob.xyz --broadcast
///
///   # Deploy to Merlin
///   forge script script/DeployBitcoinL2Bridge.s.sol --rpc-url https://rpc.merlinchain.io --broadcast
///
///   # Deploy to Rootstock
///   forge script script/DeployBitcoinL2Bridge.s.sol --rpc-url https://public-node.rsk.co --broadcast
///
///   # Deploy to ANY EVM Bitcoin L2 — just change --rpc-url
contract DeployBitcoinL2Bridge is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address mpcSigner = vm.envAddress("MPC_SIGNER");

        vm.startBroadcast(deployerKey);

        // 1. Deploy Teleporter (core bridge logic)
        Teleporter teleporter = new Teleporter(mpcSigner);

        // 2. Deploy wrapped BTC token (LBTC)
        // LRC20B is the bridgeable ERC-20 with mint/burn roles
        // The Teleporter contract gets MINTER_ROLE
        // Users burn LBTC here → MPC releases real BTC from Taproot vault

        console.log("Teleporter:", address(teleporter));
        console.log("Chain ID:", block.chainid);
        console.log("MPC Signer:", mpcSigner);

        vm.stopBroadcast();
    }
}
