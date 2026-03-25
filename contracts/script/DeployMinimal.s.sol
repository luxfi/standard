// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import { Script, console } from "forge-std/Script.sol";

// Core native token
import { WLUX } from "@luxfi/contracts/tokens/WLUX.sol";

// Bridged Collateral Tokens
import { BridgedETH } from "@luxfi/contracts/bridge/collateral/ETH.sol";
import { BridgedBTC } from "@luxfi/contracts/bridge/collateral/BTC.sol";
import { BridgedUSDC } from "@luxfi/contracts/bridge/collateral/USDC.sol";

// Staking
import { sLUX as StakedLUX } from "@luxfi/contracts/staking/sLUX.sol";

// AMM
import { AMMV2Factory } from "@luxfi/contracts/amm/AMMV2Factory.sol";
import { AMMV2Router } from "@luxfi/contracts/amm/AMMV2Router.sol";

// Governance
import { Timelock } from "@luxfi/contracts/governance/Timelock.sol";
import { vLUX } from "@luxfi/contracts/governance/vLUX.sol";
import { GaugeController } from "@luxfi/contracts/governance/GaugeController.sol";
import { Karma } from "@luxfi/contracts/governance/Karma.sol";
import { DLUX } from "@luxfi/contracts/governance/DLUX.sol";

// Identity/DID
import { DIDRegistry } from "@luxfi/contracts/identity/DIDRegistry.sol";

// Treasury
import { FeeGov } from "@luxfi/contracts/treasury/FeeGov.sol";
import { ValidatorVault } from "@luxfi/contracts/treasury/ValidatorVault.sol";

// LSSVM (NFT AMM)
import { LSSVMPairFactory } from "@luxfi/contracts/lssvm/LSSVMPairFactory.sol";
import { LinearCurve } from "@luxfi/contracts/lssvm/LinearCurve.sol";
import { ExponentialCurve } from "@luxfi/contracts/lssvm/ExponentialCurve.sol";

// Markets (Lending)
import { Markets } from "@luxfi/contracts/markets/Markets.sol";

// Perps
import { Perp } from "@luxfi/contracts/perps/Perp.sol";

/**
 * @title DeployMinimal
 * @notice Deploy all Lux standard contracts with minimal token operations
 * @dev Uses only gas, no large LUX wrapping/staking/pooling
 *
 * Usage:
 *   LUX_PRIVATE_KEY=0x... forge script contracts/script/DeployMinimal.s.sol \
 *     --rpc-url https://api.lux.network/mainnet/ext/bc/C/rpc --broadcast --legacy -vvv
 */
contract DeployMinimal is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("LUX_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Minimal Lux Standard Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "LUX");
        console.log("");

        vm.startBroadcast(deployerKey);

        // Phase 1: Core Tokens (deploy only, minimal wrap)
        WLUX wlux = new WLUX();
        console.log("WLUX:", address(wlux));

        // Wrap just 1 LUX for setup
        wlux.deposit{ value: 1 ether }();

        BridgedETH leth = new BridgedETH();
        console.log("LETH:", address(leth));

        BridgedBTC lbtc = new BridgedBTC();
        console.log("LBTC:", address(lbtc));

        BridgedUSDC lusdc = new BridgedUSDC();
        console.log("LUSDC:", address(lusdc));

        // Phase 2: Staking
        StakedLUX stakedLux = new StakedLUX(address(wlux));
        console.log("StakedLUX:", address(stakedLux));

        // Phase 3: AMM
        AMMV2Factory factory = new AMMV2Factory(deployer);
        console.log("AMMV2Factory:", address(factory));

        AMMV2Router router = new AMMV2Router(address(factory), address(wlux));
        console.log("AMMV2Router:", address(router));

        // Phase 4: Governance
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        Timelock timelock = new Timelock(1 days, proposers, executors, deployer);
        console.log("Timelock:", address(timelock));

        vLUX voteLux = new vLUX(address(wlux));
        console.log("vLUX:", address(voteLux));

        GaugeController gaugeController = new GaugeController(address(voteLux));
        console.log("GaugeController:", address(gaugeController));

        Karma karma = new Karma(deployer);
        console.log("Karma:", address(karma));

        DLUX dlux = new DLUX(address(wlux), deployer, deployer);
        console.log("DLUX:", address(dlux));

        // Phase 5: Identity (may revert on subnet EVM - Cancun opcode issue)
        try new DIDRegistry(deployer, "lux", true) returns (DIDRegistry did) {
            console.log("DIDRegistry:", address(did));
        } catch {
            console.log("DIDRegistry: REVERTED (Cancun opcode incompatibility)");
        }

        // Phase 6: Treasury
        FeeGov feeGov = new FeeGov(30, 10, 500, deployer);
        console.log("FeeGov:", address(feeGov));

        ValidatorVault validatorVault = new ValidatorVault(address(wlux));
        console.log("ValidatorVault:", address(validatorVault));

        // Phase 7: LSSVM
        LinearCurve linearCurve = new LinearCurve();
        console.log("LinearCurve:", address(linearCurve));

        ExponentialCurve exponentialCurve = new ExponentialCurve();
        console.log("ExponentialCurve:", address(exponentialCurve));

        LSSVMPairFactory lssvmFactory = new LSSVMPairFactory(deployer);
        console.log("LSSVMPairFactory:", address(lssvmFactory));

        lssvmFactory.setBondingCurveAllowed(address(linearCurve), true);
        lssvmFactory.setBondingCurveAllowed(address(exponentialCurve), true);

        // Phase 8: DeFi
        Markets markets = new Markets(deployer);
        console.log("Markets:", address(markets));

        Perp perp = new Perp(address(wlux), deployer, deployer);
        console.log("Perp:", address(perp));

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Total contracts: 20");
    }
}
