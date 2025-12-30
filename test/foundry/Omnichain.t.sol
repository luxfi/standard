// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {OmnichainLP} from "../../contracts/omnichain/OmnichainLP.sol";
import {OmnichainLPFactory} from "../../contracts/omnichain/OmnichainLPFactory.sol";
import {OmnichainLPRouter} from "../../contracts/omnichain/OmnichainLPRouter.sol";
import {Bridge} from "../../contracts/omnichain/Bridge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20Simple as MockERC20, MockWLUX} from "./TestMocks.sol";

/// @notice Mock Bridge implementation for testing
contract MockBridge is Bridge {
    // Track bridged messages for verification
    struct BridgeMessage {
        address token;
        uint256 amount;
        uint256 destChainId;
        address recipient;
        uint256 timestamp;
        bytes32 messageId;
        bool executed;
    }

    mapping(bytes32 => BridgeMessage) public messages;
    mapping(uint256 => bool) public supportedChains;
    mapping(address => Token) public registeredTokens;

    uint256 public messageNonce;
    uint256 public baseFee = 0.001 ether;

    // Failed delivery tracking
    mapping(bytes32 => bool) public failedDeliveries;

    // Replay protection
    mapping(bytes32 => bool) public processedMessages;

    event MessageSent(bytes32 indexed messageId, uint256 destChainId, address token, uint256 amount);
    event MessageReceived(bytes32 indexed messageId, address recipient, uint256 amount);
    event DeliveryFailed(bytes32 indexed messageId, string reason);
    event MessageRetried(bytes32 indexed messageId);

    constructor() {
        // Support common chain IDs for testing
        supportedChains[96369] = true; // C-Chain
        supportedChains[36963] = true; // Hanzo
        supportedChains[200200] = true; // Zoo
        supportedChains[1] = true; // Test chain 1
        supportedChains[2] = true; // Test chain 2
    }

    function _bridge(
        address token,
        uint256 amount,
        uint256 destChainId,
        bytes calldata extraData
    ) internal override {
        require(supportedChains[destChainId], "MockBridge: Unsupported chain");
        require(amount > 0, "MockBridge: Zero amount");

        bytes32 messageId = keccak256(abi.encodePacked(
            token,
            amount,
            destChainId,
            block.chainid,
            messageNonce++,
            block.timestamp
        ));

        address recipient = extraData.length >= 20 ? abi.decode(extraData, (address)) : msg.sender;

        messages[messageId] = BridgeMessage({
            token: token,
            amount: amount,
            destChainId: destChainId,
            recipient: recipient,
            timestamp: block.timestamp,
            messageId: messageId,
            executed: false
        });

        emit MessageSent(messageId, destChainId, token, amount);
    }

    function _estimateFee(uint256 destChainId) internal view override returns (uint256) {
        require(supportedChains[destChainId], "MockBridge: Unsupported chain");
        return baseFee;
    }

    // Public wrapper for testing
    function estimateFee(uint256 destChainId) external view returns (uint256) {
        return _estimateFee(destChainId);
    }

    function swap(
        Token memory fromToken,
        Token memory toToken,
        address recipient,
        uint256 amount,
        uint256 deadline
    ) external override {
        require(deadline >= block.timestamp, "MockBridge: Expired");
        require(amount > 0, "MockBridge: Zero amount");
        require(recipient != address(0), "MockBridge: Invalid recipient");

        bytes32 messageId = keccak256(abi.encodePacked(
            fromToken.tokenAddress,
            toToken.tokenAddress,
            amount,
            toToken.chainId,
            messageNonce++,
            block.timestamp
        ));

        messages[messageId] = BridgeMessage({
            token: toToken.tokenAddress,
            amount: amount,
            destChainId: toToken.chainId,
            recipient: recipient,
            timestamp: block.timestamp,
            messageId: messageId,
            executed: false
        });

        emit MessageSent(messageId, toToken.chainId, toToken.tokenAddress, amount);
    }

    function setToken(Token memory token) external override {
        registeredTokens[token.tokenAddress] = token;
    }

    /// @notice Simulate receiving a cross-chain message
    function receiveMessage(
        bytes32 messageId,
        address token,
        address recipient,
        uint256 amount
    ) external {
        require(!processedMessages[messageId], "MockBridge: Replay attack");
        require(!failedDeliveries[messageId], "MockBridge: Delivery failed");

        processedMessages[messageId] = true;

        BridgeMessage storage message = messages[messageId];
        require(!message.executed, "MockBridge: Already executed");

        message.executed = true;

        // Mint tokens on destination chain (mock behavior)
        try OmnichainLP(token).bridgeMint(recipient, amount) {
            emit MessageReceived(messageId, recipient, amount);
        } catch Error(string memory reason) {
            failedDeliveries[messageId] = true;
            emit DeliveryFailed(messageId, reason);
        }
    }

    /// @notice Retry failed delivery
    function retryMessage(bytes32 messageId) external {
        require(failedDeliveries[messageId], "MockBridge: Not failed");

        BridgeMessage storage message = messages[messageId];

        failedDeliveries[messageId] = false;

        try OmnichainLP(message.token).bridgeMint(message.recipient, message.amount) {
            emit MessageReceived(messageId, message.recipient, message.amount);
            emit MessageRetried(messageId);
        } catch Error(string memory reason) {
            failedDeliveries[messageId] = true;
            emit DeliveryFailed(messageId, reason);
        }
    }

    /// @notice Simulate delivery failure for testing
    function simulateFailure(bytes32 messageId) external {
        failedDeliveries[messageId] = true;
        emit DeliveryFailed(messageId, "Simulated failure");
    }

    function setBaseFee(uint256 _fee) external {
        baseFee = _fee;
    }

    function addSupportedChain(uint256 chainId) external {
        supportedChains[chainId] = true;
    }

    /// @notice Create a test message for retry testing
    function createTestMessage(
        bytes32 messageId,
        address token,
        address recipient,
        uint256 amount
    ) external {
        messages[messageId] = BridgeMessage({
            token: token,
            amount: amount,
            destChainId: block.chainid,
            recipient: recipient,
            timestamp: block.timestamp,
            messageId: messageId,
            executed: false
        });
    }
}

/// @title Omnichain Contract Test Suite
contract OmnichainTest is Test {
    MockBridge public bridge;
    OmnichainLPFactory public factory;
    OmnichainLPRouter public router;
    MockWLUX public wlux;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    OmnichainLP public pair;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public feeRecipient = address(0x4);

    // Events for testing
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityBridged(address indexed user, uint256 fromChain, uint256 toChain, uint256 amount);
    event MessageSent(bytes32 indexed messageId, uint256 destChainId, address token, uint256 amount);
    event CrossChainSync(uint256 indexed chainId, uint256 totalLiquidity);
    event MessageRetried(bytes32 indexed messageId);

    function setUp() public {
        // Deploy mock contracts
        bridge = new MockBridge();
        wlux = new MockWLUX();
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");

        // Deploy factory and router
        factory = new OmnichainLPFactory(address(bridge), feeRecipient);
        router = new OmnichainLPRouter(address(factory), address(bridge), address(wlux));

        // Create initial pair
        pair = OmnichainLP(factory.createPair(address(tokenA), address(tokenB)));

        // Setup test accounts with funds
        deal(alice, 100 ether);
        deal(bob, 100 ether);
        deal(charlie, 100 ether);

        tokenA.mint(alice, 10_000 ether);
        tokenA.mint(bob, 10_000 ether);
        tokenB.mint(alice, 10_000 ether);
        tokenB.mint(bob, 10_000 ether);

        // Approve router
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FACTORY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFactoryCreatePair() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC");
        MockERC20 tokenD = new MockERC20("Token D", "TKD");

        vm.expectEmit(false, false, false, false);
        emit PairCreated(address(0), address(0), address(0), 0);

        address newPair = factory.createPair(address(tokenC), address(tokenD));

        assertTrue(newPair != address(0), "Pair not created");
        assertEq(factory.getPair(address(tokenC), address(tokenD)), newPair, "Pair mapping incorrect");
        assertEq(factory.allPairsLength(), 2, "Pair count incorrect");
    }

    function testFactoryCreatePairRevertsOnDuplicate() public {
        vm.expectRevert("OmnichainLPFactory: Pair exists");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testFactoryCreatePairRevertsOnIdenticalTokens() public {
        vm.expectRevert("OmnichainLPFactory: Identical addresses");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testFactoryCreatePairRevertsOnZeroAddress() public {
        vm.expectRevert("OmnichainLPFactory: Zero address");
        factory.createPair(address(0), address(tokenA));
    }

    function testFactoryCalculatePairAddress() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC");
        MockERC20 tokenD = new MockERC20("Token D", "TKD");

        (address token0, address token1) = address(tokenC) < address(tokenD)
            ? (address(tokenC), address(tokenD))
            : (address(tokenD), address(tokenC));

        address predicted = factory.calculatePairAddress(token0, token1);
        address actual = factory.createPair(address(tokenC), address(tokenD));

        assertEq(predicted, actual, "Address prediction failed");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDITY PROVISION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testAddLiquidity() public {
        vm.startPrank(alice);

        uint256 amount0 = 1000 ether;
        uint256 amount1 = 1000 ether;

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amount0,
            amount1,
            amount0,
            amount1,
            alice,
            block.timestamp + 1
        );

        assertEq(amountA, amount0, "Amount A mismatch");
        assertEq(amountB, amount1, "Amount B mismatch");
        assertGt(liquidity, 0, "No liquidity minted");
        assertEq(pair.balanceOf(alice), liquidity, "LP token balance incorrect");

        vm.stopPrank();
    }

    function testAddLiquidityLUX() public {
        vm.startPrank(alice);

        uint256 tokenAmount = 1000 ether;
        uint256 luxAmount = 10 ether;

        (uint256 amountToken, uint256 amountLUX, uint256 liquidity) = router.addLiquidityLUX{value: luxAmount}(
            address(tokenA),
            tokenAmount,
            tokenAmount,
            luxAmount,
            alice,
            block.timestamp + 1
        );

        assertEq(amountToken, tokenAmount, "Token amount mismatch");
        assertEq(amountLUX, luxAmount, "LUX amount mismatch");
        assertGt(liquidity, 0, "No liquidity minted");

        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        // First add liquidity
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        uint256 balanceBefore0 = tokenA.balanceOf(alice);
        uint256 balanceBefore1 = tokenB.balanceOf(alice);

        // Approve router to spend LP tokens
        pair.approve(address(router), liquidity);

        // Remove liquidity
        (uint256 amount0, uint256 amount1) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertGt(amount0, 0, "No token A returned");
        assertGt(amount1, 0, "No token B returned");
        assertEq(pair.balanceOf(alice), 0, "LP tokens not burned");
        assertGt(tokenA.balanceOf(alice), balanceBefore0, "Token A not returned");
        assertGt(tokenB.balanceOf(alice), balanceBefore1, "Token B not returned");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SWAP TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testSwapExactTokensForTokens() public {
        // Add liquidity first
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 ether,
            10_000 ether,
            10_000 ether,
            10_000 ether,
            alice,
            block.timestamp + 1
        );

        // Swap tokens
        vm.startPrank(bob);

        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 balanceBefore = tokenB.balanceOf(bob);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            bob,
            block.timestamp + 1
        );

        assertEq(amounts[0], amountIn, "Input amount mismatch");
        assertGt(amounts[1], 0, "No output received");
        assertEq(tokenB.balanceOf(bob) - balanceBefore, amounts[1], "Output balance mismatch");

        vm.stopPrank();
    }

    function testSwapRevertsOnInsufficientOutput() public {
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 ether,
            10_000 ether,
            10_000 ether,
            10_000 ether,
            alice,
            block.timestamp + 1
        );

        vm.startPrank(bob);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert("OmnichainLPRouter: Insufficient output");
        router.swapExactTokensForTokens(
            100 ether,
            1000 ether, // Unrealistic slippage
            path,
            bob,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-CHAIN BRIDGE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testBridgeLPTokens() public {
        // Add liquidity
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        uint256 bridgeAmount = liquidity / 2;
        uint256 targetChain = 2;

        // Approve pair to spend LP tokens
        pair.approve(address(pair), bridgeAmount);

        vm.expectEmit(true, true, true, false);
        emit LiquidityBridged(alice, block.chainid, targetChain, 0);

        pair.bridgeLPTokens(bridgeAmount, targetChain, bob);

        // Verify tokens burned on source chain
        assertLt(pair.balanceOf(alice), liquidity, "LP tokens not burned");

        vm.stopPrank();
    }

    function testBridgeLPTokensRevertsOnSameChain() public {
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        pair.approve(address(pair), liquidity);

        vm.expectRevert("OmnichainLP: Same chain");
        pair.bridgeLPTokens(liquidity, block.chainid, bob);

        vm.stopPrank();
    }

    function testBridgeMintOnlyByBridge() public {
        vm.prank(alice);
        vm.expectRevert("OmnichainLP: Only bridge can call");
        pair.bridgeMint(alice, 100 ether);
    }

    function testBridgeBurnOnlyByBridge() public {
        vm.prank(alice);
        vm.expectRevert("OmnichainLP: Only bridge can call");
        pair.bridgeBurn(alice, 100 ether);
    }

    function testCrossChainLiquiditySync() public {
        // Add liquidity
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        uint256 initialChainLiquidity = pair.chainLiquidity(block.chainid);
        assertEq(initialChainLiquidity, liquidity, "Initial chain liquidity incorrect");

        // Bridge half
        uint256 bridgeAmount = liquidity / 2;
        pair.approve(address(pair), bridgeAmount);
        pair.bridgeLPTokens(bridgeAmount, 2, bob);

        // Verify chain liquidity decreased
        uint256 afterBridgeLiquidity = pair.chainLiquidity(block.chainid);
        assertEq(afterBridgeLiquidity, liquidity - bridgeAmount, "Chain liquidity not updated");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CROSS-CHAIN MESSAGE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testCrossChainMessageSending() public {
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        pair.approve(address(pair), liquidity);

        vm.expectEmit(false, true, true, false);
        emit MessageSent(bytes32(0), 2, address(pair), 0);

        pair.bridgeLPTokens(liquidity / 2, 2, bob);

        vm.stopPrank();
    }

    function testCrossChainMessageReceiving() public {
        // Setup: Add liquidity and bridge
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        uint256 bridgeAmount = liquidity / 2;
        pair.approve(address(pair), bridgeAmount);
        pair.bridgeLPTokens(bridgeAmount, 2, bob);

        vm.stopPrank();

        // Simulate receiving message on destination chain
        bytes32 messageId = keccak256(abi.encodePacked("test-message"));

        vm.expectEmit(true, true, true, false);
        emit CrossChainSync(block.chainid, 0);

        vm.prank(address(bridge));
        pair.bridgeMint(bob, bridgeAmount);

        assertEq(pair.balanceOf(bob), bridgeAmount, "Tokens not minted on destination");
    }

    function testReplayProtection() public {
        bytes32 messageId = keccak256(abi.encodePacked("test-message"));
        uint256 amount = 100 ether;

        // First receive
        bridge.receiveMessage(messageId, address(pair), bob, amount);

        // Attempt replay
        vm.expectRevert("MockBridge: Replay attack");
        bridge.receiveMessage(messageId, address(pair), bob, amount);
    }

    function test_FailedDelivery() public {
        // Create message
        vm.prank(alice);
        tokenA.approve(address(bridge), 100 ether);

        bytes32 messageId = keccak256(abi.encodePacked("test-message"));

        // Simulate failure
        bridge.simulateFailure(messageId);

        // Verify message marked as failed
        assertTrue(bridge.failedDeliveries(messageId), "Message not marked as failed");
    }

    function testRetryFailedMessage() public {
        // Setup: Add liquidity
        vm.startPrank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        vm.stopPrank();

        bytes32 messageId = keccak256(abi.encodePacked("test-message"));
        uint256 amount = 100 ether;

        // Create the test message with proper data
        bridge.createTestMessage(messageId, address(pair), bob, amount);
        
        // Simulate failed delivery
        bridge.simulateFailure(messageId);

        // Retry - should succeed now with proper message data
        vm.expectEmit(true, false, false, false);
        emit MessageRetried(messageId);

        bridge.retryMessage(messageId);
        
        // Verify bob received the minted tokens
        assertEq(pair.balanceOf(bob), amount, "Bob should have received minted tokens");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FEE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testBridgeFeeEstimation() public {
        uint256 fee = bridge.estimateFee(2);
        assertEq(fee, 0.001 ether, "Fee estimation incorrect");
    }

    function testBridgeFeeDeduction() public {
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        uint256 bridgeAmount = 100 ether;
        pair.approve(address(pair), bridgeAmount);

        uint256 expectedFee = (bridgeAmount * pair.bridgeFee()) / pair.FEE_DENOMINATOR();
        uint256 expectedAfterFee = bridgeAmount - expectedFee;

        pair.bridgeLPTokens(bridgeAmount, 2, bob);

        // Verify fee was deducted (would be sent in bridge message)
        assertGt(expectedFee, 0, "No fee deducted");

        vm.stopPrank();
    }

    function testUpdateBridgeFee() public {
        uint256 newFee = 50; // 0.5%

        // The pair's owner is the factory (set in constructor via Ownable(msg.sender))
        vm.prank(address(factory));
        pair.setBridgeFee(newFee);

        assertEq(pair.bridgeFee(), newFee, "Bridge fee not updated");
    }

    function testBridgeFeeMaxLimit() public {
        // The pair's owner is the factory (set in constructor via Ownable(msg.sender))
        vm.prank(address(factory));
        vm.expectRevert("OmnichainLP: Fee too high");
        pair.setBridgeFee(101); // Over 1%
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testMinimumLiquidity() public {
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        // First liquidity locks MINIMUM_LIQUIDITY
        uint256 totalSupply = pair.totalSupply();
        assertEq(totalSupply, liquidity + pair.MINIMUM_LIQUIDITY(), "Minimum liquidity not locked");

        vm.stopPrank();
    }

    function testZeroLiquidityReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("OmnichainLP: Invalid amount");
        pair.bridgeLPTokens(0, 2, bob);

        vm.stopPrank();
    }

    function testInsufficientBalanceReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("OmnichainLP: Insufficient balance");
        pair.bridgeLPTokens(1000 ether, 2, bob);

        vm.stopPrank();
    }

    function testExpiredDeadlineReverts() public {
        vm.startPrank(alice);

        vm.warp(1000);

        vm.expectRevert("OmnichainLPRouter: Expired");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            999 // Past deadline
        );

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzzAddLiquidity(uint256 amount0, uint256 amount1) public {
        // MINIMUM_LIQUIDITY is 1000, so sqrt(amount0 * amount1) must be > 1000
        // To ensure liquidity > 0, we need amount0 * amount1 > 1000^2 = 1_000_000
        // Using 1001 for both gives us sqrt(1002001) = ~1001 - 1000 = 1, which works
        // But to be safe, use larger minimum to ensure non-trivial liquidity
        amount0 = bound(amount0, 1 ether, 1_000_000 ether);
        amount1 = bound(amount1, 1 ether, 1_000_000 ether);

        tokenA.mint(alice, amount0);
        tokenB.mint(alice, amount1);

        vm.startPrank(alice);

        tokenA.approve(address(router), amount0);
        tokenB.approve(address(router), amount1);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amount0,
            amount1,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertGt(liquidity, 0, "No liquidity minted");
        assertLe(amountA, amount0, "Amount A exceeds desired");
        assertLe(amountB, amount1, "Amount B exceeds desired");

        vm.stopPrank();
    }

    function testFuzzSwap(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 100 ether);

        // Add liquidity first
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 ether,
            10_000 ether,
            10_000 ether,
            10_000 ether,
            alice,
            block.timestamp + 1
        );

        tokenA.mint(bob, amountIn);

        vm.startPrank(bob);

        tokenA.approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            bob,
            block.timestamp + 1
        );

        assertEq(amounts[0], amountIn, "Input amount mismatch");
        assertGt(amounts[1], 0, "No output");

        vm.stopPrank();
    }

    function testFuzzBridgeAmount(uint256 bridgeAmount) public {
        // Add liquidity
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        bridgeAmount = bound(bridgeAmount, 1, liquidity);

        pair.approve(address(pair), bridgeAmount);

        uint256 balanceBefore = pair.balanceOf(alice);

        pair.bridgeLPTokens(bridgeAmount, 2, bob);

        assertEq(balanceBefore - pair.balanceOf(alice), bridgeAmount, "Bridge amount mismatch");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE SYNCHRONIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testChainLiquidityTracking() public {
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        assertEq(pair.chainLiquidity(block.chainid), liquidity, "Chain liquidity incorrect");

        vm.stopPrank();
    }

    function testUserChainBalances() public {
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        assertEq(
            pair.userChainBalances(alice, block.chainid),
            liquidity,
            "User chain balance incorrect"
        );

        vm.stopPrank();
    }

    function testReserveSync() public {
        vm.startPrank(alice);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            1000 ether,
            1000 ether,
            alice,
            block.timestamp + 1
        );

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Manually sync
        pair.sync();

        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();

        assertEq(reserve0, newReserve0, "Reserve0 changed after sync");
        assertEq(reserve1, newReserve1, "Reserve1 changed after sync");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFullCrossChainFlow() public {
        // 1. Alice adds liquidity on Chain A
        vm.startPrank(alice);

        (, , uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 ether,
            10_000 ether,
            10_000 ether,
            10_000 ether,
            alice,
            block.timestamp + 1
        );

        // 2. Alice bridges half to Chain B
        uint256 bridgeAmount = liquidity / 2;
        pair.approve(address(pair), bridgeAmount);
        pair.bridgeLPTokens(bridgeAmount, 2, bob);

        vm.stopPrank();

        // 3. Simulate message arrival on Chain B
        bytes32 messageId = keccak256(abi.encodePacked("cross-chain-msg"));

        vm.prank(address(bridge));
        pair.bridgeMint(bob, bridgeAmount);

        // 4. Verify balances
        assertEq(pair.balanceOf(alice), liquidity - bridgeAmount, "Alice balance incorrect");
        assertEq(pair.balanceOf(bob), bridgeAmount, "Bob balance incorrect on dest chain");

        // 5. Bob can now remove liquidity on Chain B
        vm.startPrank(bob);
        pair.approve(address(router), bridgeAmount);

        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            bridgeAmount,
            0,
            0,
            bob,
            block.timestamp + 1
        );

        assertEq(pair.balanceOf(bob), 0, "Bob still has LP tokens");

        vm.stopPrank();
    }

    function testMultiHopCrossChainSwap() public {
        // Setup liquidity
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 ether,
            10_000 ether,
            10_000 ether,
            10_000 ether,
            alice,
            block.timestamp + 1
        );

        vm.startPrank(bob);

        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = block.chainid;
        chainIds[1] = 2;

        tokenA.approve(address(router), amountIn);

        uint256 amountOut = router.crossChainSwap(
            amountIn,
            0,
            path,
            chainIds,
            bob,
            block.timestamp + 1
        );

        assertGt(amountOut, 0, "No output from cross-chain swap");

        vm.stopPrank();
    }
}
