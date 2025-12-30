// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// Core tokens - Lux native
import {WLUX} from "../../contracts/tokens/WLUX.sol";
import {LuxUSD} from "../../contracts/liquid/tokens/LUSD.sol";
import {ILRC20} from "../../contracts/tokens/interfaces/ILRC20.sol";

// ═══════════════════════════════════════════════════════════════════════════
// MOCK AMM (Uniswap V2-style for 0.8.x compatibility)
// ═══════════════════════════════════════════════════════════════════════════

contract MockV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new MockV2Pair{salt: salt}(token0, token1));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}

contract MockV2Pair {
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    uint256 private constant MINIMUM_LIQUIDITY = 1000;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function mint(address to) external returns (uint256 liquidity) {
        uint256 balance0 = ILRC20(token0).balanceOf(address(this));
        uint256 balance1 = ILRC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        if (totalSupply == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalSupply = MINIMUM_LIQUIDITY;
            balanceOf[address(0)] = MINIMUM_LIQUIDITY;
        } else {
            liquidity = min(
                (amount0 * totalSupply) / reserve0,
                (amount1 * totalSupply) / reserve1
            );
        }

        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        balanceOf[to] += liquidity;
        totalSupply += liquidity;

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < reserve0 && amount1Out < reserve1, "INSUFFICIENT_LIQUIDITY");

        if (amount0Out > 0) ILRC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) ILRC20(token1).transfer(to, amount1Out);

        uint256 balance0 = ILRC20(token0).balanceOf(address(this));
        uint256 balance1 = ILRC20(token1).balanceOf(address(this));

        // Simplified K check with 0.3% fee
        require(balance0 * balance1 >= uint256(reserve0) * uint256(reserve1) * 997 / 1000, "K");

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) { z = x; x = (y / x + x) / 2; }
        } else if (y != 0) { z = 1; }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MOCK SYNTH (simplified alUSD for testing without proxy)
// ═══════════════════════════════════════════════════════════════════════════

contract MockAlUSD {
    string public constant name = "Alchemic USD";
    string public constant symbol = "alUSD";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public minters;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() { owner = msg.sender; minters[msg.sender] = true; }

    function setMinter(address minter, bool status) external {
        require(msg.sender == owner, "NOT_OWNER");
        minters[minter] = status;
    }

    function mint(address to, uint256 amount) external {
        require(minters[msg.sender], "NOT_MINTER");
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title LuxFullStackIntegration
 * @notice End-to-end integration test for the Lux DeFi stack
 * @dev Tests: Tokens → AMM (V2 LPs, Swaps) → Synth swaps
 * 
 * Native Lux tokens used:
 * - WLUX: Wrapped LUX (native gas token wrapper)
 * - LUSD: Lux Dollar (native stablecoin)
 * - alUSD: Alchemic USD (synthetic dollar)
 */
contract LuxFullStackIntegration is Test {
    // ═══════════════════════════════════════════════════════════════════════
    // CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════

    // Core tokens
    WLUX public wlux;
    LuxUSD public lusd;
    MockAlUSD public alUSD;

    // AMM
    MockV2Factory public factory;
    MockV2Pair public wluxLusdPair;
    MockV2Pair public alUsdLusdPair;

    // Test accounts
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public treasury = makeAddr("treasury");

    // ═══════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════

    function setUp() public {
        console.log("=== LUX FULL STACK INTEGRATION TEST ===");

        // Deploy core tokens
        wlux = new WLUX();
        lusd = new LuxUSD();
        alUSD = new MockAlUSD();

        console.log("WLUX:", address(wlux));
        console.log("LUSD:", address(lusd));
        console.log("alUSD:", address(alUSD));

        // Deploy AMM
        factory = new MockV2Factory();

        // Create pairs
        address wluxLusdAddr = factory.createPair(address(wlux), address(lusd));
        wluxLusdPair = MockV2Pair(wluxLusdAddr);

        address alUsdLusdAddr = factory.createPair(address(alUSD), address(lusd));
        alUsdLusdPair = MockV2Pair(alUsdLusdAddr);

        console.log("WLUX/LUSD Pair:", address(wluxLusdPair));
        console.log("alUSD/LUSD Pair:", address(alUsdLusdPair));

        // Seed liquidity
        _seedLiquidity();

        console.log("=== SETUP COMPLETE ===");
    }

    function _seedLiquidity() internal {
        // Mint tokens for liquidity
        // WLUX: wrap native LUX
        vm.deal(treasury, 1_000_000 ether);
        vm.prank(treasury);
        wlux.deposit{value: 1_000_000 ether}();

        // LUSD: mint stablecoin (1 LUSD = $1, 18 decimals)
        lusd.mint(treasury, 1_000_000_000e18); // 1B LUSD

        // alUSD: mint synthetic
        alUSD.mint(treasury, 1_000_000_000e18); // 1B alUSD

        // Add liquidity to WLUX/LUSD (1 WLUX = 1 LUSD initially)
        vm.startPrank(treasury);

        wlux.transfer(address(wluxLusdPair), 100_000e18);
        lusd.transfer(address(wluxLusdPair), 100_000e18);
        wluxLusdPair.mint(treasury);

        // Add liquidity to alUSD/LUSD (1:1 peg)
        alUSD.transfer(address(alUsdLusdPair), 100_000e18);
        lusd.transfer(address(alUsdLusdPair), 100_000e18);
        alUsdLusdPair.mint(treasury);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_TokensDeployed() public view {
        assertEq(wlux.name(), "Wrapped LUX");
        assertEq(wlux.symbol(), "WLUX");

        assertEq(lusd.name(), "Lux Dollar");
        assertEq(lusd.symbol(), "LUSD");

        assertEq(alUSD.name(), "Alchemic USD");
        assertEq(alUSD.symbol(), "alUSD");
    }

    function test_AMMDeployed() public view {
        assertEq(factory.allPairsLength(), 2);
        assertTrue(address(wluxLusdPair) != address(0));
        assertTrue(address(alUsdLusdPair) != address(0));
    }

    function test_LiquidityExists() public view {
        (uint112 r0, uint112 r1,) = wluxLusdPair.getReserves();
        assertTrue(r0 > 0 && r1 > 0, "WLUX/LUSD pair should have liquidity");

        (r0, r1,) = alUsdLusdPair.getReserves();
        assertTrue(r0 > 0 && r1 > 0, "alUSD/LUSD pair should have liquidity");
    }

    function test_Swap_WLUXForLUSD() public {
        console.log("");
        console.log("=== SWAP: WLUX -> LUSD ===");

        // Give alice some WLUX
        vm.deal(alice, 1000 ether);
        vm.prank(alice);
        wlux.deposit{value: 1000 ether}();

        uint256 amountIn = 100e18; // 100 WLUX

        // Calculate expected output
        (uint112 r0, uint112 r1,) = wluxLusdPair.getReserves();
        address token0 = wluxLusdPair.token0();
        (uint112 wluxReserve, uint112 lusdReserve) = token0 == address(wlux) ? (r0, r1) : (r1, r0);

        uint256 amountInWithFee = amountIn * 997;
        uint256 expectedOut = (amountInWithFee * lusdReserve) / (wluxReserve * 1000 + amountInWithFee);

        console.log("Swapping WLUX:", amountIn / 1e18);
        console.log("Expected LUSD:", expectedOut);

        // Execute swap
        vm.startPrank(alice);
        wlux.transfer(address(wluxLusdPair), amountIn);

        uint256 amount0Out = token0 == address(wlux) ? 0 : expectedOut;
        uint256 amount1Out = token0 == address(wlux) ? expectedOut : 0;
        wluxLusdPair.swap(amount0Out, amount1Out, alice, "");
        vm.stopPrank();

        uint256 lusdReceived = lusd.balanceOf(alice);
        console.log("SWAP SUCCESSFUL: Received", lusdReceived, "LUSD");

        assertEq(lusdReceived, expectedOut, "Should receive expected LUSD");
        assertTrue(lusdReceived > 99e18, "Should receive ~99+ LUSD for 100 WLUX");
    }

    function test_Swap_LUSDForAlUSD() public {
        console.log("");
        console.log("=== SWAP: LUSD -> alUSD (Synth) ===");

        // Give bob some LUSD
        uint256 amountIn = 1000e18; // 1000 LUSD
        lusd.mint(bob, amountIn);

        // Calculate expected output
        (uint112 r0, uint112 r1,) = alUsdLusdPair.getReserves();
        address token0 = alUsdLusdPair.token0();
        (uint112 alUsdReserve, uint112 lusdReserve) = token0 == address(alUSD) ? (r0, r1) : (r1, r0);

        uint256 amountInWithFee = amountIn * 997;
        uint256 expectedOut = (amountInWithFee * alUsdReserve) / (lusdReserve * 1000 + amountInWithFee);

        console.log("Swapping LUSD:", amountIn / 1e18);
        console.log("Expected alUSD:", expectedOut);

        // Execute swap
        vm.startPrank(bob);
        lusd.transfer(address(alUsdLusdPair), amountIn);

        uint256 amount0Out = token0 == address(alUSD) ? expectedOut : 0;
        uint256 amount1Out = token0 == address(alUSD) ? 0 : expectedOut;
        alUsdLusdPair.swap(amount0Out, amount1Out, bob, "");
        vm.stopPrank();

        uint256 alUsdReceived = alUSD.balanceOf(bob);
        console.log("SYNTH SWAP SUCCESSFUL: Received", alUsdReceived, "alUSD");

        assertEq(alUsdReceived, expectedOut, "Should receive expected alUSD");
        assertTrue(alUsdReceived > 980e18, "Should receive ~980+ alUSD for 1000 LUSD (1:1 peg with slippage)");
    }

    function test_FullFlow_WrapSwapSynthSwap() public {
        console.log("");
        console.log("=== FULL FLOW: Wrap LUX -> Swap to LUSD -> Swap to alUSD ===");

        // Start with native LUX
        vm.deal(alice, 500 ether);

        vm.startPrank(alice);

        // Step 1: Wrap LUX -> WLUX
        wlux.deposit{value: 500 ether}();
        console.log("1. Wrapped 500 LUX -> 500 WLUX");

        // Step 2: Swap WLUX -> LUSD
        uint256 wluxToSwap = 100e18;
        wlux.transfer(address(wluxLusdPair), wluxToSwap);

        (uint112 r0, uint112 r1,) = wluxLusdPair.getReserves();
        address token0 = wluxLusdPair.token0();
        (uint112 wluxR, uint112 lusdR) = token0 == address(wlux) ? (r0, r1) : (r1, r0);
        uint256 lusdOut = (wluxToSwap * 997 * lusdR) / (wluxR * 1000 + wluxToSwap * 997);

        wluxLusdPair.swap(
            token0 == address(wlux) ? 0 : lusdOut,
            token0 == address(wlux) ? lusdOut : 0,
            alice,
            ""
        );
        console.log("2. Swapped 100 WLUX ->", lusdOut, "LUSD");

        // Step 3: Swap LUSD -> alUSD
        uint256 lusdToSwap = 50_000e18; // Use 50k LUSD
        vm.stopPrank();
        lusd.mint(alice, lusdToSwap); // Mint more for this test (requires admin)
        vm.startPrank(alice);
        lusd.transfer(address(alUsdLusdPair), lusdToSwap);

        (r0, r1,) = alUsdLusdPair.getReserves();
        token0 = alUsdLusdPair.token0();
        (uint112 alR, uint112 luR) = token0 == address(alUSD) ? (r0, r1) : (r1, r0);
        uint256 alUsdOut = (lusdToSwap * 997 * alR) / (luR * 1000 + lusdToSwap * 997);

        alUsdLusdPair.swap(
            token0 == address(alUSD) ? alUsdOut : 0,
            token0 == address(alUSD) ? 0 : alUsdOut,
            alice,
            ""
        );
        console.log("3. Swapped 50000 LUSD ->", alUsdOut, "alUSD");

        vm.stopPrank();

        // Verify final state
        assertTrue(wlux.balanceOf(alice) == 400e18, "Should have 400 WLUX left");
        assertTrue(alUSD.balanceOf(alice) > 0, "Should have alUSD");

        console.log("FULL FLOW COMPLETE!");
    }

    function test_PriceImpact() public view {
        console.log("");
        console.log("=== PRICE IMPACT ANALYSIS ===");

        (uint112 r0, uint112 r1,) = wluxLusdPair.getReserves();
        address token0 = wluxLusdPair.token0();
        (uint112 wluxReserve, uint112 lusdReserve) = token0 == address(wlux) ? (r0, r1) : (r1, r0);

        // Price = LUSD reserve / WLUX reserve
        uint256 price = (uint256(lusdReserve) * 1e18) / uint256(wluxReserve);
        console.log("Current WLUX price:", price / 1e18, "LUSD");

        // Calculate price impact for different trade sizes
        uint256[] memory tradeSizes = new uint256[](4);
        tradeSizes[0] = 100e18;    // 100 WLUX
        tradeSizes[1] = 1000e18;   // 1,000 WLUX
        tradeSizes[2] = 10000e18;  // 10,000 WLUX
        tradeSizes[3] = 100000e18; // 100,000 WLUX

        for (uint i = 0; i < tradeSizes.length; i++) {
            uint256 amountIn = tradeSizes[i];
            uint256 expectedOut = (amountIn * 997 * lusdReserve) / (wluxReserve * 1000 + amountIn * 997);
            uint256 effectivePrice = (expectedOut * 1e18) / amountIn;
            uint256 priceImpact = ((price - effectivePrice) * 10000) / price; // basis points

            console.log("Trade WLUX amount:", amountIn / 1e18);
            console.log("  Price impact (bps):", priceImpact);
        }
    }
}
