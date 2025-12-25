// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../contracts/nft/GenesisNFTs.sol";

contract MockAMMPair {
    address public token0;
    address public token1;
    uint112 public reserve0 = 1_000_000e18;
    uint112 public reserve1 = 1_000_000e18;
    
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
    
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }
}

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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

contract GenesisNFTsDiscountTest is Test {
    GenesisNFTs public genesis;
    MockToken public wlux;
    MockToken public lusd;
    MockAMMPair public pair;
    
    address deployer = address(1);
    address buyer = address(2);
    
    function setUp() public {
        vm.startPrank(deployer);
        
        wlux = new MockToken();
        lusd = new MockToken();
        pair = new MockAMMPair(address(wlux), address(lusd));
        
        genesis = new GenesisNFTs(
            "ipfs://genesis/",
            deployer,
            250,
            address(wlux),
            address(lusd),
            address(pair)
        );
        
        genesis.completeMigration();
        genesis.setSalesOpen(true);
        
        vm.stopPrank();
    }
    
    function testDiscountConstants() public view {
        assertEq(genesis.START_DISCOUNT_BPS(), 1100, "Start discount should be 11%");
        assertEq(genesis.END_DISCOUNT_BPS(), 100, "End discount should be 1%");
        assertEq(genesis.DISCOUNT_END_TIMESTAMP(), 1735689600, "End timestamp should be Jan 1, 2026");
    }
    
    function testInitialDiscountIs11Percent() public view {
        uint256 currentDiscount = genesis.getCurrentDiscount();
        assertEq(currentDiscount, 1100, "Initial discount should be 11%");
    }
    
    function testDiscountedPriceIs89PercentOfMarket() public view {
        uint256 marketPrice = genesis.getLuxPrice();
        uint256 discountedPrice = genesis.getDiscountedPrice();
        
        // With 11% discount, buyer pays 89%
        uint256 expectedDiscounted = (marketPrice * 8900) / 10000;
        assertEq(discountedPrice, expectedDiscounted, "Discounted price should be 89% of market");
    }
    
    function testDiscountDecreasesOverTime() public {
        uint256 initialDiscount = genesis.getCurrentDiscount();
        
        // Warp 6 months into the future
        vm.warp(block.timestamp + 180 days);
        
        uint256 laterDiscount = genesis.getCurrentDiscount();
        assertLt(laterDiscount, initialDiscount, "Discount should decrease over time");
        assertGt(laterDiscount, genesis.END_DISCOUNT_BPS(), "Discount should still be above end discount");
    }
    
    function testDiscountBottomsAtEndTimestamp() public {
        // Warp past end date (Jan 1, 2026)
        vm.warp(genesis.DISCOUNT_END_TIMESTAMP() + 1);
        
        uint256 discount = genesis.getCurrentDiscount();
        assertEq(discount, genesis.END_DISCOUNT_BPS(), "Discount should be at minimum (1%)");
    }
    
    function testBuyUsesDiscountedPrice() public {
        lusd.mint(buyer, 10e18);
        
        vm.startPrank(buyer);
        lusd.approve(address(genesis), type(uint256).max);
        
        uint256 balBefore = lusd.balanceOf(buyer);
        uint256 expectedPrice = genesis.getDiscountedPrice();
        
        genesis.buy(
            GenesisNFTs.NFTType.VALIDATOR,
            GenesisNFTs.Tier.NANO,
            "Test NFT",
            type(uint256).max // maxPrice - no slippage limit for tests
        );
        
        uint256 balAfter = lusd.balanceOf(buyer);
        uint256 spent = balBefore - balAfter;
        
        assertEq(spent, expectedPrice, "Should pay discounted price");
        vm.stopPrank();
    }
}
