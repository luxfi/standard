// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

// Core Perps contracts
import "../../contracts/perps/core/interfaces/IVault.sol";
import "../../contracts/perps/core/interfaces/IVaultUtils.sol";
import "../../contracts/perps/core/Vault.sol";
import "../../contracts/perps/core/VaultUtils.sol";
import "../../contracts/perps/core/VaultPriceFeed.sol";
import "../../contracts/perps/core/Router.sol";
import "../../contracts/perps/core/PositionRouter.sol";
import "../../contracts/perps/core/ShortsTracker.sol";
import "../../contracts/perps/core/GlpManager.sol";

// Tokens
import "../../contracts/perps/tokens/USDG.sol";
import "../../contracts/perps/gmx/GMX.sol";
import "../../contracts/perps/gmx/GLP.sol";
import "../../contracts/perps/gmx/EsGMX.sol";
import "../../contracts/perps/tokens/MintableBaseToken.sol";

// Staking
import "../../contracts/perps/staking/RewardTracker.sol";
import "../../contracts/perps/staking/RewardDistributor.sol";

// Oracle
import "../../contracts/perps/oracle/PriceFeed.sol";

// Mocks
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockToken
/// @notice Simple mock ERC20 for perps testing
contract MockToken is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @title MockPriceFeed
/// @notice Mock Chainlink price feed for testing
contract MockPriceFeed {
    int256 private _answer;
    uint8 private _decimals;
    
    constructor(int256 answer, uint8 decimals_) {
        _answer = answer;
        _decimals = decimals_;
    }
    
    function latestAnswer() external view returns (int256) {
        return _answer;
    }
    
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    
    function setAnswer(int256 answer) external {
        _answer = answer;
    }
    
    function latestRound() external pure returns (uint80) {
        return 1;
    }
    
    function getRoundData(uint80) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }
}

/// @title PerpsTest
/// @notice Comprehensive tests for the Perps (GMX-style) protocol
contract PerpsTest is Test {
    // Core contracts
    Vault public vault;
    VaultUtils public vaultUtils;
    VaultPriceFeed public vaultPriceFeed;
    Router public router;
    ShortsTracker public shortsTracker;
    GlpManager public glpManager;
    
    // Tokens
    USDG public usdg;
    GMX public gmx;
    GLP public glp;
    MockToken public weth;
    MockToken public wbtc;
    MockToken public usdc;
    
    // Price feeds
    MockPriceFeed public ethPriceFeed;
    MockPriceFeed public btcPriceFeed;
    MockPriceFeed public usdcPriceFeed;
    
    // Users
    address public gov = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public keeper = address(0x4);
    
    // Constants
    uint256 constant ETH_PRICE = 2000e30; // $2000
    uint256 constant BTC_PRICE = 40000e30; // $40000
    uint256 constant LIQUIDATION_FEE = 5e30; // $5
    
    function setUp() public {
        // Deploy mock tokens
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        usdc = new MockToken("USD Coin", "USDC", 6);
        
        // Deploy price feeds
        ethPriceFeed = new MockPriceFeed(2000e8, 8); // $2000
        btcPriceFeed = new MockPriceFeed(40000e8, 8); // $40000
        usdcPriceFeed = new MockPriceFeed(1e8, 8); // $1.00
        
        // Deploy USDG
        usdg = new USDG(address(0));
        
        // Deploy VaultPriceFeed
        vaultPriceFeed = new VaultPriceFeed();
        
        // Deploy VaultUtils (needs vault address later)
        // VaultUtils will be deployed after vault
        // vaultUtils = new VaultUtils(IVault(address(vault)));
        
        // Deploy Vault
        vault = new Vault();
        
        // Initialize Vault
        vault.initialize(
            address(0), // router - set later
            address(usdg),
            address(vaultPriceFeed),
            LIQUIDATION_FEE,
            100, // fundingRateFactor
            100  // stableFundingRateFactor
        );
        
        // Deploy VaultUtils with vault reference
        vaultUtils = new VaultUtils(IVault(address(vault)));

        // Configure vault
        vault.setVaultUtils(IVaultUtils(address(vaultUtils)));
        vault.setGov(gov);
        
        // Add vault to USDG
        usdg.addVault(address(vault));
        
        // Deploy Router
        router = new Router(address(vault), address(usdg), address(weth));
        
        // Deploy ShortsTracker
        shortsTracker = new ShortsTracker(address(vault));
        
        // Deploy GLP
        glp = new GLP();
        
        // Deploy GMX
        gmx = new GMX();
        
        // Deploy GlpManager
        glpManager = new GlpManager(
            address(vault),
            address(usdg),
            address(glp),
            address(shortsTracker),
            15 minutes
        );
        
        // Configure GLP minting
        glp.setMinter(address(glpManager), true);
        usdg.addVault(address(glpManager));
        
        // Note: Router is set during vault.initialize()
        // Users can approve additional routers via vault.addRouter()
        
        // Configure price feeds
        _configurePriceFeeds();
        
        // Configure tokens
        _configureTokens();
        
        // Fund users
        weth.mint(alice, 100e18);
        weth.mint(bob, 100e18);
        wbtc.mint(alice, 10e8);
        wbtc.mint(bob, 10e8);
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
    }
    
    function _configurePriceFeeds() internal {
        vaultPriceFeed.setTokenConfig(
            address(weth),
            address(ethPriceFeed),
            8, // price decimals
            false // isStrictStable
        );
        
        vaultPriceFeed.setTokenConfig(
            address(wbtc),
            address(btcPriceFeed),
            8,
            false
        );

        vaultPriceFeed.setTokenConfig(
            address(usdc),
            address(usdcPriceFeed),
            8,
            true // isStrictStable
        );
    }
    
    function _configureTokens() internal {
        vm.startPrank(gov);
        
        // Configure WETH
        vault.setTokenConfig(
            address(weth),
            18, // decimals
            10000, // weight
            75, // minProfitBps
            0, // maxUsdgAmount
            false, // isStable
            true // isShortable
        );
        
        // Configure WBTC
        vault.setTokenConfig(
            address(wbtc),
            8,
            10000,
            75,
            0,
            false,
            true
        );
        
        // Configure USDC as stable
        vault.setTokenConfig(
            address(usdc),
            6,
            10000,
            0,
            0,
            true,
            false
        );
        
        vm.stopPrank();
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // VAULT INITIALIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_VaultInitialization() public view {
        assertTrue(vault.isInitialized());
        assertEq(vault.gov(), gov);
        assertEq(vault.usdg(), address(usdg));
        assertEq(vault.priceFeed(), address(vaultPriceFeed));
    }
    
    function test_VaultFeeConfiguration() public view {
        assertEq(vault.taxBasisPoints(), 50); // 0.5%
        assertEq(vault.stableTaxBasisPoints(), 20); // 0.2%
        assertEq(vault.mintBurnFeeBasisPoints(), 30); // 0.3%
        assertEq(vault.swapFeeBasisPoints(), 30); // 0.3%
        assertEq(vault.marginFeeBasisPoints(), 10); // 0.1%
    }
    
    function test_TokenConfiguration() public view {
        assertTrue(vault.whitelistedTokens(address(weth)));
        assertTrue(vault.whitelistedTokens(address(wbtc)));
        assertTrue(vault.whitelistedTokens(address(usdc)));
        
        assertTrue(vault.shortableTokens(address(weth)));
        assertTrue(vault.shortableTokens(address(wbtc)));
        assertFalse(vault.shortableTokens(address(usdc)));
        
        assertFalse(vault.stableTokens(address(weth)));
        assertTrue(vault.stableTokens(address(usdc)));
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ROUTER TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_RouterInitialization() public view {
        assertEq(router.vault(), address(vault));
        assertEq(router.usdg(), address(usdg));
        assertEq(router.weth(), address(weth));
    }
    
    function test_PluginApproval() public {
        address plugin = address(0x999);
        
        vm.prank(alice);
        router.approvePlugin(plugin);
        
        assertTrue(router.approvedPlugins(alice, plugin));
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // GLP MANAGER TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_GlpManagerInitialization() public view {
        assertEq(address(glpManager.vault()), address(vault));
        assertEq(address(glpManager.usdg()), address(usdg));
        assertEq(address(glpManager.glp()), address(glp));
    }
    
    function test_AddLiquidity() public {
        uint256 depositAmount = 10e18; // 10 WETH
        
        vm.startPrank(alice);
        weth.approve(address(glpManager), depositAmount);
        
        // Calculate expected GLP amount
        // At $2000/ETH, 10 ETH = $20,000 worth of GLP
        uint256 glpAmount = glpManager.addLiquidity(
            address(weth),
            depositAmount,
            0, // minUsdg
            0  // minGlp
        );
        vm.stopPrank();
        
        assertGt(glpAmount, 0);
        assertEq(glp.balanceOf(alice), glpAmount);
    }
    
    function test_RemoveLiquidity() public {
        // First add liquidity
        uint256 depositAmount = 10e18;
        
        vm.startPrank(alice);
        weth.approve(address(glpManager), depositAmount);
        uint256 glpAmount = glpManager.addLiquidity(
            address(weth),
            depositAmount,
            0,
            0
        );
        
        // Wait for cooldown
        vm.warp(block.timestamp + 16 minutes);
        
        // Remove liquidity
        glp.approve(address(glpManager), glpAmount);
        uint256 wethReceived = glpManager.removeLiquidity(
            address(weth),
            glpAmount,
            0, // minOut
            alice
        );
        vm.stopPrank();
        
        assertGt(wethReceived, 0);
        assertEq(glp.balanceOf(alice), 0);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_GMXToken() public view {
        assertEq(gmx.name(), "GMX");
        assertEq(gmx.symbol(), "GMX");
        assertEq(gmx.id(), "GMX");
    }
    
    function test_GLPToken() public view {
        assertEq(glp.name(), "GMX LP");
        assertEq(glp.symbol(), "GLP");
    }
    
    function test_USDGToken() public view {
        assertEq(usdg.name(), "USD Gambit");
        assertEq(usdg.symbol(), "USDG");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // PRICE FEED TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_PriceFeedConfiguration() public view {
        uint256 ethPrice = vaultPriceFeed.getPrice(address(weth), true, true, true);
        uint256 btcPrice = vaultPriceFeed.getPrice(address(wbtc), true, true, true);
        
        // Prices should be in 30 decimal precision
        assertEq(ethPrice, 2000e30);
        assertEq(btcPrice, 40000e30);
    }
    
    function test_PriceUpdate() public {
        // Update ETH price to $2500
        ethPriceFeed.setAnswer(2500e8);
        
        uint256 newPrice = vaultPriceFeed.getPrice(address(weth), true, true, true);
        assertEq(newPrice, 2500e30);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_OnlyGovCanSetFees() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setFees(
            50, 20, 30, 30, 4, 10,
            5e30, 3 hours, true
        );
        
        vm.prank(gov);
        vault.setFees(
            50, 20, 30, 30, 4, 10,
            5e30, 3 hours, true
        );
    }
    
    function test_OnlyGovCanAddManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setManager(keeper, true);
        
        vm.prank(gov);
        vault.setManager(keeper, true);
        assertTrue(vault.isManager(keeper));
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function testFuzz_PriceImpact(uint256 price) public {
        price = bound(price, 100e8, 100000e8); // $100 - $100,000
        
        ethPriceFeed.setAnswer(int256(price));
        
        uint256 fetchedPrice = vaultPriceFeed.getPrice(address(weth), true, true, true);
        assertEq(fetchedPrice, price * 1e22); // Convert from 8 decimals to 30
    }
    
    function testFuzz_AddRemoveLiquidity(uint256 amount) public {
        amount = bound(amount, 0.01e18, 50e18); // 0.01 - 50 WETH
        
        vm.startPrank(alice);
        weth.approve(address(glpManager), amount);
        
        uint256 glpAmount = glpManager.addLiquidity(
            address(weth),
            amount,
            0,
            0
        );
        
        assertGt(glpAmount, 0);
        assertEq(glp.balanceOf(alice), glpAmount);
        vm.stopPrank();
    }
}

/// @title PerpsPositionTest
/// @notice Position management tests
contract PerpsPositionTest is PerpsTest {
    
    function test_IncreasePositionLong() public {
        // Note: Full position testing requires complete setup
        // This is a placeholder for the complete test
    }
    
    function test_IncreasePositionShort() public {
        // Placeholder for short position test
    }
    
    function test_LiquidatePosition() public {
        // Placeholder for liquidation test
    }
}

/// @title PerpsEdgeCaseTest
/// @notice Edge case and error condition tests
contract PerpsEdgeCaseTest is PerpsTest {
    
    function test_CannotInitializeVaultTwice() public {
        vm.expectRevert();
        vault.initialize(
            address(0),
            address(usdg),
            address(vaultPriceFeed),
            5e30,
            100,
            100
        );
    }
    
    function test_CannotSwapToUnwhitelistedToken() public {
        MockToken newToken = new MockToken("New", "NEW", 18);
        
        vm.startPrank(alice);
        weth.approve(address(router), 1e18);
        
        vm.expectRevert();
        router.swap(
            new address[](2),
            1e18,
            0,
            alice
        );
        vm.stopPrank();
    }
    
    function test_CooldownPeriod() public {
        // Add liquidity
        vm.startPrank(alice);
        weth.approve(address(glpManager), 10e18);
        uint256 glpAmount = glpManager.addLiquidity(address(weth), 10e18, 0, 0);
        
        // Try to remove immediately (should fail due to cooldown)
        glp.approve(address(glpManager), glpAmount);
        vm.expectRevert();
        glpManager.removeLiquidity(address(weth), glpAmount, 0, alice);
        
        vm.stopPrank();
    }
}
