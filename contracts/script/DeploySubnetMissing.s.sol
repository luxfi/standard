// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Core native token
import {WLUX} from "@luxfi/contracts/tokens/WLUX.sol";

// Bridged Collateral Tokens
import {BridgedETH} from "@luxfi/contracts/bridge/collateral/ETH.sol";
import {BridgedBTC} from "@luxfi/contracts/bridge/collateral/BTC.sol";
import {BridgedUSDC} from "@luxfi/contracts/bridge/collateral/USDC.sol";

// Governance
import {Timelock} from "@luxfi/contracts/governance/Timelock.sol";
import {vLUX} from "@luxfi/contracts/governance/vLUX.sol";
import {GaugeController} from "@luxfi/contracts/governance/GaugeController.sol";
import {Karma} from "@luxfi/contracts/governance/Karma.sol";
import {DLUX} from "@luxfi/contracts/governance/DLUX.sol";

// Identity/DID
import {DIDRegistry} from "@luxfi/contracts/identity/DIDRegistry.sol";

// Treasury
import {FeeGov} from "@luxfi/contracts/treasury/FeeGov.sol";
import {ValidatorVault} from "@luxfi/contracts/treasury/ValidatorVault.sol";

// Markets (Lending)
import {Markets} from "@luxfi/contracts/markets/Markets.sol";

/**
 * @title DeploySubnetMissing
 * @notice Deploy the 13 missing contracts to subnet chains
 * @dev Subnets already have 7 contracts deployed (StakedLUX, AMMV2Factory,
 *      AMMV2Router, LinearCurve, ExponentialCurve, LSSVMPairFactory, Perp).
 *      This script deploys only the 13 that are missing.
 *      Skips LP pool creation (Phase 4) since no V3 on subnets.
 *
 * Deploy key: 0xEAbCC110fAcBfebabC66Ad6f9E7B67288e720B59
 *
 * Subnet chains (all share addresses from deployer nonce):
 *   Mainnet: Zoo (200200), Hanzo (36963), SPC (36911), Pars (494949)
 *   Testnet: Zoo (200201), Hanzo (36964), SPC (36910), Pars (7071)
 *   Devnet:  Zoo (200202), Hanzo (36964), SPC (36912), Pars (494951)
 *
 * Usage:
 *   export LUX_PRIVATE_KEY=<deployer-private-key>
 *
 *   # Example: Deploy to Zoo mainnet
 *   forge script contracts/script/DeploySubnetMissing.s.sol \
 *     --rpc-url https://api.lux.network/mainnet/ext/bc/<zoo-blockchain-id>/rpc \
 *     --broadcast -vvv
 */
contract DeploySubnetMissing is Script {
    // Deployer
    address public deployer;
    uint256 public deployerKey;

    // ========== Core Tokens ==========
    WLUX public wlux;
    BridgedETH public leth;
    BridgedBTC public lbtc;
    BridgedUSDC public lusdc;

    // ========== Governance ==========
    Timelock public timelock;
    vLUX public voteLux;
    GaugeController public gaugeController;
    Karma public karma;
    DLUX public dlux;

    // ========== Identity ==========
    DIDRegistry public didRegistry;

    // ========== Treasury ==========
    FeeGov public feeGov;
    ValidatorVault public validatorVault;

    // ========== DeFi ==========
    Markets public markets;

    // Constants (same as DeployMultiNetwork)
    uint256 constant INITIAL_LUX = 10_000 ether;
    uint256 constant INITIAL_ETH = 100 ether;
    uint256 constant INITIAL_BTC = 10e8;
    uint256 constant INITIAL_USDC = 1_000_000e6;

    function run() external {
        console.log("=== Deploying 13 Missing Subnet Contracts ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        // Get deployer from private key or mnemonic
        try vm.envUint("LUX_PRIVATE_KEY") returns (uint256 pk) {
            deployerKey = pk;
        } catch {
            string memory mnemonic = vm.envString("LUX_MNEMONIC");
            require(bytes(mnemonic).length > 0, "LUX_PRIVATE_KEY or LUX_MNEMONIC required");
            deployerKey = vm.deriveKey(mnemonic, 0);
        }
        deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);

        // Fund deployer in simulation (ignored during broadcast)
        vm.deal(deployer, 3_000_000_000_000 ether);

        console.log("Balance:", deployer.balance / 1e18, "LUX");
        console.log("");

        vm.startBroadcast(deployerKey);

        // Phase 1: Core Tokens (WLUX, LETH, LBTC, LUSDC)
        _deployPhase1CoreTokens();

        // Phase 2: Governance (Timelock, vLUX, GaugeController, Karma, DLUX)
        _deployPhase2Governance();

        // Phase 3: Identity (DIDRegistry)
        _deployPhase3Identity();

        // Phase 4: Treasury (FeeGov, ValidatorVault)
        _deployPhase4Treasury();

        // Phase 5: DeFi (Markets)
        _deployPhase5DeFi();

        vm.stopBroadcast();

        _printSummary();
    }

    function _deployPhase1CoreTokens() internal {
        console.log("--- Phase 1: Core Tokens ---");

        wlux = new WLUX();
        console.log("WLUX:", address(wlux));

        // Wrap some LUX
        wlux.deposit{value: INITIAL_LUX}();
        console.log("Wrapped", INITIAL_LUX / 1e18, "LUX");

        leth = new BridgedETH();
        console.log("LETH:", address(leth));

        lbtc = new BridgedBTC();
        console.log("LBTC:", address(lbtc));

        lusdc = new BridgedUSDC();
        console.log("LUSDC:", address(lusdc));

        // Mint bridged tokens
        leth.mint(deployer, INITIAL_ETH);
        lbtc.mint(deployer, INITIAL_BTC);
        lusdc.mint(deployer, INITIAL_USDC);
        console.log("Minted bridged tokens");
        console.log("");
    }

    function _deployPhase2Governance() internal {
        console.log("--- Phase 2: Governance ---");

        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new Timelock(1 days, proposers, executors, deployer);
        console.log("Timelock:", address(timelock));

        voteLux = new vLUX(address(wlux));
        console.log("vLUX:", address(voteLux));

        gaugeController = new GaugeController(address(voteLux));
        console.log("GaugeController:", address(gaugeController));

        karma = new Karma(deployer);
        console.log("Karma:", address(karma));

        dlux = new DLUX(address(wlux), deployer, deployer);
        console.log("DLUX:", address(dlux));

        console.log("");
    }

    function _deployPhase3Identity() internal {
        console.log("--- Phase 3: Identity ---");

        didRegistry = new DIDRegistry(deployer, "lux", true);
        console.log("DIDRegistry:", address(didRegistry));
        console.log("");
    }

    function _deployPhase4Treasury() internal {
        console.log("--- Phase 4: Treasury ---");

        feeGov = new FeeGov(30, 10, 500, deployer);
        console.log("FeeGov:", address(feeGov));

        validatorVault = new ValidatorVault(address(wlux));
        console.log("ValidatorVault:", address(validatorVault));
        console.log("");
    }

    function _deployPhase5DeFi() internal {
        console.log("--- Phase 5: DeFi ---");

        markets = new Markets(deployer);
        console.log("Markets:", address(markets));
        console.log("");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("           SUBNET MISSING CONTRACTS DEPLOYMENT COMPLETE");
        console.log("================================================================================");
        console.log("");
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("CORE TOKENS (4):");
        console.log("  WLUX:      ", address(wlux));
        console.log("  LETH:      ", address(leth));
        console.log("  LBTC:      ", address(lbtc));
        console.log("  LUSDC:     ", address(lusdc));
        console.log("");
        console.log("GOVERNANCE (5):");
        console.log("  Timelock:  ", address(timelock));
        console.log("  vLUX:      ", address(voteLux));
        console.log("  Gauge:     ", address(gaugeController));
        console.log("  Karma:     ", address(karma));
        console.log("  DLUX:      ", address(dlux));
        console.log("");
        console.log("IDENTITY (1):");
        console.log("  DIDRegistry:", address(didRegistry));
        console.log("");
        console.log("TREASURY (2):");
        console.log("  FeeGov:       ", address(feeGov));
        console.log("  ValidatorVault:", address(validatorVault));
        console.log("");
        console.log("DEFI (1):");
        console.log("  Markets: ", address(markets));
        console.log("");
        console.log("ALREADY DEPLOYED (7 - not touched):");
        console.log("  StakedLUX:        0xAb95c8B59f68cE922F2f334DFC8bb8f5B0525326");
        console.log("  AMMV2Factory:     0x84CF0A13db1BE8E1f0676405CfcBC8b09692fd1C");
        console.log("  AMMV2Router:      0x2382F7A49Fa48E1f91bEc466C32E1d7f13Ec8206");
        console.log("  LinearCurve:      0xD13Ab81F02449b1630EcD940bE5fB9cD367225b4");
        console.log("  ExponentialCurve: 0xBc92f4e290f8Ad03f5348F81A27Fb2AF3B37ec47");
        console.log("  LSSVMPairFactory: 0xB43dB9af0c5CACB99f783E30398ee0AEE6744212");
        console.log("  Perp:             0xD984fEd38C98c1eAB66E577FD1dDC8dcD88Ea799");
        console.log("");
        console.log("TOTAL: 13 new + 7 existing = 20/20 contracts");
        console.log("================================================================================");
    }
}
