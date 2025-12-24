// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Core Markets contracts
import {Markets, MarketParams, Id} from "../contracts/markets/Markets.sol";
import {IMarkets} from "../contracts/markets/interfaces/IMarkets.sol";
import {AdaptiveCurveRateModel} from "../contracts/markets/ratemodel/AdaptiveCurveRateModel.sol";
import {ChainlinkOracle} from "../contracts/markets/oracles/ChainlinkOracle.sol";
import {Allocator} from "../contracts/markets/Allocator.sol";
import {Router as MarketsRouter} from "../contracts/markets/Router.sol";
import {MarketParamsLib} from "../contracts/markets/libraries/MarketParamsLib.sol";

/// @title DeployMarkets
/// @notice Deploy the complete Lux Markets (Morpho Blue-style) lending protocol
/// @dev Deployment order:
///   1. Markets singleton
///   2. Rate models (AdaptiveCurve)
///   3. Oracles (Chainlink adapters)
///   4. Create lending markets
///   5. Allocator (optional vault layer)
///   6. Router (bundled operations)
contract DeployMarkets is Script, DeployConfig {
    using MarketParamsLib for MarketParams;

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT PARAMETERS
    // ═══════════════════════════════════════════════════════════════════════

    // Standard LLTV tiers (Loan-to-Value ratios)
    uint256 constant LLTV_945 = 0.945e18; // 94.5% - Stablecoin pairs
    uint256 constant LLTV_915 = 0.915e18; // 91.5% - Correlated assets
    uint256 constant LLTV_860 = 0.86e18;  // 86% - Major assets (ETH/BTC)
    uint256 constant LLTV_770 = 0.77e18;  // 77% - Standard assets
    uint256 constant LLTV_625 = 0.625e18; // 62.5% - Volatile assets

    // Maximum staleness for price feeds (1 hour)
    uint256 constant MAX_STALENESS = 1 hours;

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYED ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════

    struct DeployedMarkets {
        // Core
        address markets;
        address rateModel;
        address allocator;
        address router;

        // Oracles (per asset pair)
        address oracleETH_USD;
        address oracleBTC_USD;
        address oracleLUX_USD;

        // Market IDs
        bytes32 marketLUSD_WETH;  // Borrow LUSD against WETH
        bytes32 marketLUSD_WBTC;  // Borrow LUSD against WBTC
        bytes32 marketWETH_LUSD;  // Borrow WETH against LUSD
        bytes32 marketLUSD_LUSD;  // LUSD/LUSD (stablecoin)
    }

    DeployedMarkets public deployed;

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════

    function run() public virtual {
        _initConfigs();
        ChainConfig memory config = getConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|          LUX MARKETS (LENDING) DEPLOYMENT                    |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("+==============================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Markets singleton
        _deployMarkets(deployer);

        // Step 2: Deploy rate model
        _deployRateModel();

        // Step 3: Deploy oracles (if Chainlink feeds available)
        _deployOracles(config);

        // Step 4: Enable LLTVs
        _enableLLTVs();

        // Step 5: Create lending markets
        _createMarkets(config);

        // Step 6: Deploy Allocator (vault layer)
        _deployAllocator(deployer, config);

        // Step 7: Deploy Router (bundled operations)
        _deployRouter(config);

        vm.stopBroadcast();

        _printDeploymentSummary();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STEPS
    // ═══════════════════════════════════════════════════════════════════════

    function _deployMarkets(address owner) internal {
        console.log("  Step 1: Deploying Markets singleton...");

        Markets markets = new Markets(owner);
        deployed.markets = address(markets);
        console.log("    Markets:", deployed.markets);
    }

    function _deployRateModel() internal {
        console.log("  Step 2: Deploying Rate Model...");

        AdaptiveCurveRateModel rateModel = new AdaptiveCurveRateModel();
        deployed.rateModel = address(rateModel);
        console.log("    AdaptiveCurveRateModel:", deployed.rateModel);

        // Enable rate model in Markets
        Markets(deployed.markets).enableRateModel(deployed.rateModel);
        console.log("    Rate model enabled");
    }

    function _deployOracles(ChainConfig memory config) internal {
        console.log("  Step 3: Deploying Oracles...");

        // Check if Chainlink feeds are configured
        if (config.chainlinkETH == address(0)) {
            console.log("    (Chainlink feeds not configured - skipping oracle deployment)");
            console.log("    (For testnet, use mock oracles or configure feeds)");
            return;
        }

        // ETH/USD Oracle
        ChainlinkOracle oracleETH = new ChainlinkOracle(
            config.chainlinkETH,  // ETH/USD feed
            address(0),           // Quote is USD
            18,                   // ETH has 18 decimals
            18,                   // LUSD has 18 decimals
            MAX_STALENESS
        );
        deployed.oracleETH_USD = address(oracleETH);
        console.log("    Oracle ETH/USD:", deployed.oracleETH_USD);

        // BTC/USD Oracle (if available)
        if (config.chainlinkBTC != address(0)) {
            ChainlinkOracle oracleBTC = new ChainlinkOracle(
                config.chainlinkBTC,
                address(0),
                8,   // WBTC has 8 decimals
                18,  // LUSD has 18 decimals
                MAX_STALENESS
            );
            deployed.oracleBTC_USD = address(oracleBTC);
            console.log("    Oracle BTC/USD:", deployed.oracleBTC_USD);
        }

        // LUX/USD Oracle (if available)
        if (config.chainlinkLUX != address(0)) {
            ChainlinkOracle oracleLUX = new ChainlinkOracle(
                config.chainlinkLUX,
                address(0),
                18,  // LUX has 18 decimals
                18,  // LUSD has 18 decimals
                MAX_STALENESS
            );
            deployed.oracleLUX_USD = address(oracleLUX);
            console.log("    Oracle LUX/USD:", deployed.oracleLUX_USD);
        }
    }

    function _enableLLTVs() internal {
        console.log("  Step 4: Enabling LLTV tiers...");

        Markets markets = Markets(deployed.markets);

        markets.enableLltv(LLTV_945);
        console.log("    LLTV 94.5% enabled (stablecoins)");

        markets.enableLltv(LLTV_915);
        console.log("    LLTV 91.5% enabled (correlated)");

        markets.enableLltv(LLTV_860);
        console.log("    LLTV 86% enabled (major assets)");

        markets.enableLltv(LLTV_770);
        console.log("    LLTV 77% enabled (standard)");

        markets.enableLltv(LLTV_625);
        console.log("    LLTV 62.5% enabled (volatile)");
    }

    function _createMarkets(ChainConfig memory config) internal {
        console.log("  Step 5: Creating Lending Markets...");

        // Skip market creation if oracles not deployed
        if (deployed.oracleETH_USD == address(0)) {
            console.log("    (Skipping market creation - oracles not deployed)");
            console.log("    (Deploy oracles first, then create markets manually)");
            return;
        }

        Markets markets = Markets(deployed.markets);

        // Market: Borrow LUSD against WETH collateral (86% LTV)
        if (config.weth != address(0) && config.lusd != address(0)) {
            MarketParams memory paramsLUSD_WETH = MarketParams({
                loanToken: config.lusd,
                collateralToken: config.weth,
                oracle: deployed.oracleETH_USD,
                rateModel: deployed.rateModel,
                lltv: LLTV_860
            });
            markets.createMarket(paramsLUSD_WETH);
            deployed.marketLUSD_WETH = Id.unwrap(paramsLUSD_WETH.id());
            console.log("    Market LUSD/WETH created (86% LTV)");
        }

        // Market: Borrow LUSD against WBTC collateral (77% LTV)
        if (config.wbtc != address(0) && config.lusd != address(0) && deployed.oracleBTC_USD != address(0)) {
            MarketParams memory paramsLUSD_WBTC = MarketParams({
                loanToken: config.lusd,
                collateralToken: config.wbtc,
                oracle: deployed.oracleBTC_USD,
                rateModel: deployed.rateModel,
                lltv: LLTV_770
            });
            markets.createMarket(paramsLUSD_WBTC);
            deployed.marketLUSD_WBTC = Id.unwrap(paramsLUSD_WBTC.id());
            console.log("    Market LUSD/WBTC created (77% LTV)");
        }

        console.log("    Markets created successfully");
    }

    function _deployAllocator(address curator, ChainConfig memory config) internal {
        console.log("  Step 6: Deploying Allocator (LUSD vault)...");

        // Skip if LUSD not configured
        if (config.lusd == address(0)) {
            console.log("    (LUSD not configured - skipping Allocator)");
            return;
        }

        Allocator allocator = new Allocator(
            deployed.markets,
            config.lusd,
            "Lux Markets LUSD Vault",
            "lmLUSD",
            curator
        );
        deployed.allocator = address(allocator);
        console.log("    Allocator (lmLUSD):", deployed.allocator);
    }

    function _deployRouter(ChainConfig memory config) internal {
        console.log("  Step 7: Deploying Router...");

        // Use WLUX for native token wrapping
        address weth = config.weth != address(0) ? config.weth : config.wlux;
        
        if (weth == address(0)) {
            console.log("    (WETH/WLUX not configured - skipping Router)");
            return;
        }

        MarketsRouter router = new MarketsRouter(deployed.markets, weth);
        deployed.router = address(router);
        console.log("    Router:", deployed.router);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Create a market with specific parameters
    /// @dev Call after initial deployment to add more markets
    function createMarket(
        address loanToken,
        address collateralToken,
        address oracle,
        uint256 lltv
    ) external returns (bytes32 marketId) {
        require(deployed.markets != address(0), "Markets not deployed");

        MarketParams memory params = MarketParams({
            loanToken: loanToken,
            collateralToken: collateralToken,
            oracle: oracle,
            rateModel: deployed.rateModel,
            lltv: lltv
        });

        Markets(deployed.markets).createMarket(params);
        return Id.unwrap(params.id());
    }

    function _printDeploymentSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|              MARKETS DEPLOYMENT SUMMARY                       |");
        console.log("+==============================================================+");
        console.log("");
        console.log("  Core Contracts:");
        console.log("    Markets:", deployed.markets);
        console.log("    RateModel:", deployed.rateModel);
        console.log("    Allocator:", deployed.allocator);
        console.log("    Router:", deployed.router);
        console.log("");
        console.log("  Oracles:");
        console.log("    ETH/USD:", deployed.oracleETH_USD);
        console.log("    BTC/USD:", deployed.oracleBTC_USD);
        console.log("    LUX/USD:", deployed.oracleLUX_USD);
        console.log("");
        console.log("  Enabled LLTV Tiers:");
        console.log("    94.5% - Stablecoin pairs (LUSD/USDC)");
        console.log("    91.5% - Correlated assets (xETH/LETH)");
        console.log("    86%   - Major assets (ETH, BTC)");
        console.log("    77%   - Standard assets");
        console.log("    62.5% - Volatile assets");
        console.log("");
        console.log("  Next Steps:");
        console.log("    1. Configure Chainlink price feeds for production");
        console.log("    2. Create additional markets via createMarket()");
        console.log("    3. Set fee recipient via markets.setFeeRecipient()");
        console.log("    4. Integrate with Synths for yield-bearing collateral");
        console.log("");
        console.log("+==============================================================+");
        console.log("");
    }

    /// @notice Get deployed addresses
    function getDeployedAddresses() external view returns (DeployedMarkets memory) {
        return deployed;
    }
}

/// @title DeployMarketsTestnet
/// @notice Deploy Markets with mock oracles for testnet
contract DeployMarketsTestnet is DeployMarkets {
    function run() public override {
        console.log("Deploying Markets to Testnet with mock configuration...");
        super.run();
    }
}

/// @title DeployMarketsLocal
/// @notice Deploy Markets for local Anvil testing
contract DeployMarketsLocal is DeployMarkets {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil for local deployment");
        super.run();
    }
}
