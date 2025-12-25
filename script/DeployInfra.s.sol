// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Infrastructure imports
import {Multicall} from "../contracts/multicall/Multicall.sol";
import {Multicall2} from "../contracts/multicall/Multicall2.sol";
import {MultiFaucet} from "../contracts/utils/MultiFaucet.sol";
import {MockChainlinkAggregator, MockOracleFactory} from "../contracts/mocks/MockChainlinkOracle.sol";
import {ChainlinkOracle} from "../contracts/markets/oracles/ChainlinkOracle.sol";

/// @title DeployInfra
/// @notice Deploys infrastructure contracts: Multicall, Faucet, Mock Oracles
/// @dev For local/testnet deployments
contract DeployInfra is Script, DeployConfig {

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STRUCT
    // ═══════════════════════════════════════════════════════════════════════

    struct InfraDeployment {
        // Utilities
        address multicall;
        address multicall2;
        address faucet;

        // Mock Oracles (testnet only)
        address ethUsdOracle;
        address btcUsdOracle;
        address luxUsdOracle;
        address usdcUsdOracle;

        // Markets Oracles (wrapped for IOracle interface)
        address ethUsdMarketsOracle;
        address btcUsdMarketsOracle;
    }

    InfraDeployment public deployment;

    // Token addresses (set before deployment)
    address public wlux;
    address public lusd;
    address public weth;
    address public aiToken;

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════

    function run() public virtual {
        _initConfigs();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|          INFRASTRUCTURE DEPLOYMENT                           |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("|  Network:", _getNetworkName());
        console.log("+==============================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy utilities
        _deployUtilities();

        // Deploy mock oracles (testnet/local only)
        if (block.chainid == 31337 || isTestnet()) {
            _deployMockOracles();
        }

        // Setup faucet with tokens if addresses provided
        if (wlux != address(0)) {
            _setupFaucet();
        }

        vm.stopBroadcast();

        _printSummary();
    }

    /// @notice Deploy with token addresses
    function runWithTokens(
        address _wlux,
        address _lusd,
        address _weth,
        address _aiToken
    ) public {
        wlux = _wlux;
        lusd = _lusd;
        weth = _weth;
        aiToken = _aiToken;
        run();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT LOGIC
    // ═══════════════════════════════════════════════════════════════════════

    function _deployUtilities() internal {
        console.log("  Deploying utilities...");

        // Multicall
        Multicall multicall = new Multicall();
        deployment.multicall = address(multicall);
        console.log("    Multicall:", deployment.multicall);

        // Multicall2 (extended version)
        Multicall2 multicall2 = new Multicall2();
        deployment.multicall2 = address(multicall2);
        console.log("    Multicall2:", deployment.multicall2);

        // MultiFaucet
        MultiFaucet faucet = new MultiFaucet();
        deployment.faucet = address(faucet);
        console.log("    MultiFaucet:", deployment.faucet);
    }

    function _deployMockOracles() internal {
        console.log("  Deploying mock oracles (testnet)...");

        // Deploy mock Chainlink aggregators
        MockOracleFactory factory = new MockOracleFactory();
        (
            address ethUsd,
            address btcUsd,
            address luxUsd,
            address usdcUsd
        ) = factory.deployCommonOracles();

        deployment.ethUsdOracle = ethUsd;
        deployment.btcUsdOracle = btcUsd;
        deployment.luxUsdOracle = luxUsd;
        deployment.usdcUsdOracle = usdcUsd;

        console.log("    ETH/USD:", deployment.ethUsdOracle);
        console.log("    BTC/USD:", deployment.btcUsdOracle);
        console.log("    LUX/USD:", deployment.luxUsdOracle);
        console.log("    USDC/USD:", deployment.usdcUsdOracle);

        // Deploy Markets-compatible oracles (IOracle interface)
        // ETH/USD oracle for Markets (collateral=ETH, loan=USD)
        ChainlinkOracle ethOracle = new ChainlinkOracle(
            deployment.ethUsdOracle,  // base feed
            address(0),               // quote feed (USD = no feed)
            18,                       // ETH decimals
            6,                        // USD decimals (like USDC)
            3600                      // 1 hour staleness
        );
        deployment.ethUsdMarketsOracle = address(ethOracle);
        console.log("    ETH/USD (Markets):", deployment.ethUsdMarketsOracle);

        // BTC/USD oracle for Markets
        ChainlinkOracle btcOracle = new ChainlinkOracle(
            deployment.btcUsdOracle,
            address(0),
            8,                        // BTC decimals
            6,                        // USD decimals
            3600
        );
        deployment.btcUsdMarketsOracle = address(btcOracle);
        console.log("    BTC/USD (Markets):", deployment.btcUsdMarketsOracle);
    }

    function _setupFaucet() internal {
        console.log("  Configuring faucet tokens...");
        MultiFaucet faucet = MultiFaucet(payable(deployment.faucet));

        // Add tokens with drip amounts and 1 hour cooldown
        if (wlux != address(0)) {
            faucet.addToken(wlux, 10 ether, 1 hours);       // 10 WLUX
            console.log("    Added WLUX: 10 per drip");
        }
        if (lusd != address(0)) {
            faucet.addToken(lusd, 1000e6, 1 hours);         // 1000 LUSD (6 decimals)
            console.log("    Added LUSD: 1000 per drip");
        }
        if (weth != address(0)) {
            faucet.addToken(weth, 0.1 ether, 1 hours);      // 0.1 WETH
            console.log("    Added WETH: 0.1 per drip");
        }
        if (aiToken != address(0)) {
            faucet.addToken(aiToken, 100 ether, 1 hours);   // 100 AI
            console.log("    Added AI: 100 per drip");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _getNetworkName() internal view returns (string memory) {
        if (block.chainid == LUX_MAINNET) return "Lux Mainnet";
        if (block.chainid == LUX_TESTNET) return "Lux Testnet";
        if (block.chainid == HANZO_MAINNET) return "Hanzo Mainnet";
        if (block.chainid == HANZO_TESTNET) return "Hanzo Testnet";
        if (block.chainid == ZOO_MAINNET) return "Zoo Mainnet";
        if (block.chainid == ZOO_TESTNET) return "Zoo Testnet";
        if (block.chainid == 31337) return "Anvil (Local)";
        return "Unknown";
    }

    function _printSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|              INFRASTRUCTURE DEPLOYMENT COMPLETE              |");
        console.log("+==============================================================+");
        console.log("|  UTILITIES                                                   |");
        console.log("|    Multicall:", deployment.multicall);
        console.log("|    Multicall2:", deployment.multicall2);
        console.log("|    MultiFaucet:", deployment.faucet);
        if (deployment.ethUsdOracle != address(0)) {
            console.log("+--------------------------------------------------------------+");
            console.log("|  MOCK ORACLES                                                |");
            console.log("|    ETH/USD:", deployment.ethUsdOracle);
            console.log("|    BTC/USD:", deployment.btcUsdOracle);
            console.log("|    LUX/USD:", deployment.luxUsdOracle);
            console.log("|    USDC/USD:", deployment.usdcUsdOracle);
        }
        console.log("+==============================================================+");
        console.log("");
    }

    /// @notice Fund the faucet with native LUX
    function fundFaucetNative() external payable {
        require(deployment.faucet != address(0), "Faucet not deployed");
        (bool success,) = deployment.faucet.call{value: msg.value}("");
        require(success, "Fund failed");
    }
}

/// @title DeployInfraLocal
contract DeployInfraLocal is DeployInfra {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil");
        super.run();
    }
}

/// @title DeployInfraTestnet
contract DeployInfraTestnet is DeployInfra {
    function run() public override {
        require(isTestnet(), "Wrong network");
        super.run();
    }
}
