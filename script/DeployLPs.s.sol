// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Interfaces
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @title DeployLPs - Synth/Bridge Token Liquidity Pairs
/// @notice Deploy and initialize LP pairs for synth tokens paired with bridge tokens
/// @dev Creates: WLUX/xLUX, LETH/xETH, LBTC/xBTC, LUSD/xUSD
contract DeployLPs is Script, DeployConfig {

    struct LPDeployment {
        // Core pairs
        address wluxXlux;    // WLUX/xLUX
        address lethXeth;    // LETH/xETH
        address lbtcXbtc;    // LBTC/xBTC
        address lusdXusd;    // LUSD/xUSD
        // Additional pairs
        address wluxLusd;    // WLUX/LUSD (main trading pair)
        address lethLusd;    // LETH/LUSD
        address lbtcLusd;    // LBTC/LUSD
    }

    struct TokenAddresses {
        // Wrapped/Native
        address wlux;
        // Bridge tokens (L*)
        address leth;
        address lbtc;
        address lusd;
        // Synth tokens (x*)
        address xlux;
        address xeth;
        address xbtc;
        address xusd;
    }

    LPDeployment public lps;
    TokenAddresses public tokens;
    address public factory;
    address public router;

    /// @notice Main deployment - create all LP pairs
    function run() public {
        _initConfigs();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|           LUX SYNTH LP PAIRS DEPLOYMENT                      |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("+==============================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Load token addresses from environment or use defaults
        _loadTokenAddresses();
        _loadAMMAddresses();

        // Create all pairs
        _createSynthPairs();

        vm.stopBroadcast();

        _printSummary();
    }

    /// @notice Run with specific addresses (for integration with DeployAll)
    function runWithAddresses(
        address _factory,
        address _router,
        TokenAddresses memory _tokens
    ) public returns (LPDeployment memory) {
        factory = _factory;
        router = _router;
        tokens = _tokens;

        console.log("  Creating synth LP pairs...");
        _createSynthPairs();

        return lps;
    }

    /// @notice Load token addresses from environment
    function _loadTokenAddresses() internal {
        // Try environment first, then use deployed addresses
        tokens.wlux = vm.envOr("WLUX", address(0));
        tokens.leth = vm.envOr("LETH", address(0));
        tokens.lbtc = vm.envOr("LBTC", address(0));
        tokens.lusd = vm.envOr("LUSD", address(0));
        tokens.xlux = vm.envOr("XLUX", address(0));
        tokens.xeth = vm.envOr("XETH", address(0));
        tokens.xbtc = vm.envOr("XBTC", address(0));
        tokens.xusd = vm.envOr("XUSD", address(0));

        require(tokens.wlux != address(0), "WLUX address required");
        require(tokens.lusd != address(0), "LUSD address required");

        console.log("  Token addresses loaded:");
        console.log("    WLUX:", tokens.wlux);
        console.log("    LETH:", tokens.leth);
        console.log("    LBTC:", tokens.lbtc);
        console.log("    LUSD:", tokens.lusd);
        console.log("    xLUX:", tokens.xlux);
        console.log("    xETH:", tokens.xeth);
        console.log("    xBTC:", tokens.xbtc);
        console.log("    xUSD:", tokens.xusd);
    }

    /// @notice Load AMM addresses
    function _loadAMMAddresses() internal {
        ChainConfig memory config = getConfig();
        
        factory = vm.envOr("UNI_V2_FACTORY", config.uniV2Factory);
        router = vm.envOr("UNI_V2_ROUTER", config.uniV2Router);

        require(factory != address(0), "V2 Factory address required");
        require(router != address(0), "V2 Router address required");

        console.log("  AMM addresses:");
        console.log("    Factory:", factory);
        console.log("    Router:", router);
    }

    /// @notice Create all synth LP pairs
    function _createSynthPairs() internal {
        console.log("");
        console.log("  === Creating Synth LP Pairs ===");

        // 1. WLUX/xLUX - Native LUX paired with Synthetic LUX
        if (tokens.wlux != address(0) && tokens.xlux != address(0)) {
            lps.wluxXlux = _createPairIfNotExists(tokens.wlux, tokens.xlux, "WLUX/xLUX");
        }

        // 2. LETH/xETH - Bridged ETH paired with Synthetic ETH
        if (tokens.leth != address(0) && tokens.xeth != address(0)) {
            lps.lethXeth = _createPairIfNotExists(tokens.leth, tokens.xeth, "LETH/xETH");
        }

        // 3. LBTC/xBTC - Bridged BTC paired with Synthetic BTC
        if (tokens.lbtc != address(0) && tokens.xbtc != address(0)) {
            lps.lbtcXbtc = _createPairIfNotExists(tokens.lbtc, tokens.xbtc, "LBTC/xBTC");
        }

        // 4. LUSD/xUSD - Native stablecoin paired with Synthetic USD
        if (tokens.lusd != address(0) && tokens.xusd != address(0)) {
            lps.lusdXusd = _createPairIfNotExists(tokens.lusd, tokens.xusd, "LUSD/xUSD");
        }

        console.log("");
        console.log("  === Creating Trading Pairs ===");

        // 5. WLUX/LUSD - Main trading pair
        if (tokens.wlux != address(0) && tokens.lusd != address(0)) {
            lps.wluxLusd = _createPairIfNotExists(tokens.wlux, tokens.lusd, "WLUX/LUSD");
        }

        // 6. LETH/LUSD - ETH/USD trading
        if (tokens.leth != address(0) && tokens.lusd != address(0)) {
            lps.lethLusd = _createPairIfNotExists(tokens.leth, tokens.lusd, "LETH/LUSD");
        }

        // 7. LBTC/LUSD - BTC/USD trading
        if (tokens.lbtc != address(0) && tokens.lusd != address(0)) {
            lps.lbtcLusd = _createPairIfNotExists(tokens.lbtc, tokens.lusd, "LBTC/LUSD");
        }
    }

    /// @notice Create pair if it doesn't exist
    function _createPairIfNotExists(
        address tokenA,
        address tokenB,
        string memory name
    ) internal returns (address pair) {
        // Check if pair already exists
        pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        
        if (pair == address(0)) {
            pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
            console.log("    Created", name, ":", pair);
        } else {
            console.log("    Exists ", name, ":", pair);
        }
    }

    /// @notice Add initial liquidity to a pair
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param amountA Amount of tokenA
    /// @param amountB Amount of tokenB
    /// @param to Recipient of LP tokens
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address to
    ) public returns (uint256 liquidity) {
        require(router != address(0), "Router not set");

        // Approve router
        IERC20(tokenA).approve(router, amountA);
        IERC20(tokenB).approve(router, amountB);

        // Add liquidity with 5% slippage tolerance
        (, , liquidity) = IUniswapV2Router02(router).addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            amountA * 95 / 100,
            amountB * 95 / 100,
            to,
            block.timestamp + 300
        );

        console.log("  Added liquidity:", liquidity);
    }

    /// @notice Seed initial liquidity for all pairs (for testnet)
    /// @param seedAmount Base amount for seeding (e.g., 1000e18 for 1000 tokens)
    function seedAllPairs(uint256 seedAmount) external {
        console.log("  Seeding LP pairs with initial liquidity...");

        // For testnet, mint tokens and add liquidity
        // Assumes caller has minting permissions or tokens

        if (lps.wluxXlux != address(0)) {
            _seedPair(tokens.wlux, tokens.xlux, seedAmount, seedAmount);
        }
        if (lps.lethXeth != address(0)) {
            _seedPair(tokens.leth, tokens.xeth, seedAmount, seedAmount);
        }
        if (lps.lbtcXbtc != address(0)) {
            // BTC amounts are smaller (8 decimals typically, but we use 18)
            _seedPair(tokens.lbtc, tokens.xbtc, seedAmount / 10, seedAmount / 10);
        }
        if (lps.lusdXusd != address(0)) {
            _seedPair(tokens.lusd, tokens.xusd, seedAmount, seedAmount);
        }
    }

    /// @notice Seed a single pair with liquidity
    function _seedPair(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal {
        // Transfer tokens to this contract (assumes caller has them)
        IERC20(tokenA).approve(router, amountA);
        IERC20(tokenB).approve(router, amountB);

        IUniswapV2Router02(router).addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            amountA * 95 / 100,
            amountB * 95 / 100,
            msg.sender,
            block.timestamp + 300
        );
    }

    function _printSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|                  LP PAIRS DEPLOYMENT SUMMARY                 |");
        console.log("+==============================================================+");
        console.log("");
        console.log("  Synth Pairs (1:1 peg arbitrage):");
        console.log("    WLUX/xLUX:", lps.wluxXlux);
        console.log("    LETH/xETH:", lps.lethXeth);
        console.log("    LBTC/xBTC:", lps.lbtcXbtc);
        console.log("    LUSD/xUSD:", lps.lusdXusd);
        console.log("");
        console.log("  Trading Pairs:");
        console.log("    WLUX/LUSD:", lps.wluxLusd);
        console.log("    LETH/LUSD:", lps.lethLusd);
        console.log("    LBTC/LUSD:", lps.lbtcLusd);
        console.log("");
        console.log("+==============================================================+");
        console.log("");
        console.log("  LP Pair Use Cases:");
        console.log("  - WLUX/xLUX: Arbitrage when xLUX depegs from LUX");
        console.log("  - LETH/xETH: Arbitrage when xETH depegs from ETH");
        console.log("  - LBTC/xBTC: Arbitrage when xBTC depegs from BTC");
        console.log("  - LUSD/xUSD: Stablecoin arbitrage (both pegged to $1)");
        console.log("");
        console.log("  Next steps:");
        console.log("  1. Add initial liquidity via seedAllPairs() or addLiquidity()");
        console.log("  2. Configure oracle price feeds for synth pairs");
        console.log("  3. Enable synth minting in AlchemistV2");
        console.log("");
    }

    /// @notice Get all LP pair addresses
    function getLPAddresses() external view returns (LPDeployment memory) {
        return lps;
    }

    /// @notice Get all token addresses
    function getTokenAddresses() external view returns (TokenAddresses memory) {
        return tokens;
    }
}
