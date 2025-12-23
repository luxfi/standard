// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Core Perps contracts
import "../contracts/perps/core/interfaces/IVault.sol";
import "../contracts/perps/core/interfaces/IVaultUtils.sol";
import "../contracts/perps/core/Vault.sol";
import "../contracts/perps/core/VaultUtils.sol";
import "../contracts/perps/core/VaultPriceFeed.sol";
import "../contracts/perps/core/Router.sol";
import "../contracts/perps/core/PositionRouter.sol";
import "../contracts/perps/core/PositionManager.sol";
import "../contracts/perps/core/OrderBook.sol";
import "../contracts/perps/core/ShortsTracker.sol";
import "../contracts/perps/core/GlpManager.sol";

// Tokens
import "../contracts/perps/gmx/GMX.sol";
import "../contracts/perps/gmx/GLP.sol";
import "../contracts/perps/gmx/EsGMX.sol";
import "../contracts/perps/tokens/USDG.sol";

// Staking
import "../contracts/perps/staking/RewardRouterV2.sol";
import "../contracts/perps/staking/RewardTracker.sol";
import "../contracts/perps/staking/RewardDistributor.sol";
import "../contracts/perps/staking/BonusDistributor.sol";
import "../contracts/perps/staking/Vester.sol";
import "../contracts/perps/staking/StakedGlp.sol";

// Oracle
import "../contracts/perps/oracle/FastPriceFeed.sol";
import "../contracts/perps/oracle/FastPriceEvents.sol";
import "../contracts/perps/oracle/PriceFeed.sol";

// Peripherals
import "../contracts/perps/peripherals/Timelock.sol";
import "../contracts/perps/peripherals/Reader.sol";
import "../contracts/perps/peripherals/VaultReader.sol";
import "../contracts/perps/peripherals/PositionRouterReader.sol";
import "../contracts/perps/peripherals/OrderBookReader.sol";

// Referrals
import "../contracts/perps/referrals/ReferralStorage.sol";
import "../contracts/perps/referrals/ReferralReader.sol";

/// @title DeployPerps
/// @notice Deploy the complete Perps (GMX-style) perpetual trading protocol
/// @dev Deployment order:
///   1. USDG (stablecoin)
///   2. Vault + VaultUtils + VaultPriceFeed
///   3. Router + PositionRouter + OrderBook
///   4. GMX + GLP + EsGMX tokens
///   5. Staking (RewardRouter, Trackers, Vesters)
///   6. Oracle (FastPriceFeed, PriceFeeds)
///   7. Peripherals (Reader, Timelock)
///   8. Referrals
contract DeployPerps is Script, DeployConfig {
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════
    
    // Vault parameters
    uint256 constant LIQUIDATION_FEE_USD = 5e30; // $5
    uint256 constant MIN_PROFIT_TIME = 3 hours;
    uint256 constant MAX_LEVERAGE = 50 * 10000; // 50x
    
    // Fee parameters (in BPS)
    uint256 constant TAX_BASIS_POINTS = 50; // 0.5%
    uint256 constant STABLE_TAX_BASIS_POINTS = 20; // 0.2%
    uint256 constant MINT_BURN_FEE_BASIS_POINTS = 30; // 0.3%
    uint256 constant SWAP_FEE_BASIS_POINTS = 30; // 0.3%
    uint256 constant STABLE_SWAP_FEE_BASIS_POINTS = 4; // 0.04%
    uint256 constant MARGIN_FEE_BASIS_POINTS = 10; // 0.1%
    
    // Funding parameters
    uint256 constant FUNDING_INTERVAL = 8 hours;
    uint256 constant FUNDING_RATE_FACTOR = 100;
    uint256 constant STABLE_FUNDING_RATE_FACTOR = 100;
    
    // Staking parameters
    uint256 constant VESTING_DURATION = 365 days;
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYED ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════
    
    struct DeployedPerps {
        // Core
        address vault;
        address vaultUtils;
        address vaultPriceFeed;
        address usdg;
        address router;
        address positionRouter;
        address positionManager;
        address orderBook;
        address shortsTracker;
        address glpManager;
        
        // Tokens
        address gmx;
        address esGmx;
        address glp;
        address bnGmx; // Bonus GMX
        
        // Staking
        address stakedGmxTracker;      // staked GMX
        address bonusGmxTracker;        // staked + bonus GMX
        address feeGmxTracker;          // staked + bonus + fee GMX
        address stakedGlpTracker;       // staked GLP
        address feeGlpTracker;          // staked + fee GLP
        address gmxVester;
        address glpVester;
        address stakedGlp;
        address rewardRouter;
        
        // Distributors
        address stakedGmxDistributor;
        address bonusGmxDistributor;
        address feeGmxDistributor;
        address stakedGlpDistributor;
        address feeGlpDistributor;
        
        // Oracle
        address fastPriceFeed;
        address fastPriceEvents;
        
        // Peripherals
        address timelock;
        address reader;
        address vaultReader;
        address positionRouterReader;
        address orderBookReader;
        
        // Referrals
        address referralStorage;
        address referralReader;
    }
    
    DeployedPerps public deployed;
    
    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════
    
    function run() public virtual {
        _initConfigs();
        ChainConfig memory config = getConfig();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Perps Protocol Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy USDG
        _deployUSDG();
        
        // Step 2: Deploy Vault
        _deployVault(deployer, config);
        
        // Step 3: Deploy Router + Position contracts
        _deployRouting(deployer);
        
        // Step 4: Deploy tokens
        _deployTokens();
        
        // Step 5: Deploy GLP Manager
        _deployGlpManager();
        
        // Step 6: Deploy staking
        _deployStaking(deployer, config);
        
        // Step 7: Deploy oracle
        _deployOracle(deployer, config);
        
        // Step 8: Deploy peripherals
        _deployPeripherals(deployer, config);
        
        // Step 9: Deploy referrals
        _deployReferrals(deployer);
        
        // Step 10: Configure protocol
        _configureProtocol(deployer, config);
        
        vm.stopBroadcast();
        
        // Output deployment summary
        _printDeploymentSummary();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STEPS
    // ═══════════════════════════════════════════════════════════════════════
    
    function _deployUSDG() internal {
        console.log("Step 1: Deploying USDG...");
        
        USDG usdg = new USDG(address(0)); // Vault will be set later
        deployed.usdg = address(usdg);
        console.log("  USDG:", deployed.usdg);
    }
    
    function _deployVault(address gov, ChainConfig memory) internal {
        console.log("Step 2: Deploying Vault...");
        
        // VaultPriceFeed must be deployed first
        
        // Deploy VaultPriceFeed
        VaultPriceFeed vaultPriceFeed = new VaultPriceFeed();
        deployed.vaultPriceFeed = address(vaultPriceFeed);
        
        // Deploy Vault
        Vault vault = new Vault();
        deployed.vault = address(vault);
        
        // Initialize vault
        vault.initialize(
            address(0), // router - set later
            deployed.usdg,
            deployed.vaultPriceFeed,
            LIQUIDATION_FEE_USD,
            FUNDING_RATE_FACTOR,
            STABLE_FUNDING_RATE_FACTOR
        );
        
        // Configure vault
        vault.setFees(
            TAX_BASIS_POINTS,
            STABLE_TAX_BASIS_POINTS,
            MINT_BURN_FEE_BASIS_POINTS,
            SWAP_FEE_BASIS_POINTS,
            STABLE_SWAP_FEE_BASIS_POINTS,
            MARGIN_FEE_BASIS_POINTS,
            LIQUIDATION_FEE_USD,
            MIN_PROFIT_TIME,
            true // hasDynamicFees
        );
        
        // Deploy VaultUtils with vault reference
        VaultUtils vaultUtils = new VaultUtils(IVault(address(vault)));
        deployed.vaultUtils = address(vaultUtils);
        vault.setVaultUtils(IVaultUtils(address(vaultUtils)));
        
        // Set USDG vault
        USDG(deployed.usdg).addVault(deployed.vault);
        
        console.log("  Vault:", deployed.vault);
        console.log("  VaultUtils:", deployed.vaultUtils);
        console.log("  VaultPriceFeed:", deployed.vaultPriceFeed);
    }
    
    function _deployRouting(address) internal {
        console.log("Step 3: Deploying Router + Position contracts...");
        
        // Deploy Router
        Router router = new Router(deployed.vault, deployed.usdg, address(0)); // WETH later
        deployed.router = address(router);
        
        // Deploy ShortsTracker
        ShortsTracker shortsTracker = new ShortsTracker(deployed.vault);
        deployed.shortsTracker = address(shortsTracker);
        
        // Deploy OrderBook
        OrderBook orderBook = new OrderBook();
        orderBook.initialize(
            deployed.router,
            deployed.vault,
            address(0), // WETH
            deployed.usdg,
            1e16, // minExecutionFee
            1e30  // minPurchaseTokenAmountUsd
        );
        deployed.orderBook = address(orderBook);
        
        // Deploy PositionRouter
        PositionRouter positionRouter = new PositionRouter(
            deployed.vault,
            deployed.router,
            address(0), // WETH
            deployed.shortsTracker,
            30, // depositFee basis points
            1e16 // minExecutionFee
        );
        deployed.positionRouter = address(positionRouter);
        
        // Deploy PositionManager
        PositionManager positionManager = new PositionManager(
            deployed.vault,
            deployed.router,
            deployed.shortsTracker,
            address(0), // WETH
            30, // depositFee
            deployed.orderBook
        );
        deployed.positionManager = address(positionManager);
        
        // Note: Router is set during vault.initialize()
        // Additional routers can be approved per-user via vault.addRouter()
        
        console.log("  Router:", deployed.router);
        console.log("  PositionRouter:", deployed.positionRouter);
        console.log("  PositionManager:", deployed.positionManager);
        console.log("  OrderBook:", deployed.orderBook);
        console.log("  ShortsTracker:", deployed.shortsTracker);
    }
    
    function _deployTokens() internal {
        console.log("Step 4: Deploying Tokens...");
        
        // GMX governance/utility token
        GMX gmx = new GMX();
        deployed.gmx = address(gmx);
        
        // Escrowed GMX
        EsGMX esGmx = new EsGMX();
        deployed.esGmx = address(esGmx);
        
        // GLP liquidity provider token
        GLP glp = new GLP();
        deployed.glp = address(glp);
        
        console.log("  GMX:", deployed.gmx);
        console.log("  EsGMX:", deployed.esGmx);
        console.log("  GLP:", deployed.glp);
    }
    
    function _deployGlpManager() internal {
        console.log("Step 5: Deploying GLP Manager...");
        
        GlpManager glpManager = new GlpManager(
            deployed.vault,
            deployed.usdg,
            deployed.glp,
            deployed.shortsTracker,
            15 minutes // cooldown duration
        );
        deployed.glpManager = address(glpManager);
        
        // Set GlpManager as GLP minter
        GLP(deployed.glp).setMinter(deployed.glpManager, true);
        
        // Set GlpManager on USDG
        USDG(deployed.usdg).addVault(deployed.glpManager);
        
        console.log("  GlpManager:", deployed.glpManager);
    }
    
    function _deployStaking(address, ChainConfig memory config) internal {
        console.log("Step 6: Deploying Staking...");
        
        // Deploy RewardRouter
        RewardRouterV2 rewardRouter = new RewardRouterV2();
        deployed.rewardRouter = address(rewardRouter);
        
        // Staked GMX
        RewardTracker stakedGmxTracker = new RewardTracker("Staked GMX", "sGMX");
        deployed.stakedGmxTracker = address(stakedGmxTracker);
        
        RewardDistributor stakedGmxDistributor = new RewardDistributor(
            deployed.esGmx, 
            deployed.stakedGmxTracker
        );
        deployed.stakedGmxDistributor = address(stakedGmxDistributor);
        
        // Bonus GMX
        RewardTracker bonusGmxTracker = new RewardTracker("Staked + Bonus GMX", "sbGMX");
        deployed.bonusGmxTracker = address(bonusGmxTracker);
        
        BonusDistributor bonusGmxDistributor = new BonusDistributor(
            address(0), // bnGMX
            deployed.bonusGmxTracker
        );
        deployed.bonusGmxDistributor = address(bonusGmxDistributor);
        
        // Fee GMX
        RewardTracker feeGmxTracker = new RewardTracker("Staked + Bonus + Fee GMX", "sbfGMX");
        deployed.feeGmxTracker = address(feeGmxTracker);
        
        RewardDistributor feeGmxDistributor = new RewardDistributor(
            config.weth,
            deployed.feeGmxTracker
        );
        deployed.feeGmxDistributor = address(feeGmxDistributor);
        
        // Staked GLP
        RewardTracker stakedGlpTracker = new RewardTracker("Fee + Staked GLP", "fsGLP");
        deployed.stakedGlpTracker = address(stakedGlpTracker);
        
        RewardDistributor stakedGlpDistributor = new RewardDistributor(
            deployed.esGmx,
            deployed.stakedGlpTracker
        );
        deployed.stakedGlpDistributor = address(stakedGlpDistributor);
        
        // Fee GLP
        RewardTracker feeGlpTracker = new RewardTracker("Staked GLP", "sGLP");
        deployed.feeGlpTracker = address(feeGlpTracker);
        
        RewardDistributor feeGlpDistributor = new RewardDistributor(
            config.weth,
            deployed.feeGlpTracker
        );
        deployed.feeGlpDistributor = address(feeGlpDistributor);
        
        // StakedGlp helper
        StakedGlp stakedGlp = new StakedGlp(
            deployed.glp,
            IGlpManager(deployed.glpManager),
            deployed.stakedGlpTracker,
            deployed.feeGlpTracker
        );
        deployed.stakedGlp = address(stakedGlp);
        
        // Vesters
        Vester gmxVester = new Vester(
            "Vested GMX",
            "vGMX",
            VESTING_DURATION,
            deployed.esGmx,
            deployed.feeGmxTracker,
            deployed.gmx,
            deployed.stakedGmxTracker
        );
        deployed.gmxVester = address(gmxVester);
        
        Vester glpVester = new Vester(
            "Vested GLP",
            "vGLP",
            VESTING_DURATION,
            deployed.esGmx,
            deployed.stakedGlpTracker,
            deployed.gmx,
            deployed.stakedGlpTracker
        );
        deployed.glpVester = address(glpVester);
        
        console.log("  RewardRouter:", deployed.rewardRouter);
        console.log("  StakedGmxTracker:", deployed.stakedGmxTracker);
        console.log("  BonusGmxTracker:", deployed.bonusGmxTracker);
        console.log("  FeeGmxTracker:", deployed.feeGmxTracker);
        console.log("  StakedGlpTracker:", deployed.stakedGlpTracker);
        console.log("  FeeGlpTracker:", deployed.feeGlpTracker);
        console.log("  GMXVester:", deployed.gmxVester);
        console.log("  GLPVester:", deployed.glpVester);
    }
    
    function _deployOracle(address, ChainConfig memory) internal {
        console.log("Step 7: Deploying Oracle...");
        
        // FastPriceEvents
        FastPriceEvents fastPriceEvents = new FastPriceEvents();
        deployed.fastPriceEvents = address(fastPriceEvents);
        
        // FastPriceFeed
        uint256 priceDuration = 5 minutes;
        uint256 maxPriceUpdateDelay = 1 hours;
        uint256 minBlockInterval = 0;
        uint256 maxDeviationBasisPoints = 250; // 2.5%
        
        address[] memory tokenManagers = new address[](1);
        tokenManagers[0] = msg.sender;
        
        address[] memory updaters = new address[](1);
        updaters[0] = msg.sender;
        
        FastPriceFeed fastPriceFeed = new FastPriceFeed(
            priceDuration,
            maxPriceUpdateDelay,
            minBlockInterval,
            maxDeviationBasisPoints,
            deployed.fastPriceEvents,
            tokenManagers[0] // tokenManager is a single address
        );
        deployed.fastPriceFeed = address(fastPriceFeed);
        
        // Set secondary price feed on VaultPriceFeed
        VaultPriceFeed(deployed.vaultPriceFeed).setSecondaryPriceFeed(deployed.fastPriceFeed);
        
        console.log("  FastPriceFeed:", deployed.fastPriceFeed);
        console.log("  FastPriceEvents:", deployed.fastPriceEvents);
    }
    
    function _deployPeripherals(address gov, ChainConfig memory config) internal {
        console.log("Step 8: Deploying Peripherals...");
        
        // Timelock
        uint256 buffer = 24 hours;
        uint256 maxTokenSupply = 0; // No cap
        
        Timelock timelock = new Timelock(
            gov, // admin
            buffer,
            gov, // tokenManager
            gov, // mintReceiver
            deployed.glpManager,
            address(0), // prevGlpManager (none for new deployment)
            deployed.rewardRouter,
            maxTokenSupply,
            10, // marginFeeBasisPoints
            500 // maxMarginFeeBasisPoints
        );
        deployed.timelock = address(timelock);
        
        // Reader
        Reader reader = new Reader();
        deployed.reader = address(reader);
        
        // VaultReader
        VaultReader vaultReader = new VaultReader();
        deployed.vaultReader = address(vaultReader);
        
        // PositionRouterReader
        PositionRouterReader positionRouterReader = new PositionRouterReader();
        deployed.positionRouterReader = address(positionRouterReader);
        
        // OrderBookReader
        OrderBookReader orderBookReader = new OrderBookReader();
        deployed.orderBookReader = address(orderBookReader);
        
        console.log("  Timelock:", deployed.timelock);
        console.log("  Reader:", deployed.reader);
        console.log("  VaultReader:", deployed.vaultReader);
        console.log("  PositionRouterReader:", deployed.positionRouterReader);
        console.log("  OrderBookReader:", deployed.orderBookReader);
    }
    
    function _deployReferrals(address) internal {
        console.log("Step 9: Deploying Referrals...");
        
        ReferralStorage referralStorage = new ReferralStorage();
        deployed.referralStorage = address(referralStorage);
        
        ReferralReader referralReader = new ReferralReader();
        deployed.referralReader = address(referralReader);
        
        console.log("  ReferralStorage:", deployed.referralStorage);
        console.log("  ReferralReader:", deployed.referralReader);
    }
    
    function _configureProtocol(address gov, ChainConfig memory config) internal {
        console.log("Step 10: Configuring Protocol...");
        
        // Set governance
        Vault vault = Vault(payable(deployed.vault));
        vault.setGov(deployed.timelock);
        
        // Initialize RewardRouter
        RewardRouterV2(payable(deployed.rewardRouter)).initialize(
            config.weth,
            deployed.gmx,
            deployed.esGmx,
            address(0), // bnGMX
            deployed.glp,
            deployed.stakedGmxTracker,
            deployed.bonusGmxTracker,
            deployed.feeGmxTracker,
            deployed.feeGlpTracker,
            deployed.stakedGlpTracker,
            deployed.glpManager,
            deployed.gmxVester,
            deployed.glpVester,
            deployed.gmx // govToken
        );
        
        // Configure reward trackers
        _configureRewardTrackers();
        
        console.log("  Protocol configured");
    }
    
    function _configureRewardTrackers() internal {
        // Configure staked GMX tracker
        RewardTracker stakedGmxTracker = RewardTracker(deployed.stakedGmxTracker);
        stakedGmxTracker.initialize(
            _singleAddressArray(deployed.gmx),
            deployed.stakedGmxDistributor
        );
        stakedGmxTracker.setInPrivateTransferMode(true);
        stakedGmxTracker.setInPrivateStakingMode(true);
        stakedGmxTracker.setHandler(deployed.rewardRouter, true);
        
        // Configure bonus GMX tracker
        RewardTracker bonusGmxTracker = RewardTracker(deployed.bonusGmxTracker);
        bonusGmxTracker.initialize(
            _singleAddressArray(deployed.stakedGmxTracker),
            deployed.bonusGmxDistributor
        );
        bonusGmxTracker.setInPrivateTransferMode(true);
        bonusGmxTracker.setInPrivateStakingMode(true);
        bonusGmxTracker.setHandler(deployed.rewardRouter, true);
        
        // Configure fee GMX tracker
        RewardTracker feeGmxTracker = RewardTracker(deployed.feeGmxTracker);
        address[] memory feeGmxDepositTokens = new address[](2);
        feeGmxDepositTokens[0] = deployed.bonusGmxTracker;
        feeGmxDepositTokens[1] = address(0); // bnGMX
        feeGmxTracker.initialize(
            feeGmxDepositTokens,
            deployed.feeGmxDistributor
        );
        feeGmxTracker.setInPrivateTransferMode(true);
        feeGmxTracker.setInPrivateStakingMode(true);
        feeGmxTracker.setHandler(deployed.rewardRouter, true);
        
        // Configure staked GLP tracker
        RewardTracker stakedGlpTracker = RewardTracker(deployed.stakedGlpTracker);
        stakedGlpTracker.initialize(
            _singleAddressArray(deployed.feeGlpTracker),
            deployed.stakedGlpDistributor
        );
        stakedGlpTracker.setInPrivateTransferMode(true);
        stakedGlpTracker.setInPrivateStakingMode(true);
        stakedGlpTracker.setHandler(deployed.rewardRouter, true);
        
        // Configure fee GLP tracker
        RewardTracker feeGlpTracker = RewardTracker(deployed.feeGlpTracker);
        feeGlpTracker.initialize(
            _singleAddressArray(deployed.glp),
            deployed.feeGlpDistributor
        );
        feeGlpTracker.setInPrivateTransferMode(true);
        feeGlpTracker.setInPrivateStakingMode(true);
        feeGlpTracker.setHandler(deployed.stakedGlp, true);
        feeGlpTracker.setHandler(deployed.rewardRouter, true);
    }
    
    function _singleAddressArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // OUTPUT
    // ═══════════════════════════════════════════════════════════════════════
    
    function _printDeploymentSummary() internal view {
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("");
        console.log("Core:");
        console.log("  Vault:", deployed.vault);
        console.log("  VaultUtils:", deployed.vaultUtils);
        console.log("  VaultPriceFeed:", deployed.vaultPriceFeed);
        console.log("  USDG:", deployed.usdg);
        console.log("");
        console.log("Routing:");
        console.log("  Router:", deployed.router);
        console.log("  PositionRouter:", deployed.positionRouter);
        console.log("  PositionManager:", deployed.positionManager);
        console.log("  OrderBook:", deployed.orderBook);
        console.log("");
        console.log("Tokens:");
        console.log("  GMX:", deployed.gmx);
        console.log("  EsGMX:", deployed.esGmx);
        console.log("  GLP:", deployed.glp);
        console.log("");
        console.log("Staking:");
        console.log("  RewardRouter:", deployed.rewardRouter);
        console.log("  GlpManager:", deployed.glpManager);
        console.log("");
        console.log("Oracle:");
        console.log("  FastPriceFeed:", deployed.fastPriceFeed);
        console.log("");
        console.log("Peripherals:");
        console.log("  Timelock:", deployed.timelock);
        console.log("  Reader:", deployed.reader);
        console.log("");
    }
}

/// @title DeployPerpsTestnet
/// @notice Deploy Perps with mock price feeds for testnet
contract DeployPerpsTestnet is DeployPerps {
    function run() public override {
        console.log("Deploying Perps to Testnet...");
        super.run();
    }
}
