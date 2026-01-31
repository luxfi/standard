// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Treasury
import {FeeGov} from "../contracts/treasury/FeeGov.sol";
import {Vault as TreasuryVault} from "../contracts/treasury/Vault.sol";
import {Router as TreasuryRouter} from "../contracts/treasury/Router.sol";
import {ValidatorVault} from "../contracts/treasury/ValidatorVault.sol";

// Safe (Gnosis Safe for Treasury Management)
import {Safe} from "@safe-global/safe-smart-account/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/proxies/SafeProxy.sol";

// LSSVM (NFT AMM)
import {LSSVMPairFactory} from "../contracts/lssvm/LSSVMPairFactory.sol";
import {LinearCurve} from "../contracts/lssvm/LinearCurve.sol";
import {ExponentialCurve} from "../contracts/lssvm/ExponentialCurve.sol";
import {LSSVMRouter} from "../contracts/lssvm/LSSVMRouter.sol";

// Markets (Lending)
import {Markets} from "../contracts/markets/Markets.sol";

// Perps
import {Perp} from "../contracts/perps/Perp.sol";

// Additional Governance
import {VotingLUX} from "../contracts/governance/VotingLUX.sol";
import {Strategy} from "../contracts/governance/Strategy.sol";

// DeFi Suite
import {StableSwap} from "../contracts/amm/StableSwap.sol";
import {StableSwapFactory} from "../contracts/amm/StableSwapFactory.sol";
import {Options} from "../contracts/options/Options.sol";
import {Streams} from "../contracts/streaming/Streams.sol";
import {IntentRouter} from "../contracts/router/IntentRouter.sol";
import {Cover} from "../contracts/insurance/Cover.sol";

// FHE Contracts
import {ConfidentialERC20} from "../contracts/fhe/tokens/ConfidentialERC20.sol";
import {ConfidentialGovernorAlpha} from "../contracts/fhe/governance/ConfidentialGovernorAlpha.sol";
import {ConfidentialVLUX} from "../contracts/fhe/governance/ConfidentialVLUX.sol";

// Prediction Markets
import {Oracle as PredictionOracle} from "../contracts/prediction/Oracle.sol";
import {Claims} from "../contracts/prediction/claims/Claims.sol";
import {Resolver} from "../contracts/prediction/Resolver.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployRemaining
 * @notice Deploys remaining phases (9-12) plus full governance and DeFi suite
 *
 * Already deployed on devnet:
 * - WLUX: 0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec
 * - DLUX: 0x316520ca05eaC5d2418F562a116091F1b22Bf6e0
 * - DLUXMinter: 0xcd7ee976df9C8a2709a14bda8463af43e6097A56
 * - Timelock: 0x80f3bd0Bdf7861487dDDA61bc651243ecB8B5072
 * - AMM Factory: 0x0570b2c59976E87D37d3a9915750BFf131d295D6
 * - StakedLUX: 0x191067f88d61f9506555E88CEab9CF71deeD61A9
 * - Karma: 0x97c265001EB088E1dE2F77A13a62B708014c9e68
 * - KarmaMinter: 0x1fe145582c7D5683C7C69c0a2BCe0e3ffe901160
 * - vLUX: 0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a
 * - GaugeController: 0x26328AC03d07BD9A7Caaafbde39F9b56B5449240
 * - VotesToken: 0xE77E1cB5E303ed0EcB10d0d13914AaA2ED9B3b8C
 * - BridgedUSDC: 0x7fC4f8a926E47Fa3587C0d7658C00E7489e67916
 */
contract DeployRemaining is Script {
    // Already deployed addresses
    address constant WLUX = 0xc65ea8882020Af7CDa7854d590C6Fcd34BF364ec;
    address constant DLUX = 0x316520ca05eaC5d2418F562a116091F1b22Bf6e0;
    address constant DLUX_MINTER = 0xcd7ee976df9C8a2709a14bda8463af43e6097A56;
    address constant TIMELOCK = 0x80f3bd0Bdf7861487dDDA61bc651243ecB8B5072;
    address constant AMM_FACTORY = 0x0570b2c59976E87D37d3a9915750BFf131d295D6;
    address constant STAKED_LUX = 0x191067f88d61f9506555E88CEab9CF71deeD61A9;
    address constant KARMA = 0x97c265001EB088E1dE2F77A13a62B708014c9e68;
    address constant VLUX = 0x91954cf6866d557C5CA1D2f384D204bcE9DFfd5a;
    address constant GAUGE_CONTROLLER = 0x26328AC03d07BD9A7Caaafbde39F9b56B5449240;
    address constant VOTES_TOKEN = 0xE77E1cB5E303ed0EcB10d0d13914AaA2ED9B3b8C;
    address constant BRIDGED_USDC = 0x7fC4f8a926E47Fa3587C0d7658C00E7489e67916;
    address constant BRIDGED_DAI = 0xC64BD67b39765127ae5DBdd750Fb6a9f62c3269f;
    address constant BRIDGED_USDT = 0x51c3408B9A6a0B2446CCB78c72C846CEB76201FA;

    // Treasury
    Safe public safeImpl;
    SafeProxyFactory public safeProxyFactory;
    address public daoTreasury;
    address public protocolVault;
    address public aiTreasury;
    address public zooTreasury;
    ValidatorVault public validatorVault;
    FeeGov public feeGov;
    TreasuryVault public treasuryVault;
    TreasuryRouter public treasuryRouter;

    // LSSVM
    LinearCurve public linearCurve;
    ExponentialCurve public exponentialCurve;
    LSSVMPairFactory public lssvmFactory;
    LSSVMRouter public lssvmRouter;

    // Core DeFi
    Markets public markets;
    Perp public perp;

    // Advanced Governance
    VotingLUX public votingLux;
    Strategy public strategy;

    // DeFi Suite
    StableSwapFactory public stableSwapFactory;
    Options public options;
    Streams public streams;
    IntentRouter public intentRouter;
    Cover public cover;

    // FHE
    ConfidentialERC20 public confidentialToken;
    ConfidentialGovernorAlpha public confidentialGovernor;
    ConfidentialVLUX public confidentialVLUX;

    // Prediction
    PredictionOracle public predictionOracle;
    Claims public claims;
    Resolver public resolver;

    function run() public {
        string memory mnemonic = vm.envString("LUX_MNEMONIC");
        uint256 deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==============================================");
        console.log("  DEPLOYING FULL REMAINING STACK");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 9: Treasury
        _deployTreasury(deployer);

        // Phase 10: LSSVM
        _deployLSSVM(deployer);

        // Phase 11: Markets
        _deployMarkets(deployer);

        // Phase 12: Perps
        _deployPerps(deployer);

        // Phase 13: Advanced Governance
        _deployAdvancedGovernance(deployer);

        // Phase 14: DeFi Suite
        _deployDeFiSuite(deployer);

        // Phase 15: FHE Governance
        _deployFHE(deployer);

        // Phase 16: Prediction Markets
        _deployPrediction(deployer);

        vm.stopBroadcast();

        _printSummary();
    }

    function _deployTreasury(address deployer) internal {
        console.log("--- Phase 9: Treasury ---");

        // Deploy Safe implementation and factory
        safeImpl = new Safe();
        console.log("Safe impl:", address(safeImpl));

        safeProxyFactory = new SafeProxyFactory();
        console.log("SafeProxyFactory:", address(safeProxyFactory));

        // Create treasury safes (1-of-1 for testing)
        address[] memory owners = new address[](1);
        owners[0] = deployer;

        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,           // owners
            1,                // threshold
            address(0),       // to (no delegate call)
            "",               // data
            address(0),       // fallbackHandler
            address(0),       // paymentToken
            0,                // payment
            payable(address(0)) // paymentReceiver
        );

        // DAO Treasury
        SafeProxy daoProxy = safeProxyFactory.createProxyWithNonce(address(safeImpl), initializer, 1);
        daoTreasury = address(daoProxy);
        console.log("DAO Treasury Safe:", daoTreasury);

        // Protocol Vault
        SafeProxy protocolProxy = safeProxyFactory.createProxyWithNonce(address(safeImpl), initializer, 2);
        protocolVault = address(protocolProxy);
        console.log("Protocol Vault Safe:", protocolVault);

        // AI Treasury
        SafeProxy aiProxy = safeProxyFactory.createProxyWithNonce(address(safeImpl), initializer, 3);
        aiTreasury = address(aiProxy);
        console.log("AI Treasury Safe:", aiTreasury);

        // ZOO Treasury
        SafeProxy zooProxy = safeProxyFactory.createProxyWithNonce(address(safeImpl), initializer, 4);
        zooTreasury = address(zooProxy);
        console.log("ZOO Treasury Safe:", zooTreasury);

        // Deploy ValidatorVault
        validatorVault = new ValidatorVault(WLUX, deployer);
        console.log("ValidatorVault:", address(validatorVault));

        // Deploy FeeGov (fee governance)
        feeGov = new FeeGov(deployer);
        feeGov.setRate(30);    // 0.3%
        feeGov.setFloor(10);   // 0.1%
        feeGov.setCap(500);    // 5%
        console.log("FeeGov:", address(feeGov));

        // Deploy TreasuryVault
        treasuryVault = new TreasuryVault(WLUX, deployer);
        console.log("TreasuryVault:", address(treasuryVault));

        // Deploy TreasuryRouter with weights
        address[] memory recipients = new address[](3);
        recipients[0] = STAKED_LUX;      // stakers
        recipients[1] = daoTreasury;     // DAO
        recipients[2] = address(validatorVault); // validators

        uint256[] memory weights = new uint256[](3);
        weights[0] = 7000;  // 70% to stakers
        weights[1] = 2000;  // 20% to DAO
        weights[2] = 1000;  // 10% to validators

        treasuryRouter = new TreasuryRouter(address(treasuryVault), recipients, weights, deployer);
        console.log("TreasuryRouter:", address(treasuryRouter));

        // Wire TreasuryVault to TreasuryRouter
        treasuryVault.setRouter(address(treasuryRouter));

        console.log("");
    }

    function _deployLSSVM(address deployer) internal {
        console.log("--- Phase 10: LSSVM (NFT AMM) ---");

        linearCurve = new LinearCurve();
        console.log("LinearCurve:", address(linearCurve));

        exponentialCurve = new ExponentialCurve();
        console.log("ExponentialCurve:", address(exponentialCurve));

        lssvmFactory = new LSSVMPairFactory(deployer, deployer);
        console.log("LSSVMPairFactory:", address(lssvmFactory));

        lssvmFactory.setBondingCurveAllowed(address(linearCurve), true);
        lssvmFactory.setBondingCurveAllowed(address(exponentialCurve), true);

        lssvmRouter = new LSSVMRouter(address(lssvmFactory));
        console.log("LSSVMRouter:", address(lssvmRouter));

        console.log("");
    }

    function _deployMarkets(address deployer) internal {
        console.log("--- Phase 11: Markets (Lending) ---");

        markets = new Markets(deployer);
        console.log("Markets:", address(markets));

        console.log("");
    }

    function _deployPerps(address deployer) internal {
        console.log("--- Phase 12: Perps ---");

        perp = new Perp(deployer);
        console.log("Perp:", address(perp));

        console.log("");
    }

    function _deployAdvancedGovernance(address deployer) internal {
        console.log("--- Phase 13: Advanced Governance ---");

        // VotingLUX aggregates xLUX + DLUX voting power
        votingLux = new VotingLUX(STAKED_LUX, DLUX);
        console.log("VotingLUX:", address(votingLux));

        // Strategy for gauge-weighted voting
        strategy = new Strategy(deployer);
        console.log("Strategy:", address(strategy));

        console.log("");
    }

    function _deployDeFiSuite(address deployer) internal {
        console.log("--- Phase 14: DeFi Suite ---");

        // StableSwap Factory (Curve-style)
        stableSwapFactory = new StableSwapFactory(deployer);
        console.log("StableSwapFactory:", address(stableSwapFactory));

        // Create a 3pool (USDC/USDT/DAI)
        address[] memory stablecoins = new address[](3);
        stablecoins[0] = BRIDGED_USDC;
        stablecoins[1] = BRIDGED_USDT;
        stablecoins[2] = BRIDGED_DAI;

        address stablePool = stableSwapFactory.createPool(
            "Lux 3Pool",
            "LUX3CRV",
            stablecoins,
            200,  // A = 200 (amplification)
            4,    // 0.04% fee
            0     // 0% admin fee
        );
        console.log("  3Pool (USDC/USDT/DAI):", stablePool);

        // Options Protocol
        options = new Options(deployer);
        console.log("Options:", address(options));

        // Streaming Payments
        streams = new Streams();
        console.log("Streams:", address(streams));

        // Intent Router (Limit Orders, RFQ)
        intentRouter = new IntentRouter(deployer);
        console.log("IntentRouter:", address(intentRouter));

        // Insurance/Cover
        cover = new Cover(deployer);
        console.log("Cover:", address(cover));

        console.log("");
    }

    function _deployFHE(address deployer) internal {
        console.log("--- Phase 15: FHE Governance ---");

        // Confidential ERC20 (encrypted balances)
        confidentialToken = new ConfidentialERC20("Confidential LUX", "cLUX", deployer);
        console.log("ConfidentialERC20 (cLUX):", address(confidentialToken));

        // Confidential Governor (private voting)
        confidentialGovernor = new ConfidentialGovernorAlpha(
            address(confidentialToken),
            TIMELOCK,
            deployer
        );
        console.log("ConfidentialGovernorAlpha:", address(confidentialGovernor));

        // Confidential vLUX (private voting power)
        confidentialVLUX = new ConfidentialVLUX(
            STAKED_LUX,
            DLUX,
            KARMA
        );
        console.log("ConfidentialVLUX:", address(confidentialVLUX));

        console.log("");
    }

    function _deployPrediction(address deployer) internal {
        console.log("--- Phase 16: Prediction Markets ---");

        // Prediction Oracle (optimistic oracle)
        predictionOracle = new PredictionOracle(
            BRIDGED_USDC,  // default bond token
            deployer
        );
        console.log("PredictionOracle:", address(predictionOracle));

        // Claims (ERC-1155 conditional tokens)
        claims = new Claims();
        console.log("Claims:", address(claims));

        // Resolver (binds oracle to claims)
        resolver = new Resolver(
            address(predictionOracle),
            address(claims)
        );
        console.log("Resolver:", address(resolver));

        console.log("");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("                    FULL STACK DEPLOYMENT COMPLETE");
        console.log("================================================================================");
        console.log("");
        console.log("TREASURY (Phase 9):");
        console.log("  DAO Treasury:     ", daoTreasury);
        console.log("  ValidatorVault:   ", address(validatorVault));
        console.log("  FeeGov:           ", address(feeGov));
        console.log("  TreasuryVault:    ", address(treasuryVault));
        console.log("  TreasuryRouter:   ", address(treasuryRouter));
        console.log("");
        console.log("NFT AMM (Phase 10):");
        console.log("  LSSVMPairFactory: ", address(lssvmFactory));
        console.log("  LSSVMRouter:      ", address(lssvmRouter));
        console.log("");
        console.log("LENDING & PERPS (Phases 11-12):");
        console.log("  Markets:          ", address(markets));
        console.log("  Perp:             ", address(perp));
        console.log("");
        console.log("ADVANCED GOVERNANCE (Phase 13):");
        console.log("  VotingLUX:        ", address(votingLux));
        console.log("  Strategy:         ", address(strategy));
        console.log("");
        console.log("DEFI SUITE (Phase 14):");
        console.log("  StableSwapFactory:", address(stableSwapFactory));
        console.log("  Options:          ", address(options));
        console.log("  Streams:          ", address(streams));
        console.log("  IntentRouter:     ", address(intentRouter));
        console.log("  Cover:            ", address(cover));
        console.log("");
        console.log("FHE GOVERNANCE (Phase 15):");
        console.log("  ConfidentialERC20:", address(confidentialToken));
        console.log("  ConfidentialGov:  ", address(confidentialGovernor));
        console.log("  ConfidentialVLUX: ", address(confidentialVLUX));
        console.log("");
        console.log("PREDICTION MARKETS (Phase 16):");
        console.log("  PredictionOracle: ", address(predictionOracle));
        console.log("  Claims:           ", address(claims));
        console.log("  Resolver:         ", address(resolver));
        console.log("");
        console.log("================================================================================");
        console.log("                         ALL 16 PHASES DEPLOYED");
        console.log("================================================================================");
    }
}
