// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {AINative, AINativeFactory} from "../contracts/tokens/AI.sol";
import {AMMV3Factory} from "../contracts/amm/AMMV3Factory.sol";
import {AMMV3Pool} from "../contracts/amm/AMMV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployAI
 * @notice Deploys AI token with V3 one-sided liquidity
 * 
 * TOKENOMICS:
 * - Total Supply: 1,000,000,000 AI (1B)
 * - Initial Liquidity: 100,000,000 AI (10%) → V3 pool
 * - Mining Allocation: 900,000,000 AI (90%) → GPU attestation rewards
 * 
 * LIQUIDITY SETUP (V3 Concentrated):
 * - One-sided LP (AI only, no LUX needed initially)
 * - Price range: $0.01 → $10 per AI
 * - Initial price: $0.01 (LP starts with 100% AI)
 * - As price rises, AI sells into LUX
 * - At $10, LP holds 100% LUX
 * 
 * TICK MATH:
 * - tick = log(price) / log(1.0001)
 * - $0.01: tick ≈ -46054
 * - $10.00: tick ≈ 23027
 */
contract DeployAI is Script {
    // Tick constants for price range
    // Price = 1.0001^tick
    // $0.01 = 1.0001^(-46054) ≈ 0.01
    // $10.00 = 1.0001^(23027) ≈ 10.00
    int24 constant TICK_LOWER = -46080;  // Rounded to tick spacing (60)
    int24 constant TICK_UPPER = 23040;   // Rounded to tick spacing (60)
    
    // sqrtPriceX96 for $0.01 initial price
    // sqrtPrice = sqrt(0.01) * 2^96 = 0.1 * 2^96
    uint160 constant INITIAL_SQRT_PRICE = 7922816251426434000000000000; // ~$0.01
    
    // Fee tier: 0.3% (3000 bps) with tick spacing 60
    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;

    // Deployed contracts
    AINative public aiToken;
    AMMV3Factory public v3Factory;
    AMMV3Pool public aiLuxPool;
    
    // Addresses
    address public deployer;
    address public wlux;
    
    function run() external {
        console.log("=== Deploying AI Token with V3 Liquidity ===");
        console.log("");
        console.log("TOKENOMICS:");
        console.log("  Total Supply:    1,000,000,000 AI (1B)");
        console.log("  Liquidity (10%):   100,000,000 AI");
        console.log("  Mining (90%):      900,000,000 AI");
        console.log("");
        console.log("V3 LIQUIDITY:");
        console.log("  Price Range: $0.01 - $10.00");
        console.log("  Tick Range: %s to %s", TICK_LOWER, TICK_UPPER);
        console.log("  One-sided: 100% AI at start");
        console.log("");
        
        // Get deployer from environment
        string memory mnemonic = vm.envString("LUX_MNEMONIC");
        require(bytes(mnemonic).length > 0, "LUX_MNEMONIC required");
        
        uint256 deployerKey = vm.deriveKey(mnemonic, 0);
        deployer = vm.addr(deployerKey);
        console.log("Deployer:", deployer);
        
        // Get WLUX address (should be deployed already)
        wlux = vm.envOr("WLUX", address(0));
        if (wlux == address(0)) {
            console.log("WARNING: WLUX not set, using placeholder");
            wlux = address(0x1); // Placeholder - set proper WLUX address
        }
        console.log("WLUX:", wlux);
        console.log("");
        
        vm.startBroadcast(deployerKey);
        
        // Phase 1: Deploy AI Token (10% goes to deployer initially)
        _deployAIToken();
        
        // Phase 2: Deploy V3 Factory (if not exists)
        _deployV3Factory();
        
        // Phase 3: Create AI/LUX Pool
        _createPool();
        
        // Phase 4: Add One-Sided Liquidity
        _addLiquidity();
        
        vm.stopBroadcast();
        
        _printSummary();
    }
    
    function _deployAIToken() internal {
        console.log("--- Phase 1: Deploy AI Token ---");
        
        // Deploy AINative with deployer as initial liquidity recipient
        // The 10% (100M AI) will be minted to deployer, then added to V3 pool
        aiToken = new AINative(deployer);
        
        console.log("AI Token deployed:", address(aiToken));
        console.log("  Initial balance:", aiToken.balanceOf(deployer) / 1e18, "AI");
        console.log("");
    }
    
    function _deployV3Factory() internal {
        console.log("--- Phase 2: Deploy V3 Factory ---");
        
        // Check if factory exists at expected address
        address factoryAddr = vm.envOr("V3_FACTORY", address(0));
        
        if (factoryAddr != address(0) && factoryAddr.code.length > 0) {
            v3Factory = AMMV3Factory(factoryAddr);
            console.log("Using existing V3 Factory:", factoryAddr);
        } else {
            v3Factory = new AMMV3Factory();
            console.log("V3 Factory deployed:", address(v3Factory));
        }
        console.log("");
    }
    
    function _createPool() internal {
        console.log("--- Phase 3: Create AI/LUX Pool ---");
        
        // Sort tokens (token0 < token1)
        (address token0, address token1) = address(aiToken) < wlux 
            ? (address(aiToken), wlux) 
            : (wlux, address(aiToken));
        
        // Create pool
        address poolAddr = v3Factory.createPool(token0, token1, FEE);
        aiLuxPool = AMMV3Pool(poolAddr);
        
        console.log("AI/LUX Pool created:", poolAddr);
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  Fee:", FEE, "bps");
        console.log("  Tick Spacing:", TICK_SPACING);
        
        // Initialize price at $0.01
        // This means current tick is below TICK_LOWER, so LP holds 100% AI
        aiLuxPool.initializePrice(INITIAL_SQRT_PRICE);
        console.log("  Initial Price: ~$0.01");
        console.log("");
    }
    
    function _addLiquidity() internal {
        console.log("--- Phase 4: Add One-Sided Liquidity ---");
        
        uint256 aiAmount = aiToken.balanceOf(deployer);
        console.log("AI amount to add:", aiAmount / 1e18, "AI");
        
        // Approve pool to spend AI tokens
        aiToken.approve(address(aiLuxPool), aiAmount);
        
        // Transfer AI to pool first (required by pool contract)
        IERC20(address(aiToken)).transfer(address(aiLuxPool), aiAmount);
        
        // Calculate liquidity amount
        // For one-sided position below current price, we only provide token1 (or token0 depending on ordering)
        // Liquidity = amount / (sqrtPriceUpper - sqrtPriceLower)
        uint128 liquidityAmount = uint128(aiAmount / 1e12); // Simplified calculation
        
        // Mint liquidity position
        (uint256 amount0, uint256 amount1) = aiLuxPool.mint(
            deployer,       // recipient
            TICK_LOWER,     // tickLower ($0.01)
            TICK_UPPER,     // tickUpper ($10.00)
            liquidityAmount // liquidity amount
        );
        
        console.log("Liquidity added:");
        console.log("  Tick Range: [%s, %s]", TICK_LOWER, TICK_UPPER);
        console.log("  Liquidity:", uint256(liquidityAmount));
        console.log("  Amount0:", amount0);
        console.log("  Amount1:", amount1);
        console.log("");
    }
    
    function _printSummary() internal view {
        console.log("");
        console.log("========================================");
        console.log("           DEPLOYMENT SUMMARY           ");
        console.log("========================================");
        console.log("");
        console.log("AI Token:     ", address(aiToken));
        console.log("V3 Factory:   ", address(v3Factory));
        console.log("AI/LUX Pool:  ", address(aiLuxPool));
        console.log("");
        console.log("LIQUIDITY POSITION:");
        console.log("  Price Range:  $0.01 - $10.00");
        console.log("  Direction:    AI -> LUX as price rises");
        console.log("  100M AI in LP band");
        console.log("");
        console.log("MINING REWARDS:");
        console.log("  900M AI available for GPU attestation mining");
        console.log("  Reward rates by privacy level:");
        console.log("    Public (0.25x):      15 AI/hr");
        console.log("    Private (0.5x):      30 AI/hr");
        console.log("    Confidential (1.0x): 60 AI/hr");
        console.log("    Sovereign (1.5x):    90 AI/hr");
        console.log("");
        console.log("========================================");
    }
}
