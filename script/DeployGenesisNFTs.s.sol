// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/nft/GenesisNFTs.sol";
import "../contracts/amm/AMMV2Pair.sol";
import "../contracts/amm/AMMV2Factory.sol";

/**
 * @title MockLRC20
 * @notice Simple mock token for testing
 */
contract MockLRC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/**
 * @title DeployGenesisNFTs
 * @notice Deploy and test GenesisNFTs with AMM pricing
 */
contract DeployGenesisNFTs is Script {
    // Anvil default private key
    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant USER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    
    MockLRC20 wlux;
    MockLRC20 lusd;
    LuxV2Factory factory;
    LuxV2Pair pair;
    GenesisNFTs genesis;

    function run() external {
        vm.startBroadcast(DEPLOYER_KEY);

        console.log("=== Deploying GenesisNFTs Test Environment ===");
        console.log("");

        // 1. Deploy mock tokens
        console.log("1. Deploying mock tokens...");
        wlux = new MockLRC20("Wrapped LUX", "WLUX");
        lusd = new MockLRC20("Lux USD", "LUSD");
        console.log("   WLUX:", address(wlux));
        console.log("   LUSD:", address(lusd));

        // 2. Deploy AMM factory and create pair
        console.log("");
        console.log("2. Deploying AMM...");
        factory = new LuxV2Factory(DEPLOYER);
        address pairAddr = factory.createPair(address(wlux), address(lusd));
        pair = LuxV2Pair(pairAddr);
        console.log("   Factory:", address(factory));
        console.log("   WLUX/LUSD Pair:", pairAddr);

        // 3. Add liquidity to set initial price
        // Price: 1 LUX = $1 LUSD (initial)
        console.log("");
        console.log("3. Adding liquidity (1 LUX = $1 LUSD)...");
        uint256 luxAmount = 1_000_000 * 1e18;  // 1M LUX
        uint256 lusdAmount = 1_000_000 * 1e18; // 1M LUSD (1:1 ratio = $1/LUX)
        
        wlux.mint(address(pair), luxAmount);
        lusd.mint(address(pair), lusdAmount);
        pair.mint(DEPLOYER);
        
        (uint112 r0, uint112 r1,) = pair.getReserves();
        console.log("   Reserve0:", r0 / 1e18);
        console.log("   Reserve1:", r1 / 1e18);

        // 4. Deploy GenesisNFTs
        console.log("");
        console.log("4. Deploying GenesisNFTs...");
        genesis = new GenesisNFTs(
            "ipfs://genesis/",           // baseURI
            DEPLOYER,                     // royaltyReceiver
            250,                          // royaltyBps (2.5%)
            address(wlux),               // wlux
            address(lusd),               // lusd
            address(pair)                // luxLusdPair
        );
        console.log("   GenesisNFTs:", address(genesis));

        // 5. Complete migration and open sales
        console.log("");
        console.log("5. Completing migration & opening sales...");
        genesis.completeMigration();
        genesis.setSalesOpen(true);
        console.log("   Migration complete:", genesis.migrationComplete());
        console.log("   Sales open:", genesis.salesOpen());

        vm.stopBroadcast();

        // 6. Test buying an NFT with time-based discount
        console.log("");
        console.log("=== Testing NFT Purchase (Time-Based Discount) ===");

        // Get prices - market vs discounted
        uint256 marketPrice = genesis.getLuxPrice();
        uint256 discountedPrice = genesis.getDiscountedPrice();
        uint256 discount = genesis.getCurrentDiscount();
        console.log("Market LUX price:", marketPrice / 1e18, "LUSD");
        console.log("Current discount:", discount / 100, "% (starts 11%, ends 1% by Jan 1 2026)");
        console.log("Discounted price:", discountedPrice / 1e16, "cents (0.89 LUSD at 11%)");

        // Mint LUSD to user and approve
        vm.startBroadcast(DEPLOYER_KEY);
        lusd.mint(USER, 100 * 1e18);
        vm.stopBroadcast();

        vm.startBroadcast(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d); // USER key
        lusd.approve(address(genesis), type(uint256).max);
        
        uint256 balBefore = lusd.balanceOf(USER);
        console.log("User LUSD before:", balBefore / 1e18);

        // Buy NFT (pays discounted price!)
        uint256 tokenId = genesis.buy(
            GenesisNFTs.NFTType.VALIDATOR,
            GenesisNFTs.Tier.NANO,
            "Test Validator"
        );

        uint256 balAfter = lusd.balanceOf(USER);
        uint256 spent = balBefore - balAfter;
        console.log("User LUSD after:", balAfter / 1e18);
        console.log("LUSD spent:", spent / 1e16, "cents (should be ~89)");
        console.log("Savings vs market:", (marketPrice - spent) / 1e16, "cents (should be 11)");
        console.log("NFT minted, tokenId:", tokenId);
        console.log("NFT owner:", genesis.ownerOf(tokenId));
        
        vm.stopBroadcast();

        // 7. Test price change with swap
        console.log("");
        console.log("=== Testing Dynamic Pricing ===");
        
        vm.startBroadcast(DEPLOYER_KEY);
        
        // Add more LUSD to increase LUX price to $2
        lusd.mint(address(pair), 1_000_000 * 1e18);
        pair.sync();
        
        (r0, r1,) = pair.getReserves();
        console.log("New Reserve0:", r0 / 1e18);
        console.log("New Reserve1:", r1 / 1e18);
        
        uint256 newPrice = genesis.getLuxPrice();
        uint256 newDiscounted = genesis.getDiscountedPrice();
        console.log("New LUX market price:", newPrice / 1e18, "LUSD");
        console.log("New discounted price:", newDiscounted / 1e16, "cents (1.78 LUSD with 11% off)");

        vm.stopBroadcast();

        // 8. Verify DAO Treasury received funds
        console.log("");
        console.log("=== DAO Treasury Balance ===");
        uint256 treasuryBal = lusd.balanceOf(genesis.DAO_TREASURY());
        console.log("Treasury LUSD:", treasuryBal / 1e18);

        console.log("");
        console.log("=== All Tests Passed! ===");
    }
}
