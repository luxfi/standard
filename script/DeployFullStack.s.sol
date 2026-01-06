// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";

// Core native token
import {WLUX} from "../contracts/tokens/WLUX.sol";

// Bridged Collateral Tokens (1:1 from source chains, minted by Teleporter)
import {BridgedETH} from "../contracts/bridge/collateral/ETH.sol";
import {BridgedBTC} from "../contracts/bridge/collateral/BTC.sol";
import {BridgedUSDC} from "../contracts/bridge/collateral/USDC.sol";
import {BridgedUSDT} from "../contracts/bridge/collateral/USDT.sol";
import {BridgedDAI} from "../contracts/bridge/collateral/DAI.sol";

// Liquid Protocol
import {LiquidLUX} from "../contracts/liquid/LiquidLUX.sol";

// Staking
import {sLUX as StakedLUX} from "../contracts/staking/sLUX.sol";

// AI Token (GPU compute mining)
import {AINative} from "../contracts/tokens/AI.sol";

// AMM
import {AMMV2Factory} from "../contracts/amm/AMMV2Factory.sol";
import {AMMV2Router} from "../contracts/amm/AMMV2Router.sol";
import {AMMV2Pair} from "../contracts/amm/AMMV2Pair.sol";

// Teleport (cross-chain vaults)
import {LiquidVault} from "../contracts/liquid/teleport/LiquidVault.sol";

// Identity/DID
import {DIDRegistry} from "../contracts/identity/DIDRegistry.sol";

// Governance
import {VotesToken} from "../contracts/governance/VotesToken.sol";
import {Timelock} from "../contracts/governance/Timelock.sol";
import {Governor} from "../contracts/governance/Governor.sol";
import {vLUX} from "../contracts/governance/vLUX.sol";
import {GaugeController} from "../contracts/governance/GaugeController.sol";
import {Karma} from "../contracts/governance/Karma.sol";
import {KarmaMinter} from "../contracts/governance/KarmaMinter.sol";
import {DLUX} from "../contracts/governance/DLUX.sol";
import {DLUXMinter} from "../contracts/governance/DLUXMinter.sol";

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

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// IVotes and TimelockController not needed - Governor skipped due to Strategy complexity

/**
 * @title DeployFullStack
 * @notice Deploys complete Lux DeFi stack for testing
 *
 * TOKEN MODEL:
 *
 * BRIDGED TOKENS (L* prefix on Lux, Z* on Zoo):
 * - LETH, LBTC, LUSD, etc. - minted by bridge contracts
 * - See contracts/bridge/lux/ for all bridge tokens
 *
 * LIQUID PROTOCOL:
 * - LiquidLUX (xLUX): Master yield vault - receives ALL protocol fees
 * - vLUX: Voting power = xLUX + DLUX
 *
 * LP POOLS:
 * - WLUX/xLUX, WLUX/LUSD, WLUX/AI
 *
 * FULL STACK DEPLOYMENT:
 * ┌──────────────────────────────────────────────────────────────────┐
 * │  Phase 1: Bridged Tokens      - ETH, BTC, USDC collateral       │
 * │  Phase 2: LiquidLUX           - Master yield vault (xLUX)       │
 * │  Phase 3: Native & Staking    - WLUX, StakedLUX, AI             │
 * │  Phase 4: AMM                 - Factory, Router                  │
 * │  Phase 5: LP Pools            - Core trading pairs              │
 * │  Phase 6: Teleport Vaults     - Cross-chain yield               │
 * │  Phase 7: Identity/DID        - DIDRegistry                      │
 * │  Phase 8: Governance          - VotesToken, Timelock, vLUX      │
 * │  Phase 9: Treasury            - FeeSplitter, ValidatorVault     │
 * │  Phase 10: LSSVM              - NFT AMM                          │
 * │  Phase 11: Markets            - Morpho-style lending             │
 * │  Phase 12: Perps              - Perpetual futures                │
 * └──────────────────────────────────────────────────────────────────┘
 */
contract DeployFullStack is Script {
    // Deployer
    address public deployer;
    uint256 public deployerKey;

    // ========== Phase 1: Bridged Collateral ==========
    BridgedETH public eth;
    BridgedBTC public btc;
    BridgedUSDC public usdc;
    BridgedUSDT public usdt;
    BridgedDAI public dai;

    // ========== Phase 2: LiquidLUX ==========
    LiquidLUX public liquidLux;

    // ========== Phase 3: Native & Staking ==========
    WLUX public wlux;
    StakedLUX public stakedLux;
    AINative public ai;

    // ========== Phase 4: AMM ==========
    AMMV2Factory public factory;
    AMMV2Router public router;

    // ========== Phase 6: Teleport Vaults ==========
    LiquidVault public liquidVault;

    // ========== Phase 7: Identity/DID ==========
    DIDRegistry public didRegistry;

    // ========== Phase 8: Governance ==========
    VotesToken public govToken;
    Timelock public timelock;
    // Governor skipped - requires Strategy with two-phase init
    vLUX public voteLux;
    GaugeController public gaugeController;
    Karma public karma;
    KarmaMinter public karmaMinter;
    DLUX public dlux;
    DLUXMinter public dluxMinter;

    // ========== Phase 9: Treasury ==========
    FeeGov public feeGov;            // C-Chain governs all chain fees
    TreasuryVault public treasuryVault; // Receives fees via Warp
    TreasuryRouter public treasuryRouter; // Distributes to recipients
    ValidatorVault public validatorVault; // Validator rewards distribution
    Safe public safeImpl;
    SafeProxyFactory public safeFactory;
    address public daoTreasury;      // Safe for DAO funds
    address public protocolVault;    // Safe for protocol fees (→ sLUX)
    address public aiTreasury;       // Safe for AI mining rewards
    address public zooTreasury;      // Safe for ZOO ecosystem

    // ========== Phase 10: LSSVM ==========
    LinearCurve public linearCurve;
    ExponentialCurve public exponentialCurve;
    LSSVMPairFactory public lssvmFactory;
    LSSVMRouter public lssvmRouter;

    // ========== Phase 11: Markets ==========
    Markets public markets;

    // ========== Phase 12: Perps ==========
    Perp public perp;

    // Initial amounts
    uint256 constant INITIAL_LUX = 1_000 ether;
    uint256 constant INITIAL_ETH = 100 ether;
    uint256 constant INITIAL_BTC = 10e8; // 10 BTC (8 decimals)
    uint256 constant INITIAL_STABLES = 100_000e6; // 100k (6 decimals for USDC/USDT)
    uint256 constant INITIAL_DAI = 100_000 ether; // 18 decimals
    uint256 constant GOV_TOKEN_SUPPLY = 100_000_000 ether;
    uint256 constant AI_INITIAL_LIQUIDITY = 100_000_000 ether; // 10% of 1B for LP

    function run() external {
        console.log("=== Deploying Lux Full Stack ===");
        console.log("TOKEN MODEL: Bridged Collateral + Debt Tokens");
        console.log("");

        // Get deployer from environment
        string memory mnemonic = vm.envString("LUX_MNEMONIC");
        require(bytes(mnemonic).length > 0, "LUX_MNEMONIC required");

        deployerKey = vm.deriveKey(mnemonic, 0);
        deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerKey);

        // Deploy WLUX first (nonce 0) for deterministic address 0x5FbDB2315678afecb367f032d93F642f64180aa3
        _deployWLUXFirst();
        _deployPhase1BridgedCollateral();
        _deployPhase2LiquidLUX();
        _deployPhase3NativeAndStaking();
        _deployPhase4AMM();
        _deployPhase5LPPools();
        _deployPhase6TeleportVaults();
        _deployPhase7Identity();
        _deployPhase8Governance();
        _deployPhase9Treasury();
        _deployPhase10LSSVM();
        _deployPhase11Markets();
        _deployPhase12Perps();

        vm.stopBroadcast();

        _printSummary();
    }

    /**
     * @notice Deploy WLUX first to get deterministic address at nonce 0
     * Expected address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
     */
    function _deployWLUXFirst() internal {
        console.log("--- Phase 0: WLUX (Deployed First for Deterministic Address) ---");

        wlux = new WLUX();
        console.log("WLUX:", address(wlux));
        console.log("Expected: 0x5FbDB2315678afecb367f032d93F642f64180aa3");
        console.log("");
    }

    function _deployPhase1BridgedCollateral() internal {
        console.log("--- Phase 1: Bridged Collateral (1:1 from source) ---");
        // Deploy in order: LETH (nonce 1), LBTC (nonce 2), LUSD (nonce 3)
        // Expected addresses:
        //   LETH: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
        //   LBTC: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
        //   LUSD: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9

        eth = new BridgedETH();
        console.log("ETH (bridged):", address(eth));

        btc = new BridgedBTC();
        console.log("BTC (bridged):", address(btc));

        usdc = new BridgedUSDC();
        console.log("USDC (bridged):", address(usdc));

        usdt = new BridgedUSDT();
        console.log("USDT (bridged):", address(usdt));

        dai = new BridgedDAI();
        console.log("DAI (bridged):", address(dai));

        // Mint initial bridged collateral (simulating Teleporter)
        eth.mint(deployer, INITIAL_ETH);
        btc.mint(deployer, INITIAL_BTC);
        usdc.mint(deployer, INITIAL_STABLES);
        usdt.mint(deployer, INITIAL_STABLES);
        dai.mint(deployer, INITIAL_DAI);
        console.log("Minted initial bridged collateral");
        console.log("");
    }

    function _deployPhase2LiquidLUX() internal {
        console.log("--- Phase 2: LiquidLUX (Master Yield Vault) ---");

        // LiquidLUX will be deployed after WLUX in phase 3
        // Placeholder - actual deployment happens in phase 3 after WLUX
        console.log("LiquidLUX deployment deferred to phase 3 (needs WLUX)");
        console.log("");
    }

    function _deployPhase3NativeAndStaking() internal {
        console.log("--- Phase 3: Native Token & Staking ---");

        // WLUX already deployed in _deployWLUXFirst() at nonce 0
        console.log("WLUX (already deployed):", address(wlux));

        // Wrap LUX
        wlux.deposit{value: INITIAL_LUX}();
        console.log("Wrapped", INITIAL_LUX / 1e18, "LUX");

        stakedLux = new StakedLUX(address(wlux));
        console.log("StakedLUX:", address(stakedLux));

        // Stake some LUX
        uint256 stakeAmount = 100 ether;
        wlux.approve(address(stakedLux), stakeAmount);
        stakedLux.stake(stakeAmount);
        console.log("Staked 100 LUX");

        // Deploy AI Token (1B supply, 10% to deployer for liquidity)
        ai = new AINative(deployer);
        console.log("AI (1B supply, 10%% liquidity):", address(ai));
        console.log("  Initial liquidity (100M AI) minted to:", deployer);
        console.log("");
    }

    function _deployPhase4AMM() internal {
        console.log("--- Phase 4: AMM ---");

        factory = new AMMV2Factory(deployer);
        console.log("AMMV2Factory:", address(factory));

        router = new AMMV2Router(address(factory), address(wlux));
        console.log("AMMV2Router:", address(router));
        console.log("");
    }

    function _deployPhase5LPPools() internal {
        console.log("--- Phase 5: LP Pools ---");

        // ===== Core WLUX Pairs =====
        console.log("Creating WLUX pairs...");

        // WLUX/ETH (bridged ETH)
        _createPool(address(wlux), address(eth), 50 ether, 10 ether);
        console.log("  WLUX/ETH pool created");

        // WLUX/BTC (bridged BTC - 8 decimals)
        _createPool(address(wlux), address(btc), 100 ether, 1e7); // 0.1 BTC
        console.log("  WLUX/BTC pool created");

        // WLUX/USDC (bridged USDC - 6 decimals)
        _createPool(address(wlux), address(usdc), 100 ether, 500e6);
        console.log("  WLUX/USDC pool created");

        // WLUX/AI (AI token liquidity - using 50M of the 100M initial allocation)
        _createPool(address(wlux), address(ai), 200 ether, 50_000_000 ether);
        console.log("  WLUX/AI pool created (50M AI liquidity)");

        // ===== Stablecoin pairs =====
        console.log("Creating stablecoin pairs...");

        // USDC/DAI (6 dec / 18 dec)
        _createPool(address(usdc), address(dai), 10_000e6, 10_000 ether);
        console.log("  USDC/DAI pool created");

        // USDC/USDT (6 dec / 6 dec)
        _createPool(address(usdc), address(usdt), 10_000e6, 10_000e6);
        console.log("  USDC/USDT pool created");

        console.log("");
    }

    function _deployPhase6TeleportVaults() internal {
        console.log("--- Phase 6: Teleport Vaults ---");

        // MPC Oracle is deployer for testing (multisig in production)
        liquidVault = new LiquidVault(deployer);
        console.log("LiquidVault:", address(liquidVault));
        console.log("  MPC Oracle (test):", deployer);
        console.log("");
    }

    function _deployPhase7Identity() internal {
        console.log("--- Phase 7: Identity/DID ---");

        didRegistry = new DIDRegistry(deployer, "lux", true);
        console.log("DIDRegistry:", address(didRegistry));
        console.log("");
    }

    function _deployPhase8Governance() internal {
        console.log("--- Phase 8: Governance ---");

        VotesToken.Allocation[] memory allocations = new VotesToken.Allocation[](1);
        allocations[0] = VotesToken.Allocation({
            recipient: deployer,
            amount: GOV_TOKEN_SUPPLY
        });

        govToken = new VotesToken(
            "Lux Governance",
            "gLUX",
            allocations,
            deployer,
            GOV_TOKEN_SUPPLY,
            false
        );
        console.log("VotesToken (gLUX):", address(govToken));

        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new Timelock(1 days, proposers, executors, deployer);
        console.log("Timelock:", address(timelock));

        // NOTE: Governor requires Strategy with complex two-phase init
        // For full governance, deploy separately with:
        // 1. Deploy Strategy impl + proxy
        // 2. Strategy.initialize(votingPeriod, quorum, basis, proposerAdapters, lightAccountFactory)
        // 3. Deploy Governor impl + proxy with Strategy address
        // 4. Strategy.initialize2(governor, votingConfigs)
        console.log("Governor: SKIPPED (requires Strategy with two-phase init)");

        voteLux = new vLUX(address(wlux));
        console.log("vLUX:", address(voteLux));

        gaugeController = new GaugeController(address(voteLux));
        console.log("GaugeController:", address(gaugeController));

        // Deploy Karma (soul-bound reputation)
        karma = new Karma(deployer);
        console.log("Karma (K):", address(karma));

        // Deploy KarmaMinter with DAO control
        // Timelock gets GOVERNOR_ROLE for DAO-controlled mint params
        karmaMinter = new KarmaMinter(address(karma), deployer, address(timelock));
        console.log("KarmaMinter:", address(karmaMinter));

        // Grant ATTESTOR_ROLE to KarmaMinter so it can mint K
        karma.grantRole(karma.ATTESTOR_ROLE(), address(karmaMinter));
        console.log("  KarmaMinter granted ATTESTOR_ROLE on Karma");

        // Deploy DLUX (rebasing governance token)
        // Treasury is deployer initially, updated after Phase 9 deploys DAO Treasury
        dlux = new DLUX(address(wlux), deployer, deployer);
        console.log("DLUX:", address(dlux));

        // Grant GOVERNOR_ROLE to Timelock for DAO control
        dlux.grantRole(dlux.GOVERNOR_ROLE(), address(timelock));
        console.log("  Timelock granted GOVERNOR_ROLE on DLUX");

        // Deploy DLUXMinter with deployer as initial dao for setup
        // After setup in Phase 9, grant GOVERNOR_ROLE to timelock
        dluxMinter = new DLUXMinter(
            address(dlux),
            address(wlux),
            deployer,      // treasury (updated after Phase 9)
            deployer,      // admin
            deployer       // dao (deployer initially for setup, timelock added in Phase 9)
        );
        console.log("DLUXMinter:", address(dluxMinter));

        // Grant MINTER_ROLE to DLUXMinter on DLUX
        dlux.grantRole(dlux.MINTER_ROLE(), address(dluxMinter));
        console.log("  DLUXMinter granted MINTER_ROLE on DLUX");

        console.log("");
    }

    function _deployPhase9Treasury() internal {
        console.log("--- Phase 9: Treasury ---");

        // Deploy Safe infrastructure
        safeImpl = new Safe();
        console.log("Safe impl:", address(safeImpl));

        safeFactory = new SafeProxyFactory();
        console.log("SafeProxyFactory:", address(safeFactory));

        // Deploy 4 Treasury Safes (all start as 1-of-1 with deployer, upgrade later)
        address[] memory owners = new address[](1);
        owners[0] = deployer;

        // DAO Treasury - holds governance funds
        daoTreasury = _deploySafe(owners, 1, "DAO Treasury");

        // Protocol Vault - receives tx fees, distributes to sLUX stakers
        protocolVault = _deploySafe(owners, 1, "Protocol Vault");

        // AI Treasury - holds AI token mining rewards/ecosystem funds
        aiTreasury = _deploySafe(owners, 1, "AI Treasury");

        // ZOO Treasury - holds ZOO ecosystem funds
        zooTreasury = _deploySafe(owners, 1, "ZOO Treasury");

        // Deploy ValidatorVault for P-Chain reward distribution
        validatorVault = new ValidatorVault(address(wlux));
        console.log("ValidatorVault:", address(validatorVault));

        // FeeGov - C-Chain governs all chain fees
        // Initial params: 0.3% rate, 0.1% floor, 5% cap
        feeGov = new FeeGov(30, 10, 500, deployer);
        console.log("FeeGov:", address(feeGov));
        console.log("  Rate: 0.3%%, Floor: 0.1%%, Cap: 5%%");

        // Treasury Vault - receives fees via Warp from all chains
        treasuryVault = new TreasuryVault(address(wlux));
        console.log("TreasuryVault:", address(treasuryVault));

        // Treasury Router - distributes to recipients
        treasuryRouter = new TreasuryRouter(address(wlux), address(treasuryVault), deployer);
        console.log("TreasuryRouter:", address(treasuryRouter));

        // Wire vault to router
        treasuryVault.init(address(treasuryRouter));
        console.log("  TreasuryVault wired to TreasuryRouter");

        // Set up router weights: 70% stakers, 20% DAO, 10% validators
        address[] memory recipients = new address[](3);
        uint256[] memory weights = new uint256[](3);
        recipients[0] = protocolVault;  // Protocol → sLUX stakers
        recipients[1] = daoTreasury;     // DAO treasury
        recipients[2] = address(validatorVault);  // Validators
        weights[0] = 7000;  // 70%
        weights[1] = 2000;  // 20%
        weights[2] = 1000;  // 10%

        treasuryRouter.setBatch(recipients, weights);
        console.log("  Router weights: 70%% stakers, 20%% DAO, 10%% validators");

        // Register all 11 chains in FeeGov
        bytes32[] memory chainIds = new bytes32[](11);
        chainIds[0] = keccak256("P");
        chainIds[1] = keccak256("X");
        chainIds[2] = keccak256("A");
        chainIds[3] = keccak256("B");
        chainIds[4] = keccak256("C");
        chainIds[5] = keccak256("D");
        chainIds[6] = keccak256("T");
        chainIds[7] = keccak256("G");
        chainIds[8] = keccak256("Q");
        chainIds[9] = keccak256("K");
        chainIds[10] = keccak256("Z");

        for (uint256 i = 0; i < chainIds.length; i++) {
            feeGov.add(chainIds[i]);
        }
        console.log("  Registered 11 chains: P, X, A, B, C, D, T, G, Q, K, Z");

        // Update DLUX treasury to DAO Treasury
        dlux.setTreasury(daoTreasury);
        console.log("  DLUX treasury updated to DAO Treasury");

        // Update DLUXMinter treasury to DAO Treasury
        dluxMinter.setTreasury(daoTreasury);
        console.log("  DLUXMinter treasury updated to DAO Treasury");

        // Grant GOVERNOR_ROLE to Timelock for DAO control
        dluxMinter.grantRole(dluxMinter.GOVERNOR_ROLE(), address(timelock));
        console.log("  Timelock granted GOVERNOR_ROLE on DLUXMinter");

        // Grant DLUXMinter EMITTER_ROLE to protocol contracts
        dluxMinter.grantRole(dluxMinter.EMITTER_ROLE(), address(factory));
        dluxMinter.grantRole(dluxMinter.EMITTER_ROLE(), address(stakedLux));
        console.log("  EMITTER_ROLE granted to AMM, StakedLUX");

        console.log("");
    }

    function _deploySafe(address[] memory owners, uint256 threshold, string memory name) internal returns (address) {
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            threshold,
            address(0),  // to
            "",          // data
            address(0),  // fallbackHandler
            address(0),  // paymentToken
            0,           // payment
            payable(address(0))  // paymentReceiver
        );

        SafeProxy proxy = safeFactory.createProxyWithNonce(
            address(safeImpl),
            initializer,
            uint256(keccak256(abi.encodePacked(name, block.timestamp)))
        );

        console.log(name, "Safe:", address(proxy));
        return address(proxy);
    }

    function _deployPhase10LSSVM() internal {
        console.log("--- Phase 10: LSSVM (NFT AMM) ---");

        linearCurve = new LinearCurve();
        console.log("LinearCurve:", address(linearCurve));

        exponentialCurve = new ExponentialCurve();
        console.log("ExponentialCurve:", address(exponentialCurve));

        lssvmFactory = new LSSVMPairFactory(deployer);
        console.log("LSSVMPairFactory:", address(lssvmFactory));

        lssvmFactory.setBondingCurveAllowed(address(linearCurve), true);
        lssvmFactory.setBondingCurveAllowed(address(exponentialCurve), true);

        lssvmRouter = new LSSVMRouter();
        console.log("LSSVMRouter:", address(lssvmRouter));
        console.log("");
    }

    function _deployPhase11Markets() internal {
        console.log("--- Phase 11: Markets (Lending) ---");

        markets = new Markets(deployer);
        console.log("Markets:", address(markets));
        console.log("");
    }

    function _deployPhase12Perps() internal {
        console.log("--- Phase 12: Perps ---");

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
        console.log("                    FULL STACK DEPLOYMENT COMPLETE");
        console.log("================================================================================");
        console.log("");
        console.log("BRIDGED COLLATERAL (1:1 from source chains):");
        console.log("  ETH:    ", address(eth));
        console.log("  BTC:    ", address(btc));
        console.log("  USDC:   ", address(usdc));
        console.log("  USDT:   ", address(usdt));
        console.log("  DAI:    ", address(dai));
        console.log("");
        console.log("NATIVE & STAKING:");
        console.log("  WLUX:       ", address(wlux));
        console.log("  StakedLUX:  ", address(stakedLux));
        console.log("  AI:         ", address(ai));
        console.log("");
        console.log("AMM:");
        console.log("  Factory:    ", address(factory));
        console.log("  Router:     ", address(router));
        console.log("");
        console.log("LP POOLS CREATED:");
        console.log("  LUX pairs:   WLUX/ETH, WLUX/BTC, WLUX/USDC, WLUX/AI");
        console.log("  Stables:     USDC/DAI, USDC/USDT");
        console.log("");
        console.log("TELEPORT VAULTS:");
        console.log("  LiquidVault:     ", address(liquidVault));
        console.log("");
        console.log("GOVERNANCE:");
        console.log("  VotesToken:     ", address(govToken));
        console.log("  Timelock:       ", address(timelock));
        console.log("  Governor:        SKIPPED (complex two-phase init)");
        console.log("  vLUX:           ", address(voteLux));
        console.log("  GaugeController:", address(gaugeController));
        console.log("  Karma (K):      ", address(karma));
        console.log("  KarmaMinter:    ", address(karmaMinter));
        console.log("  DLUX:           ", address(dlux));
        console.log("  DLUXMinter:     ", address(dluxMinter));
        console.log("");
        console.log("TREASURY:");
        console.log("  FeeGov:         ", address(feeGov));
        console.log("    Rate: 0.3%%, Floor: 0.1%%, Cap: 5%%");
        console.log("    Chains: P, X, A, B, C, D, T, G, Q, K, Z");
        console.log("  TreasuryVault:  ", address(treasuryVault));
        console.log("  TreasuryRouter: ", address(treasuryRouter));
        console.log("    Weights: 70%% stakers, 20%% DAO, 10%% validators");
        console.log("  ValidatorVault: ", address(validatorVault));
        console.log("");
        console.log("TREASURY SAFES:");
        console.log("  DAO Treasury:   ", daoTreasury);
        console.log("  Protocol Vault: ", protocolVault);
        console.log("  AI Treasury:    ", aiTreasury);
        console.log("  ZOO Treasury:   ", zooTreasury);
        console.log("");
        console.log("OTHER:");
        console.log("  DIDRegistry:    ", address(didRegistry));
        console.log("  Markets:        ", address(markets));
        console.log("  Perp:           ", address(perp));
        console.log("  LSSVM Factory:  ", address(lssvmFactory));
        console.log("");
        console.log("================================================================================");
        console.log("                         ALL 12 PHASES DEPLOYED");
        console.log("================================================================================");
    }
}
