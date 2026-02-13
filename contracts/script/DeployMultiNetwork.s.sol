// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Core native token
import {WLUX} from "@luxfi/contracts/tokens/WLUX.sol";

// Bridged Collateral Tokens
import {BridgedETH} from "@luxfi/contracts/bridge/collateral/ETH.sol";
import {BridgedBTC} from "@luxfi/contracts/bridge/collateral/BTC.sol";
import {BridgedUSDC} from "@luxfi/contracts/bridge/collateral/USDC.sol";

// Staking
import {sLUX as StakedLUX} from "@luxfi/contracts/staking/sLUX.sol";

// AMM
import {AMMV2Factory} from "@luxfi/contracts/amm/AMMV2Factory.sol";
import {AMMV2Router} from "@luxfi/contracts/amm/AMMV2Router.sol";

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

// LSSVM (NFT AMM)
import {LSSVMPairFactory} from "@luxfi/contracts/lssvm/LSSVMPairFactory.sol";
import {LinearCurve} from "@luxfi/contracts/lssvm/LinearCurve.sol";
import {ExponentialCurve} from "@luxfi/contracts/lssvm/ExponentialCurve.sol";

// Markets (Lending)
import {Markets} from "@luxfi/contracts/markets/Markets.sol";

// Perps
import {Perp} from "@luxfi/contracts/perps/Perp.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployMultiNetwork
 * @notice Deploy Lux standard contracts to multiple networks
 * @dev Simplified deployment for Mainnet, Testnet, and Devnet
 *
 * Networks (all use chain-id 1337 in dev mode):
 * - Mainnet: http://209.38.175.130:9630/ext/bc/C/rpc
 * - Testnet: http://24.199.70.106:9640/ext/bc/C/rpc
 * - Devnet: http://24.199.74.128:9650/ext/bc/C/rpc
 *
 * Funded account (from "light energy" mnemonic):
 * - Primary: 0x35D64Ff3f618f7a17DF34DCb21be375A4686a8de
 *
 * Usage:
 *   export LUX_MNEMONIC="light light light light light light light light light light light energy"
 *
 *   # Deploy to mainnet
 *   forge script contracts/script/DeployMultiNetwork.s.sol --rpc-url http://209.38.175.130:9630/ext/bc/C/rpc --broadcast -vvv
 *
 *   # Deploy to testnet
 *   forge script contracts/script/DeployMultiNetwork.s.sol --rpc-url http://24.199.70.106:9640/ext/bc/C/rpc --broadcast -vvv
 *
 *   # Deploy to devnet
 *   forge script contracts/script/DeployMultiNetwork.s.sol --rpc-url http://24.199.74.128:9650/ext/bc/C/rpc --broadcast -vvv
 */
contract DeployMultiNetwork is Script {
    // Deployer
    address public deployer;
    uint256 public deployerKey;

    // ========== Core Tokens ==========
    WLUX public wlux;
    BridgedETH public leth;
    BridgedBTC public lbtc;
    BridgedUSDC public lusdc;

    // ========== Staking ==========
    StakedLUX public stakedLux;

    // ========== AMM ==========
    AMMV2Factory public factory;
    AMMV2Router public router;

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

    // ========== LSSVM ==========
    LinearCurve public linearCurve;
    ExponentialCurve public exponentialCurve;
    LSSVMPairFactory public lssvmFactory;

    // ========== DeFi ==========
    Markets public markets;
    Perp public perp;

    // Constants
    uint256 constant INITIAL_LUX = 10_000 ether;
    uint256 constant INITIAL_ETH = 100 ether;
    uint256 constant INITIAL_BTC = 10e8;
    uint256 constant INITIAL_USDC = 1_000_000e6;

    function run() external {
        console.log("=== Deploying Lux Standard Contracts ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        // Get deployer from mnemonic
        string memory mnemonic = vm.envString("LUX_MNEMONIC");
        require(bytes(mnemonic).length > 0, "LUX_MNEMONIC required");

        deployerKey = vm.deriveKey(mnemonic, 0);
        deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);

        // Fund deployer in simulation (ignored during broadcast)
        vm.deal(deployer, 3_000_000_000_000 ether);

        console.log("Balance:", deployer.balance / 1e18, "LUX");
        console.log("");

        vm.startBroadcast(deployerKey);

        // Phase 1: Core Tokens
        _deployPhase1CoreTokens();

        // Phase 2: Staking
        _deployPhase2Staking();

        // Phase 3: AMM
        _deployPhase3AMM();

        // Phase 4: LP Pools
        _deployPhase4LPPools();

        // Phase 5: Governance
        _deployPhase5Governance();

        // Phase 6: Identity
        _deployPhase6Identity();

        // Phase 7: Treasury
        _deployPhase7Treasury();

        // Phase 8: LSSVM
        _deployPhase8LSSVM();

        // Phase 9: DeFi
        _deployPhase9DeFi();

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

    function _deployPhase2Staking() internal {
        console.log("--- Phase 2: Staking ---");

        stakedLux = new StakedLUX(address(wlux));
        console.log("StakedLUX:", address(stakedLux));

        // Stake some LUX
        uint256 stakeAmount = 1000 ether;
        wlux.approve(address(stakedLux), stakeAmount);
        stakedLux.stake(stakeAmount);
        console.log("Staked", stakeAmount / 1e18, "LUX");
        console.log("");
    }

    function _deployPhase3AMM() internal {
        console.log("--- Phase 3: AMM ---");

        factory = new AMMV2Factory(deployer);
        console.log("AMMV2Factory:", address(factory));

        router = new AMMV2Router(address(factory), address(wlux));
        console.log("AMMV2Router:", address(router));
        console.log("");
    }

    function _deployPhase4LPPools() internal {
        console.log("--- Phase 4: LP Pools ---");

        // WLUX/LETH
        _createPool(address(wlux), address(leth), 1000 ether, 10 ether);
        console.log("WLUX/LETH pool created");

        // WLUX/LBTC
        _createPool(address(wlux), address(lbtc), 1000 ether, 1e8);
        console.log("WLUX/LBTC pool created");

        // WLUX/LUSDC
        _createPool(address(wlux), address(lusdc), 1000 ether, 5000e6);
        console.log("WLUX/LUSDC pool created");

        console.log("");
    }

    function _deployPhase5Governance() internal {
        console.log("--- Phase 5: Governance ---");

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

    function _deployPhase6Identity() internal {
        console.log("--- Phase 6: Identity ---");

        didRegistry = new DIDRegistry(deployer, "lux", true);
        console.log("DIDRegistry:", address(didRegistry));
        console.log("");
    }

    function _deployPhase7Treasury() internal {
        console.log("--- Phase 7: Treasury ---");

        feeGov = new FeeGov(30, 10, 500, deployer);
        console.log("FeeGov:", address(feeGov));

        validatorVault = new ValidatorVault(address(wlux));
        console.log("ValidatorVault:", address(validatorVault));
        console.log("");
    }

    function _deployPhase8LSSVM() internal {
        console.log("--- Phase 8: LSSVM (NFT AMM) ---");

        linearCurve = new LinearCurve();
        console.log("LinearCurve:", address(linearCurve));

        exponentialCurve = new ExponentialCurve();
        console.log("ExponentialCurve:", address(exponentialCurve));

        lssvmFactory = new LSSVMPairFactory(deployer);
        console.log("LSSVMPairFactory:", address(lssvmFactory));

        lssvmFactory.setBondingCurveAllowed(address(linearCurve), true);
        lssvmFactory.setBondingCurveAllowed(address(exponentialCurve), true);
        console.log("");
    }

    function _deployPhase9DeFi() internal {
        console.log("--- Phase 9: DeFi ---");

        markets = new Markets(deployer);
        console.log("Markets:", address(markets));

        perp = new Perp(address(wlux), deployer, deployer);
        console.log("Perp:", address(perp));
        console.log("");
    }

    function _createPool(address tokenA, address tokenB, uint256 amountA, uint256 amountB) internal {
        IERC20(tokenA).approve(address(router), amountA);
        IERC20(tokenB).approve(address(router), amountB);

        router.addLiquidity(
            tokenA, tokenB,
            amountA, amountB,
            0, 0,
            deployer,
            block.timestamp + 1 hours
        );
    }

    function _printSummary() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("                    DEPLOYMENT COMPLETE");
        console.log("================================================================================");
        console.log("");
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("CORE TOKENS:");
        console.log("  WLUX:      ", address(wlux));
        console.log("  LETH:      ", address(leth));
        console.log("  LBTC:      ", address(lbtc));
        console.log("  LUSDC:     ", address(lusdc));
        console.log("");
        console.log("STAKING:");
        console.log("  StakedLUX: ", address(stakedLux));
        console.log("");
        console.log("AMM:");
        console.log("  Factory:   ", address(factory));
        console.log("  Router:    ", address(router));
        console.log("");
        console.log("GOVERNANCE:");
        console.log("  Timelock:  ", address(timelock));
        console.log("  vLUX:      ", address(voteLux));
        console.log("  Gauge:     ", address(gaugeController));
        console.log("  Karma:     ", address(karma));
        console.log("  DLUX:      ", address(dlux));
        console.log("");
        console.log("IDENTITY:");
        console.log("  DIDRegistry:", address(didRegistry));
        console.log("");
        console.log("TREASURY:");
        console.log("  FeeGov:       ", address(feeGov));
        console.log("  ValidatorVault:", address(validatorVault));
        console.log("");
        console.log("LSSVM:");
        console.log("  LinearCurve:     ", address(linearCurve));
        console.log("  ExponentialCurve:", address(exponentialCurve));
        console.log("  LSSVMFactory:    ", address(lssvmFactory));
        console.log("");
        console.log("DEFI:");
        console.log("  Markets: ", address(markets));
        console.log("  Perp:    ", address(perp));
        console.log("");
        console.log("================================================================================");
    }
}
