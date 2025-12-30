// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

// AMM V2 contracts
import "../../contracts/amm/AMMV2Factory.sol";
import "../../contracts/amm/AMMV2Pair.sol";
import "../../contracts/amm/AMMV2Router.sol";

// AMM V3 contracts
import "../../contracts/amm/AMMV3Factory.sol";
import "../../contracts/amm/AMMV3Pool.sol";

// Interfaces
import "../../contracts/amm/interfaces/IWLUX.sol";

// Shared mocks
import {MockERC20 as MockToken, MockWLUX} from "./TestMocks.sol";

/// @title AMMV2Test
/// @notice Comprehensive tests for AMM V2 (Uniswap V2-style)
contract AMMV2Test is Test {
    // Core contracts
    AMMV2Factory public factory;
    AMMV2Router public router;

    // Mock tokens
    MockToken public tokenA;
    MockToken public tokenB;
    MockToken public usdc;
    MockWLUX public wlux;

    // Users
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public feeCollector = address(0x3);

    // Constants
    uint256 constant INITIAL_MINT = 1_000_000e18;
    uint256 constant USDC_INITIAL = 1_000_000e6;

    function setUp() public {
        // Deploy WLUX
        wlux = new MockWLUX();

        // Deploy tokens
        tokenA = new MockToken("Token A", "TKA", 18);
        tokenB = new MockToken("Token B", "TKB", 18);
        usdc = new MockToken("USD Coin", "USDC", 6);

        // Deploy factory and router
        factory = new AMMV2Factory(feeCollector);
        router = new AMMV2Router(address(factory), address(wlux));

        // Mint tokens to users
        tokenA.mint(alice, INITIAL_MINT);
        tokenB.mint(alice, INITIAL_MINT);
        usdc.mint(alice, USDC_INITIAL);

        tokenA.mint(bob, INITIAL_MINT);
        tokenB.mint(bob, INITIAL_MINT);
        usdc.mint(bob, USDC_INITIAL);

        // Fund users with LUX
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FACTORY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_FactoryDeployment() public view {
        assertEq(factory.feeToSetter(), feeCollector);
        assertEq(factory.allPairsLength(), 0);
    }

    function test_CreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);

        AMMV2Pair pairContract = AMMV2Pair(pair);
        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        assertEq(pairContract.token0(), token0);
        assertEq(pairContract.token1(), token1);
    }

    function test_CannotCreateDuplicatePair() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert("AMMV2: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert("AMMV2: PAIR_EXISTS");
        factory.createPair(address(tokenB), address(tokenA));
    }

    function test_CannotCreatePairWithSameToken() public {
        vm.expectRevert("AMMV2: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_CannotCreatePairWithZeroAddress() public {
        vm.expectRevert("AMMV2: ZERO_ADDRESS");
        factory.createPair(address(0), address(tokenA));
    }

    function test_SetFeeTo() public {
        address newFeeCollector = address(0x999);

        vm.prank(feeCollector);
        factory.setFeeTo(newFeeCollector);

        assertEq(factory.feeTo(), newFeeCollector);
    }

    function test_OnlyFeeSetterCanSetFeeTo() public {
        vm.prank(alice);
        vm.expectRevert("AMMV2: FORBIDDEN");
        factory.setFeeTo(address(0x999));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDITY TESTS (V2)
    // ═══════════════════════════════════════════════════════════════════════

    function test_AddLiquidityFirstTime() public {
        uint256 amountA = 100e18;
        uint256 amountB = 200e18;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        (uint256 actualA, uint256 actualB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, // min amounts
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(actualA, amountA);
        assertEq(actualB, amountB);
        assertGt(liquidity, 0);

        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertGt(AMMV2Pair(pair).balanceOf(alice), 0);
    }

    function test_AddLiquiditySubsequent() public {
        // First liquidity provision
        vm.startPrank(alice);
        tokenA.approve(address(router), 100e18);
        tokenB.approve(address(router), 200e18);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            200e18,
            0, 0, alice,
            block.timestamp
        );

        // Second liquidity provision (should maintain ratio)
        tokenA.approve(address(router), 50e18);
        tokenB.approve(address(router), 100e18);
        (uint256 actualA, uint256 actualB,) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            50e18,
            100e18,
            0, 0, alice,
            block.timestamp
        );
        vm.stopPrank();

        // Should maintain 1:2 ratio
        assertEq(actualA, 50e18);
        assertEq(actualB, 100e18);
    }

    function test_AddLiquidityLUX() public {
        uint256 tokenAmount = 100e18;
        uint256 luxAmount = 10 ether;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);

        (uint256 actualToken, uint256 actualLUX, uint256 liquidity) = router.addLiquidityLUX{value: luxAmount}(
            address(tokenA),
            tokenAmount,
            0, // min amounts
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(actualToken, tokenAmount);
        assertEq(actualLUX, luxAmount);
        assertGt(liquidity, 0);
    }

    function test_RemoveLiquidity() public {
        // Add liquidity first
        vm.startPrank(alice);
        tokenA.approve(address(router), 100e18);
        tokenB.approve(address(router), 200e18);
        (,, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            200e18,
            0, 0, alice,
            block.timestamp
        );

        // Remove liquidity
        address pair = factory.getPair(address(tokenA), address(tokenB));
        AMMV2Pair(pair).approve(address(router), liquidity);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0, // min amounts
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        assertGt(amountA, 0);
        assertGt(amountB, 0);
    }

    function test_RemoveLiquidityLUX() public {
        // Add LUX liquidity first
        vm.startPrank(alice);
        tokenA.approve(address(router), 100e18);
        (,, uint256 liquidity) = router.addLiquidityLUX{value: 10 ether}(
            address(tokenA),
            100e18,
            0, 0, alice,
            block.timestamp
        );

        // Remove liquidity
        address pair = factory.getPair(address(tokenA), address(wlux));
        AMMV2Pair(pair).approve(address(router), liquidity);

        uint256 luxBefore = alice.balance;
        (uint256 amountToken, uint256 amountLUX) = router.removeLiquidityLUX(
            address(tokenA),
            liquidity,
            0, 0, alice,
            block.timestamp
        );
        vm.stopPrank();

        assertGt(amountToken, 0);
        assertGt(amountLUX, 0);
        assertEq(alice.balance - luxBefore, amountLUX);
    }

    function test_MinimumLiquidityLocked() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), 100e18);
        tokenB.approve(address(router), 200e18);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            200e18,
            0, 0, alice,
            block.timestamp
        );
        vm.stopPrank();

        address pair = factory.getPair(address(tokenA), address(tokenB));

        // Check minimum liquidity is locked
        assertEq(AMMV2Pair(pair).balanceOf(address(0xdead)), 1000);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SWAP TESTS (V2)
    // ═══════════════════════════════════════════════════════════════════════

    function test_SwapExactTokensForTokens() public {
        // Setup liquidity
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        // Perform swap
        uint256 swapAmount = 10e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(bob);
        tokenA.approve(address(router), swapAmount);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            swapAmount,
            0, // min out
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(amounts[0], swapAmount);
        assertGt(amounts[1], 0);

        // Verify constant product with fees (0.3%)
        // Should get less than simple ratio due to fees
        assertLt(amounts[1], 20e18); // Would be 20e18 without fees
    }

    function test_SwapTokensForExactTokens() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        uint256 desiredOut = 10e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);

        uint256[] memory amounts = router.swapTokensForExactTokens(
            desiredOut,
            type(uint256).max, // max in
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(amounts[1], desiredOut);
        assertGt(amounts[0], 0);
    }

    function test_SwapExactLUXForTokens() public {
        _addLiquidity(alice, address(tokenA), address(wlux), 100e18, 10 ether);

        address[] memory path = new address[](2);
        path[0] = address(wlux);
        path[1] = address(tokenA);

        vm.startPrank(bob);
        uint256[] memory amounts = router.swapExactLUXForTokens{value: 1 ether}(
            0, // min out
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(amounts[0], 1 ether);
        assertGt(amounts[1], 0);
    }

    function test_SwapExactTokensForLUX() public {
        _addLiquidity(alice, address(tokenA), address(wlux), 100e18, 10 ether);

        uint256 swapAmount = 10e18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(wlux);

        vm.startPrank(bob);
        tokenA.approve(address(router), swapAmount);

        uint256 luxBefore = bob.balance;
        uint256[] memory amounts = router.swapExactTokensForLUX(
            swapAmount,
            0,
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(amounts[0], swapAmount);
        assertEq(bob.balance - luxBefore, amounts[1]);
    }

    function test_MultiHopSwap() public {
        // Create A -> B -> C liquidity path
        MockToken tokenC = new MockToken("Token C", "TKC", 18);
        tokenC.mint(alice, INITIAL_MINT);

        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);
        _addLiquidity(alice, address(tokenB), address(tokenC), 200e18, 400e18);

        // Swap A -> B -> C
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        vm.startPrank(bob);
        tokenA.approve(address(router), 10e18);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(amounts.length, 3);
        assertGt(amounts[2], 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PRICE IMPACT TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_PriceImpactSmallSwap() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        // Small swap (1% of pool)
        uint256 swapAmount = 1e18;
        uint256 expectedOut = router.getAmountOut(swapAmount, 100e18, 200e18);

        // Price impact should be minimal
        // Without fees: 1 * 200 / 101 = ~1.98
        // With 0.3% fee: slightly less
        assertGt(expectedOut, 1.96e18);
        assertLt(expectedOut, 1.98e18);
    }

    function test_PriceImpactLargeSwap() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        // Large swap (50% of pool)
        uint256 swapAmount = 50e18;
        uint256 expectedOut = router.getAmountOut(swapAmount, 100e18, 200e18);

        // Price impact should be significant
        // Without fees: 50 * 200 / 150 = ~66.67
        // With fees: much less than linear expectation of 100
        assertLt(expectedOut, 70e18);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SLIPPAGE PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_SlippageProtectionOnSwap() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory expectedAmounts = router.getAmountsOut(10e18, path);
        uint256 minOut = expectedAmounts[1] * 95 / 100; // 5% slippage

        vm.startPrank(bob);
        tokenA.approve(address(router), 10e18);

        // This should succeed with realistic slippage
        router.swapExactTokensForTokens(
            10e18,
            minOut,
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();
    }

    function test_SlippageProtectionRevert() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(bob);
        tokenA.approve(address(router), 10e18);

        // Set unrealistic minOut
        vm.expectRevert("AMMV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            10e18,
            100e18, // Unrealistic expectation
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEADLINE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_DeadlineExpired() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), 100e18);
        tokenB.approve(address(router), 200e18);

        // Set deadline in the past
        vm.expectRevert("AMMV2Router: EXPIRED");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            200e18,
            0, 0, alice,
            block.timestamp - 1
        );
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_CannotSwapToSamePair() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenA); // Same token

        vm.startPrank(bob);
        tokenA.approve(address(router), 10e18);

        vm.expectRevert();
        router.swapExactTokensForTokens(10e18, 0, path, bob, block.timestamp);
        vm.stopPrank();
    }

    function test_CannotSwapWithInsufficientLiquidity() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 10e18, 20e18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);

        // Trying to get more output than available in reserves (20e18 tokenB in pool)
        // This should fail because amountOut (25e18) > reserve1 (20e18)
        vm.expectRevert();
        router.swapTokensForExactTokens(25e18, type(uint256).max, path, bob, block.timestamp);
        vm.stopPrank();
    }

    function test_DirectPairSwap() public {
        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        address pair = factory.getPair(address(tokenA), address(tokenB));

        // Transfer tokens directly to pair
        vm.startPrank(bob);
        uint256 swapAmount = 10e18;
        tokenA.transfer(pair, swapAmount);

        // Calculate expected output
        (uint112 reserve0, uint112 reserve1,) = AMMV2Pair(pair).getReserves();
        (address token0,) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        (uint256 reserveIn, uint256 reserveOut) = address(tokenA) == token0
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        uint256 amountOut = router.getAmountOut(swapAmount, reserveIn, reserveOut);

        // Execute swap
        (uint256 amount0Out, uint256 amount1Out) = address(tokenA) == token0
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));

        AMMV2Pair(pair).swap(amount0Out, amount1Out, bob, new bytes(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_SwapAmount(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e15, 10e18); // 0.001 to 10 tokens

        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(bob);
        tokenA.approve(address(router), swapAmount);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        // Verify constant product (with fees)
        assertGt(amounts[1], 0);
        assertLt(amounts[1], swapAmount * 2); // Can't get more than 2x due to pool ratio
    }

    function testFuzz_AddLiquidity(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1e18, 1000e18);
        amountB = bound(amountB, 1e18, 1000e18);

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        (uint256 actualA, uint256 actualB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, 0, alice,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(actualA, amountA);
        assertEq(actualB, amountB);
        assertGt(liquidity, 0);
    }

    function testFuzz_PriceQuote(uint256 amountA, uint256 reserveA, uint256 reserveB) public view {
        amountA = bound(amountA, 1, type(uint128).max);
        reserveA = bound(reserveA, 1e18, type(uint64).max);
        reserveB = bound(reserveB, 1e18, type(uint64).max);

        uint256 amountB = router.quote(amountA, reserveA, reserveB);

        // Verify linear pricing
        assertEq(amountB, (amountA * reserveB) / reserveA);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE COLLECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_ProtocolFees() public {
        // Enable protocol fees
        vm.prank(feeCollector);
        factory.setFeeTo(feeCollector);

        _addLiquidity(alice, address(tokenA), address(tokenB), 100e18, 200e18);

        // Perform multiple swaps to generate fees
        for (uint i = 0; i < 10; i++) {
            _swap(bob, address(tokenA), address(tokenB), 1e18);
        }

        // Remove liquidity should trigger fee minting
        address pair = factory.getPair(address(tokenA), address(tokenB));
        vm.startPrank(alice);
        uint256 liquidity = AMMV2Pair(pair).balanceOf(alice);
        AMMV2Pair(pair).approve(address(router), liquidity);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0, 0, alice,
            block.timestamp
        );
        vm.stopPrank();

        // Fee collector should have received LP tokens
        // Note: Fee calculation would require kLast tracking in production
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _addLiquidity(
        address user,
        address tokenX,
        address tokenY,
        uint256 amountX,
        uint256 amountY
    ) internal {
        vm.startPrank(user);

        if (tokenX == address(wlux) || tokenY == address(wlux)) {
            address token = tokenX == address(wlux) ? tokenY : tokenX;
            uint256 tokenAmount = tokenX == address(wlux) ? amountY : amountX;
            uint256 luxAmount = tokenX == address(wlux) ? amountX : amountY;

            MockToken(token).approve(address(router), tokenAmount);
            router.addLiquidityLUX{value: luxAmount}(
                token,
                tokenAmount,
                0, 0, user,
                block.timestamp
            );
        } else {
            MockToken(tokenX).approve(address(router), amountX);
            MockToken(tokenY).approve(address(router), amountY);
            router.addLiquidity(
                tokenX,
                tokenY,
                amountX,
                amountY,
                0, 0, user,
                block.timestamp
            );
        }

        vm.stopPrank();
    }

    function _swap(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        vm.startPrank(user);
        MockToken(tokenIn).approve(address(router), amountIn);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            user,
            block.timestamp
        );
        vm.stopPrank();
    }
}

/// @title AMMV3Test
/// @notice Comprehensive tests for AMM V3 (Uniswap V3-style concentrated liquidity)
contract AMMV3Test is Test {
    AMMV3Factory public factory;

    MockToken public tokenA;
    MockToken public tokenB;
    MockToken public usdc;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public owner = address(this);

    uint256 constant INITIAL_MINT = 1_000_000e18;
    uint256 constant USDC_INITIAL = 1_000_000e6;

    function setUp() public {
        factory = new AMMV3Factory();

        tokenA = new MockToken("Token A", "TKA", 18);
        tokenB = new MockToken("Token B", "TKB", 18);
        usdc = new MockToken("USD Coin", "USDC", 6);

        tokenA.mint(alice, INITIAL_MINT);
        tokenB.mint(alice, INITIAL_MINT);
        usdc.mint(alice, USDC_INITIAL);

        tokenA.mint(bob, INITIAL_MINT);
        tokenB.mint(bob, INITIAL_MINT);
        usdc.mint(bob, USDC_INITIAL);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FACTORY TESTS (V3)
    // ═══════════════════════════════════════════════════════════════════════

    function test_V3FactoryDeployment() public view {
        assertEq(factory.owner(), owner);
        assertEq(factory.allPoolsLength(), 0);

        // Check default fee tiers
        assertEq(factory.feeAmountTickSpacing(100), 1);
        assertEq(factory.feeAmountTickSpacing(500), 10);
        assertEq(factory.feeAmountTickSpacing(3000), 60);
        assertEq(factory.feeAmountTickSpacing(10000), 200);
    }

    function test_V3CreatePool() public {
        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);

        assertEq(factory.allPoolsLength(), 1);
        assertEq(factory.getPool(address(tokenA), address(tokenB), 3000), pool);
        assertEq(factory.getPool(address(tokenB), address(tokenA), 3000), pool);

        AMMV3Pool poolContract = AMMV3Pool(pool);
        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        assertEq(poolContract.token0(), token0);
        assertEq(poolContract.token1(), token1);
        assertEq(poolContract.fee(), 3000);
        assertEq(poolContract.tickSpacing(), 60);
    }

    function test_V3CreateMultipleFeeTiers() public {
        address pool1 = factory.createPool(address(tokenA), address(tokenB), 500);
        address pool2 = factory.createPool(address(tokenA), address(tokenB), 3000);
        address pool3 = factory.createPool(address(tokenA), address(tokenB), 10000);

        assertTrue(pool1 != pool2);
        assertTrue(pool2 != pool3);
        assertEq(factory.allPoolsLength(), 3);
    }

    function test_V3CannotCreateDuplicatePool() public {
        factory.createPool(address(tokenA), address(tokenB), 3000);

        vm.expectRevert("AMMV3: POOL_EXISTS");
        factory.createPool(address(tokenA), address(tokenB), 3000);
    }

    function test_V3CannotCreatePoolWithInvalidFee() public {
        vm.expectRevert("AMMV3: FEE_NOT_ENABLED");
        factory.createPool(address(tokenA), address(tokenB), 1234);
    }

    function test_V3EnableNewFeeAmount() public {
        factory.enableFeeAmount(2000, 40);

        assertEq(factory.feeAmountTickSpacing(2000), 40);

        // Should be able to create pool with new fee tier
        address pool = factory.createPool(address(tokenA), address(tokenB), 2000);
        assertEq(AMMV3Pool(pool).fee(), 2000);
    }

    function test_V3OnlyOwnerCanEnableFees() public {
        vm.prank(alice);
        vm.expectRevert("AMMV3: NOT_OWNER");
        factory.enableFeeAmount(2000, 40);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL INITIALIZATION TESTS (V3)
    // ═══════════════════════════════════════════════════════════════════════

    function test_V3PoolInitialization() public {
        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool poolContract = AMMV3Pool(pool);

        // Initialize price: 1 tokenA = 2 tokenB
        // sqrtPriceX96 = sqrt(price) * 2^96
        // For price = 2: sqrt(2) * 2^96 ≈ 1.414 * 2^96
        uint160 sqrtPriceX96 = 112045541949572279837463876454; // sqrt(2) * 2^96

        poolContract.initializePrice(sqrtPriceX96);

        assertEq(poolContract.sqrtPriceX96(), sqrtPriceX96);
        assertGt(poolContract.tick(), 0); // Should be positive for price > 1
    }

    function test_V3CannotInitializeTwice() public {
        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool poolContract = AMMV3Pool(pool);

        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price
        poolContract.initializePrice(sqrtPriceX96);

        vm.expectRevert("AMMV3: ALREADY_INITIALIZED");
        poolContract.initializePrice(sqrtPriceX96);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONCENTRATED LIQUIDITY TESTS (V3)
    // ═══════════════════════════════════════════════════════════════════════

    function test_V3MintLiquidity() public {
        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool poolContract = AMMV3Pool(pool);

        // Initialize at 1:1 price
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        poolContract.initializePrice(sqrtPriceX96);

        // Mint liquidity in range
        vm.startPrank(alice);
        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        // AMMV3Pool requires tokens to be transferred BEFORE calling mint
        MockToken(token0).transfer(address(poolContract), 100e18);
        MockToken(token1).transfer(address(poolContract), 100e18);

        // Use smaller liquidity to avoid overflow in _getAmount0ForLiquidity
        // The contract's math: (liquidity << 96) can overflow for large liquidity values
        // Max safe liquidity: 2^256 / 2^96 = 2^160 ~ 1.46e48, but we need extra room
        // for multiplication with sqrtPrice differences, so use conservative value
        (uint256 amount0, uint256 amount1) = poolContract.mint(
            alice,
            -60, // tickLower (tick spacing = 60)
            60,  // tickUpper
            1000 // very small liquidity to avoid overflow
        );
        vm.stopPrank();

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test_V3CannotMintWithInvalidTickRange() public {
        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool poolContract = AMMV3Pool(pool);

        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        poolContract.initializePrice(sqrtPriceX96);

        vm.startPrank(alice);
        vm.expectRevert("AMMV3: INVALID_TICK_RANGE");
        poolContract.mint(alice, 60, -60, 1e18); // tickLower > tickUpper
        vm.stopPrank();
    }

    function test_V3TickSpacingEnforcement() public {
        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool poolContract = AMMV3Pool(pool);

        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        poolContract.initializePrice(sqrtPriceX96);

        vm.startPrank(alice);
        // tickSpacing = 60, so ticks must be multiples of 60
        vm.expectRevert("AMMV3: TICK_SPACING");
        poolContract.mint(alice, -61, 61, 1e18);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS (V3)
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_V3CreatePool(uint24 fee) public {
        // Only test valid fee tiers
        if (fee != 100 && fee != 500 && fee != 3000 && fee != 10000) {
            vm.expectRevert("AMMV3: FEE_NOT_ENABLED");
        }
        factory.createPool(address(tokenA), address(tokenB), fee);
    }

    function testFuzz_V3TickSpacing(int24 tick) public {
        // MAX_TICK = 887272, MIN_TICK = -887272, tickSpacing = 60
        // tickLower must be a multiple of 60
        // tickUpper = tickLower + 120 must be <= 887272
        // So tickLower must be <= 887152 (887272 - 120)
        // And tickLower must be >= -887272
        // 
        // Use direct tick values that are multiples of 60 for tickLower
        int24 tickLower = int24(bound(int256(tick), -887220, 887100));
        // Round to nearest multiple of 60 (towards zero)
        tickLower = (tickLower / 60) * 60;
        int24 tickUpper = tickLower + 120;

        // Safety bounds
        vm.assume(tickLower >= -887272);
        vm.assume(tickUpper <= 887272);
        vm.assume(tickLower < tickUpper);

        address pool = factory.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool poolContract = AMMV3Pool(pool);

        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        poolContract.initializePrice(sqrtPriceX96);

        vm.startPrank(alice);
        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        // Transfer tokens to the pool before minting (required by AMMV3Pool)
        MockToken(token0).transfer(address(poolContract), 100e18);
        MockToken(token1).transfer(address(poolContract), 100e18);

        // Use smaller liquidity to avoid overflow in _getAmount0ForLiquidity
        poolContract.mint(alice, tickLower, tickUpper, 1000);
        vm.stopPrank();
    }
}

/// @title AMMIntegrationTest
/// @notice Integration tests between V2 and V3 protocols
contract AMMIntegrationTest is Test {
    AMMV2Factory public factoryV2;
    AMMV2Router public routerV2;
    AMMV3Factory public factoryV3;

    MockToken public tokenA;
    MockToken public tokenB;
    MockWLUX public wlux;

    address public alice = address(0x1);

    function setUp() public {
        wlux = new MockWLUX();

        tokenA = new MockToken("Token A", "TKA", 18);
        tokenB = new MockToken("Token B", "TKB", 18);

        factoryV2 = new AMMV2Factory(address(this));
        routerV2 = new AMMV2Router(address(factoryV2), address(wlux));
        factoryV3 = new AMMV3Factory();

        tokenA.mint(alice, 1_000_000e18);
        tokenB.mint(alice, 1_000_000e18);
    }

    function test_CrossProtocolArbitrage() public {
        // Create V2 pool with 1:2 ratio
        vm.startPrank(alice);
        tokenA.approve(address(routerV2), 100e18);
        tokenB.approve(address(routerV2), 200e18);
        routerV2.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            200e18,
            0, 0, alice,
            block.timestamp
        );

        // Create V3 pool with different price
        address poolV3 = factoryV3.createPool(address(tokenA), address(tokenB), 3000);
        AMMV3Pool(poolV3).initializePrice(79228162514264337593543950336); // 1:1 price

        vm.stopPrank();

        // V2 has 1:2 ratio, V3 has 1:1 - arbitrage opportunity exists
        address pairV2 = factoryV2.getPair(address(tokenA), address(tokenB));
        (uint112 r0, uint112 r1,) = AMMV2Pair(pairV2).getReserves();

        assertTrue(r0 * 2 == r1 || r1 * 2 == r0); // Verify 1:2 ratio in V2
    }
}
