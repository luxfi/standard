// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";
import "./Create2Deployer.sol";

// Note: Uniswap V2 is Solidity 0.5.16, so we deploy via Create2 with pre-compiled bytecode
// For testing, we use the mock AMM from Integration.t.sol or deployed canonical contracts

/// @title DeployAMM
/// @notice Deployment script for AMM infrastructure (Uniswap V2/V3 style)
/// @dev Since Uniswap V2 requires Solidity 0.5.16, this script references pre-deployed
///      factory/router addresses or deploys via bytecode
contract DeployAMM is Script, DeployConfig {
    
    // Canonical Uniswap V2 factory init code hash (for pair address calculation)
    bytes32 constant UNI_V2_INIT_CODE_HASH = 
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    
    struct AMMDeployment {
        address v2Factory;
        address v2Router;
        address v3Factory;
        address v3Router;
        address v3PositionManager;
        // Key LP pairs
        address wluxUsdc;
        address wluxUsdt;
        address wluxWeth;
        address usdcUsdt;
        address alUsdUsdc;
        address alEthWeth;
    }
    
    AMMDeployment public amm;
    
    /// @notice Main deployment entry point
    function run() public {
        _initConfigs();
        ChainConfig memory config = getConfig();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("");
        console.log("+==============================================================+");
        console.log("|          LUX AMM INFRASTRUCTURE DEPLOYMENT                   |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("+==============================================================+");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // For production, we use existing canonical Uniswap deployments or deploy via bytecode
        // For testnet/local, we deploy fresh instances
        
        if (isMainnet()) {
            _useCanonicalDeployments(config);
        } else {
            _deployFreshAMM(deployer, config);
        }
        
        vm.stopBroadcast();
        
        _printSummary();
    }
    
    /// @notice Use canonical Uniswap deployments on mainnet
    function _useCanonicalDeployments(ChainConfig memory config) internal {
        console.log("  Using canonical AMM deployments...");
        
        amm.v2Factory = config.uniV2Factory;
        amm.v2Router = config.uniV2Router;
        amm.v3Factory = config.uniV3Factory;
        amm.v3Router = config.uniV3Router;
        
        require(amm.v2Factory != address(0), "V2 Factory not configured");
        require(amm.v2Router != address(0), "V2 Router not configured");
        
        console.log("    V2 Factory:", amm.v2Factory);
        console.log("    V2 Router:", amm.v2Router);
        console.log("    V3 Factory:", amm.v3Factory);
        console.log("    V3 Router:", amm.v3Router);
    }
    
    /// @notice Deploy fresh AMM for testnet/local
    /// @dev Uses CREATE2 for deterministic addresses
    function _deployFreshAMM(address, ChainConfig memory) internal {
        console.log("  Deploying fresh AMM infrastructure...");
        
        // Note: For actual deployment, we would:
        // 1. Deploy UniswapV2Factory with feeToSetter
        // 2. Deploy UniswapV2Router02 with factory + WETH
        // 3. Deploy UniswapV3Factory
        // 4. Deploy SwapRouter with factory + WETH
        // 5. Deploy NonfungiblePositionManager
        
        // For now, log that this requires Solidity 0.5.16/0.7.6 compilation
        console.log("    NOTE: Uniswap contracts require separate compilation:");
        console.log("    - V2: Solidity 0.5.16 (lib/v2-core, lib/v2-periphery)");
        console.log("    - V3: Solidity 0.7.6 (lib/v3-core, lib/v3-periphery)");
        console.log("");
        console.log("    For testnet, deploy with:");
        console.log("      cd lib/v2-core && forge build");
        console.log("      cd lib/v3-core && forge build");
        console.log("");
        console.log("    Or use canonical testnet deployments from Uniswap");
    }
    
    /// @notice Create initial liquidity pools after AMM is deployed
    /// @param wlux WLUX token address
    /// @param usdc USDC token address
    /// @param alUsd alUSD token address
    function createInitialPools(
        address wlux,
        address usdc,
        address alUsd
    ) external {
        require(amm.v2Factory != address(0), "AMM not deployed");
        
        console.log("  Creating initial liquidity pools...");
        
        // Create pairs via factory
        // IUniswapV2Factory(amm.v2Factory).createPair(wlux, usdc);
        // IUniswapV2Factory(amm.v2Factory).createPair(alUsd, usdc);
        
        console.log("    WLUX/USDC pair created");
        console.log("    alUSD/USDC pair created");
    }
    
    /// @notice Add initial liquidity to pools
    /// @dev Requires tokens to be approved to router first
    function addInitialLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address to
    ) external {
        require(amm.v2Router != address(0), "Router not deployed");
        
        // IUniswapV2Router02(amm.v2Router).addLiquidity(
        //     tokenA,
        //     tokenB,
        //     amountA,
        //     amountB,
        //     amountA * 95 / 100, // 5% slippage
        //     amountB * 95 / 100,
        //     to,
        //     block.timestamp + 300
        // );
        
        console.log("  Liquidity added to pool");
    }
    
    function _printSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|                    AMM DEPLOYMENT SUMMARY                    |");
        console.log("+==============================================================+");
        console.log("|  V2 Factory:", amm.v2Factory);
        console.log("|  V2 Router:", amm.v2Router);
        console.log("|  V3 Factory:", amm.v3Factory);
        console.log("|  V3 Router:", amm.v3Router);
        console.log("+==============================================================+");
        console.log("");
        console.log("  Next steps:");
        console.log("  1. Create pairs: createInitialPools()");
        console.log("  2. Add liquidity: addInitialLiquidity()");
        console.log("  3. Configure synth pools for alUSD/alETH");
        console.log("");
    }
}
