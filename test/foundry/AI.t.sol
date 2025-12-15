// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/tokens/AI.sol";

/**
 * @title MockWarp
 * @notice Mock Warp precompile for testing cross-chain messaging
 */
contract MockWarp {
    bytes32 public blockchainID;
    uint256 public messageCounter;

    // Store sent messages for verification
    mapping(uint256 => bytes) public sentMessages;
    mapping(uint32 => IWarp.WarpMessage) public verifiedMessages;
    mapping(uint32 => bool) public messageValidity;

    constructor(bytes32 _blockchainID) {
        blockchainID = _blockchainID;
    }

    function getBlockchainID() external view returns (bytes32) {
        return blockchainID;
    }

    function sendWarpMessage(bytes calldata payload) external returns (bytes32 messageID) {
        messageID = keccak256(abi.encode(msg.sender, payload, messageCounter));
        sentMessages[messageCounter] = payload;
        messageCounter++;
        return messageID;
    }

    function getVerifiedWarpMessage(uint32 index) external view returns (IWarp.WarpMessage memory message, bool valid) {
        return (verifiedMessages[index], messageValidity[index]);
    }

    // Test helper: Set up a verified message
    function setVerifiedMessage(
        uint32 index,
        bytes32 sourceChainID,
        address originSender,
        bytes memory payload,
        bool valid
    ) external {
        verifiedMessages[index] = IWarp.WarpMessage({
            sourceChainID: sourceChainID,
            originSenderAddress: originSender,
            payload: payload
        });
        messageValidity[index] = valid;
    }
}

/**
 * @title MockAttestation
 * @notice Mock Attestation precompile for TEE quote verification
 */
contract MockAttestation {
    mapping(bytes32 => bool) public validQuotes;
    mapping(bytes32 => bytes32) public quoteGpuIds;
    mapping(bytes32 => uint8) public quotePrivacyLevels;

    // Set up a valid TEE quote for testing
    function setValidQuote(bytes memory quote, bytes32 gpuId, uint8 privacyLevel) external {
        bytes32 quoteHash = keccak256(quote);
        validQuotes[quoteHash] = true;
        quoteGpuIds[quoteHash] = gpuId;
        quotePrivacyLevels[quoteHash] = privacyLevel;
    }

    function verifyTEEQuote(bytes calldata quote) external view returns (bool valid, bytes32 gpuId, uint8 privacyLevel) {
        bytes32 quoteHash = keccak256(quote);
        return (validQuotes[quoteHash], quoteGpuIds[quoteHash], quotePrivacyLevels[quoteHash]);
    }
}

/**
 * @title MockDEXRouter
 * @notice Mock DEX router for testing token swaps
 */
contract MockDEXRouter {
    // Fixed exchange rates for testing (in basis points, 10000 = 1:1)
    mapping(address => mapping(address => uint256)) public exchangeRates;

    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external {
        exchangeRates[tokenIn][tokenOut] = rate;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        uint256 rate = exchangeRates[path[0]][path[path.length - 1]];
        if (rate == 0) rate = 10000; // Default 1:1

        amounts[path.length - 1] = (amountIn * rate) / 10000;
        require(amounts[path.length - 1] >= amountOutMin, "Slippage");

        // Transfer tokens (simplified - assumes tokens are already at router)
        IERC20(path[path.length - 1]).transfer(to, amounts[path.length - 1]);

        return amounts;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external payable returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[0] = msg.value;

        uint256 rate = exchangeRates[path[0]][path[path.length - 1]];
        if (rate == 0) rate = 10000; // Default 1:1

        amounts[path.length - 1] = (msg.value * rate) / 10000;
        require(amounts[path.length - 1] >= amountOutMin, "Slippage");

        IERC20(path[path.length - 1]).transfer(to, amounts[path.length - 1]);

        return amounts;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        uint256 rate = exchangeRates[path[0]][path[path.length - 1]];
        if (rate == 0) rate = 10000;

        amounts[0] = (amountOut * 10000) / rate;
        amounts[path.length - 1] = amountOut;
        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        uint256 rate = exchangeRates[path[0]][path[path.length - 1]];
        if (rate == 0) rate = 10000;

        amounts[0] = amountIn;
        amounts[path.length - 1] = (amountIn * rate) / 10000;
        return amounts;
    }

    receive() external payable {}
}

/**
 * @title MockWLUX
 * @notice Mock wrapped LUX token
 */
contract MockWLUX {
    string public name = "Wrapped LUX";
    string public symbol = "WLUX";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
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

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

/**
 * @title MockWETH
 * @notice Mock wrapped ETH
 */
contract MockWETH is MockWLUX {
    constructor() {
        name = "Wrapped ETH";
        symbol = "WETH";
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

/**
 * @title AITest
 * @notice Full integration test for AI mining token system
 */
contract AITest is Test {
    // Chain IDs
    bytes32 constant A_CHAIN_ID = keccak256("A-CHAIN");
    bytes32 constant C_CHAIN_ID = keccak256("C-CHAIN");

    // Actors
    address miner = makeAddr("miner");
    address user = makeAddr("user");
    address admin = makeAddr("admin");

    // Mocks
    MockWarp warpA;
    MockWarp warpC;
    MockAttestation attestation;
    MockDEXRouter dexRouter;
    MockWLUX wlux;
    MockWETH weth;

    // Contracts under test
    AINative aiNative;
    AIRemote aiRemote;
    AIPaymentRouter paymentRouter;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy mocks
        warpA = new MockWarp(A_CHAIN_ID);
        warpC = new MockWarp(C_CHAIN_ID);
        attestation = new MockAttestation();
        dexRouter = new MockDEXRouter();
        wlux = new MockWLUX();
        weth = new MockWETH();

        // Deploy AINative on "A-Chain"
        // We need to etch the mock precompiles to the expected addresses
        vm.etch(0x0200000000000000000000000000000000000005, address(warpA).code);
        vm.etch(address(0x0300), address(attestation).code);

        aiNative = new AINative();

        // Set up trusted chains on AINative
        aiNative.addTrustedChain(C_CHAIN_ID);

        // Deploy AIRemote on "C-Chain"
        aiRemote = new AIRemote(A_CHAIN_ID, address(aiNative));

        // Deploy payment router on "C-Chain"
        paymentRouter = new AIPaymentRouter(
            address(wlux),
            address(weth),
            address(dexRouter),
            A_CHAIN_ID,
            address(aiRemote),
            1 ether  // 1 LUX attestation cost
        );

        // Set up trusted router on AINative
        aiNative.addTrustedRouter(C_CHAIN_ID, address(paymentRouter));

        // Mint some WLUX to the DEX router for swaps
        wlux.mint(address(dexRouter), 1000000 ether);

        // Set exchange rates (ETH:LUX = 1:10, meaning 1 ETH = 10 LUX)
        dexRouter.setExchangeRate(address(weth), address(wlux), 100000); // 10x

        vm.stopPrank();
    }

    // ==================== AINative Tests ====================

    function test_AINative_StartSession() public {
        bytes32 sessionId = keccak256("session1");
        bytes memory teeQuote = hex"deadbeef";
        bytes32 gpuId = keccak256("gpu1");

        // Set up valid TEE quote
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, gpuId, uint8(PrivacyLevel.Confidential));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        // Verify session started
        assertEq(aiNative.sessionMiner(sessionId), miner);
        assertTrue(aiNative.activeSessions(sessionId) > 0);
    }

    function test_AINative_Heartbeat() public {
        bytes32 sessionId = keccak256("session2");
        bytes memory teeQuote = hex"cafebabe";
        bytes32 gpuId = keccak256("gpu2");

        // Set up valid TEE quote (Confidential = 1.0x multiplier)
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, gpuId, uint8(PrivacyLevel.Confidential));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        // Wait 60 seconds
        vm.warp(block.timestamp + 60);

        // Submit heartbeat
        vm.prank(miner);
        uint256 reward = aiNative.heartbeat(sessionId);

        // Verify reward (1 AI per minute * 1.0x multiplier = 1 AI)
        assertEq(reward, 1 ether);
        assertEq(aiNative.balanceOf(miner), 1 ether);
    }

    function test_AINative_CompleteSession() public {
        bytes32 sessionId = keccak256("session3");
        bytes memory teeQuote = hex"12345678";
        bytes32 gpuId = keccak256("gpu3");

        // Set up valid TEE quote (Sovereign = 1.5x multiplier)
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, gpuId, uint8(PrivacyLevel.Sovereign));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        // Wait 5 minutes
        vm.warp(block.timestamp + 300);

        // Complete session
        vm.prank(miner);
        uint256 totalReward = aiNative.completeSession(sessionId);

        // Verify reward (5 minutes * 1 AI * 1.5x = 7.5 AI)
        assertEq(totalReward, 7.5 ether);
        assertEq(aiNative.balanceOf(miner), 7.5 ether);

        // Session should be cleared
        assertEq(aiNative.sessionMiner(sessionId), address(0));
    }

    function test_AINative_Teleport() public {
        // First mine some AI
        bytes32 sessionId = keccak256("session4");
        bytes memory teeQuote = hex"aabbccdd";
        bytes32 gpuId = keccak256("gpu4");

        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, gpuId, uint8(PrivacyLevel.Confidential));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        vm.warp(block.timestamp + 120); // 2 minutes

        vm.prank(miner);
        aiNative.completeSession(sessionId);

        // Now teleport to C-Chain
        uint256 teleportAmount = 1 ether;

        vm.prank(miner);
        bytes32 teleportId = aiNative.teleport(C_CHAIN_ID, user, teleportAmount);

        // Verify tokens burned on A-Chain
        assertEq(aiNative.balanceOf(miner), 1 ether); // 2 AI - 1 teleported = 1 AI remaining

        assertTrue(teleportId != bytes32(0));
    }

    // ==================== AIRemote Tests ====================

    function test_AIRemote_ClaimTeleport() public {
        // Set up a verified warp message
        bytes memory payload = abi.encode(user, 5 ether);

        // Mock the warp precompile at expected address
        vm.etch(0x0200000000000000000000000000000000000005, address(warpC).code);

        MockWarp(0x0200000000000000000000000000000000000005).setVerifiedMessage(
            0,
            A_CHAIN_ID,
            address(aiNative),
            payload,
            true
        );

        // Claim teleport
        vm.prank(user);
        uint256 claimed = aiRemote.claimTeleport(0);

        assertEq(claimed, 5 ether);
        assertEq(aiRemote.balanceOf(user), 5 ether);
    }

    function test_AIRemote_BatchClaimTeleports() public {
        // Set up multiple verified warp messages
        vm.etch(0x0200000000000000000000000000000000000005, address(warpC).code);

        MockWarp warp = MockWarp(0x0200000000000000000000000000000000000005);

        warp.setVerifiedMessage(0, A_CHAIN_ID, address(aiNative), abi.encode(user, 1 ether), true);
        warp.setVerifiedMessage(1, A_CHAIN_ID, address(aiNative), abi.encode(user, 2 ether), true);
        warp.setVerifiedMessage(2, A_CHAIN_ID, address(aiNative), abi.encode(user, 3 ether), true);

        uint32[] memory indices = new uint32[](3);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;

        vm.prank(user);
        uint256 total = aiRemote.batchClaimTeleports(indices);

        assertEq(total, 6 ether);
        assertEq(aiRemote.balanceOf(user), 6 ether);
    }

    // ==================== AIPaymentRouter Tests ====================

    function test_PaymentRouter_PayWithLUX() public {
        // Mint WLUX to user
        wlux.mint(user, 10 ether);

        vm.startPrank(user);
        wlux.approve(address(paymentRouter), 10 ether);

        bytes32 sessionId = keccak256("payment-session-1");
        bytes32 requestId = paymentRouter.payForAttestation(
            address(wlux),
            1 ether,
            1 ether, // minLuxOut
            sessionId
        );
        vm.stopPrank();

        assertTrue(requestId != bytes32(0));

        // Verify request stored
        (address requester, bytes32 storedSessionId, uint256 luxPaid, , bool bridged) = paymentRouter.requests(requestId);
        assertEq(requester, user);
        assertEq(storedSessionId, sessionId);
        assertEq(luxPaid, 1 ether);
        assertTrue(bridged);
    }

    function test_PaymentRouter_PayWithETH() public {
        vm.deal(user, 10 ether);

        bytes32 sessionId = keccak256("eth-payment-session");

        vm.prank(user);
        bytes32 requestId = paymentRouter.payWithETH{value: 0.1 ether}(
            0.9 ether, // minLuxOut (0.1 ETH * 10 rate = 1 LUX)
            sessionId
        );

        assertTrue(requestId != bytes32(0));
    }

    function test_PaymentRouter_GetQuote() public {
        // For WLUX, should return attestation cost directly
        uint256 luxQuote = paymentRouter.getPaymentQuote(address(wlux));
        assertEq(luxQuote, 1 ether);

        // For WETH, should calculate based on exchange rate
        uint256 ethQuote = paymentRouter.getPaymentQuote(address(weth));
        assertEq(ethQuote, 0.1 ether); // 1 LUX / 10 rate = 0.1 ETH
    }

    // ==================== Full Flow Integration Test ====================

    function test_FullFlow_PayMintTeleportClaim() public {
        console.log("=== Full AI Mining Flow Test ===");

        // 1. User pays for attestation on C-Chain
        console.log("1. User pays for attestation with LUX");
        wlux.mint(user, 10 ether);

        bytes32 sessionId = keccak256("full-flow-session");

        vm.startPrank(user);
        wlux.approve(address(paymentRouter), 10 ether);
        bytes32 requestId = paymentRouter.payForAttestation(address(wlux), 1 ether, 1 ether, sessionId);
        vm.stopPrank();

        console.log("   Request ID:", vm.toString(requestId));

        // 2. Simulate payment received on A-Chain (would normally be via Warp)
        console.log("2. Payment received on A-Chain (simulated)");

        // 3. Miner starts compute session on A-Chain
        console.log("3. Miner starts GPU compute session");

        bytes memory teeQuote = hex"deadbeefcafebabe1234567890abcdef";
        bytes32 gpuId = keccak256("nvidia-h100-12345");

        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, gpuId, uint8(PrivacyLevel.Confidential));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        console.log("   Session started at:", block.timestamp);

        // 4. Miner submits heartbeats over 5 minutes
        console.log("4. Miner submits heartbeats");

        uint256 totalMined = 0;
        uint256 currentTime = block.timestamp;
        for (uint i = 0; i < 5; i++) {
            currentTime += 60;
            vm.warp(currentTime);
            vm.prank(miner);
            uint256 reward = aiNative.heartbeat(sessionId);
            totalMined += reward;
            console.log("   Heartbeat reward:", reward / 1e18, "AI");
        }

        // 5. Miner completes session
        console.log("5. Miner completes session");

        currentTime += 30;
        vm.warp(currentTime); // Additional 30 seconds

        vm.prank(miner);
        uint256 finalReward = aiNative.completeSession(sessionId);
        totalMined += finalReward;

        console.log("   Final reward:", finalReward / 1e18, "AI");
        console.log("   Total mined:", totalMined / 1e18, "AI");

        uint256 minerBalance = aiNative.balanceOf(miner);
        assertEq(minerBalance, totalMined);
        console.log("   Miner A-Chain balance:", minerBalance / 1e18, "AI");

        // 6. Miner teleports AI to C-Chain
        console.log("6. Miner teleports AI to C-Chain");

        uint256 teleportAmount = 3 ether;

        vm.prank(miner);
        bytes32 teleportId = aiNative.teleport(C_CHAIN_ID, miner, teleportAmount);

        console.log("   Teleport ID:", vm.toString(teleportId));
        console.log("   Teleported:", teleportAmount / 1e18, "AI");

        // 7. Miner claims on C-Chain
        console.log("7. Miner claims teleport on C-Chain");

        // Set up the warp message for claiming
        vm.etch(0x0200000000000000000000000000000000000005, address(warpC).code);

        MockWarp(0x0200000000000000000000000000000000000005).setVerifiedMessage(
            0,
            A_CHAIN_ID,
            address(aiNative),
            abi.encode(miner, teleportAmount),
            true
        );

        vm.prank(miner);
        uint256 claimed = aiRemote.claimTeleport(0);

        console.log("   Claimed:", claimed / 1e18, "AI");
        console.log("   Miner C-Chain balance:", aiRemote.balanceOf(miner) / 1e18, "AI");

        assertEq(aiRemote.balanceOf(miner), teleportAmount);

        console.log("=== Full Flow Complete ===");
    }

    // ==================== Edge Case Tests ====================

    function test_RevertWhen_HeartbeatTooEarly() public {
        bytes32 sessionId = keccak256("early-heartbeat");
        bytes memory teeQuote = hex"5555555555555555";

        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, keccak256("gpu"), uint8(PrivacyLevel.Confidential));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        // Try heartbeat immediately (should fail)
        vm.expectRevert(abi.encodeWithSelector(AINative.HeartbeatTooEarly.selector, sessionId));
        vm.prank(miner);
        aiNative.heartbeat(sessionId);
    }

    function test_RevertWhen_DoubleStartSession() public {
        bytes32 sessionId = keccak256("double-start");
        bytes memory teeQuote = hex"6666666666666666";

        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(teeQuote, keccak256("gpu"), uint8(PrivacyLevel.Confidential));

        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);

        // Try to start again (should fail)
        vm.expectRevert(abi.encodeWithSelector(AINative.SessionAlreadyActive.selector, sessionId));
        vm.prank(miner);
        aiNative.startSession(sessionId, teeQuote);
    }

    function test_RevertWhen_ClaimTeleportTwice() public {
        vm.etch(0x0200000000000000000000000000000000000005, address(warpC).code);

        MockWarp(0x0200000000000000000000000000000000000005).setVerifiedMessage(
            0,
            A_CHAIN_ID,
            address(aiNative),
            abi.encode(user, 1 ether),
            true
        );

        vm.prank(user);
        aiRemote.claimTeleport(0);

        // Calculate teleport ID for revert check
        bytes32 teleportId = keccak256(abi.encode(A_CHAIN_ID, address(aiNative), abi.encode(user, 1 ether)));

        // Try to claim again (should fail)
        vm.expectRevert(abi.encodeWithSelector(AIRemote.TeleportAlreadyClaimed.selector, teleportId));
        vm.prank(user);
        aiRemote.claimTeleport(0);
    }

    function test_RevertWhen_InsufficientPayment() public {
        wlux.mint(user, 0.5 ether);

        vm.startPrank(user);
        wlux.approve(address(paymentRouter), 0.5 ether);

        // Try to pay with less than attestation cost (should fail)
        vm.expectRevert(AIPaymentRouter.InsufficientPayment.selector);
        paymentRouter.payForAttestation(address(wlux), 0.5 ether, 0.5 ether, keccak256("fail"));
        vm.stopPrank();
    }

    // ==================== Privacy Level Tests ====================

    function test_PrivacyLevelMultipliers() public {
        bytes32 gpuId = keccak256("gpu");
        uint256 currentTime = block.timestamp;

        // Test Public (0.25x)
        bytes memory quotePublic = hex"1111111111111111";
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(quotePublic, gpuId, uint8(PrivacyLevel.Public));

        bytes32 sessionPublic = keccak256("session-public");
        vm.prank(miner);
        aiNative.startSession(sessionPublic, quotePublic);
        currentTime += 60;
        vm.warp(currentTime);
        vm.prank(miner);
        uint256 rewardPublic = aiNative.heartbeat(sessionPublic);
        assertEq(rewardPublic, 0.25 ether); // 0.25x

        // Test Private (0.5x)
        bytes memory quotePrivate = hex"2222222222222222";
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(quotePrivate, gpuId, uint8(PrivacyLevel.Private));

        bytes32 sessionPrivate = keccak256("session-private");
        address miner2 = makeAddr("miner2");
        vm.prank(miner2);
        aiNative.startSession(sessionPrivate, quotePrivate);
        currentTime += 60;
        vm.warp(currentTime);
        vm.prank(miner2);
        uint256 rewardPrivate = aiNative.heartbeat(sessionPrivate);
        assertEq(rewardPrivate, 0.5 ether); // 0.5x

        // Test Confidential (1.0x)
        bytes memory quoteConfidential = hex"3333333333333333";
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(quoteConfidential, gpuId, uint8(PrivacyLevel.Confidential));

        bytes32 sessionConfidential = keccak256("session-confidential");
        address miner3 = makeAddr("miner3");
        vm.prank(miner3);
        aiNative.startSession(sessionConfidential, quoteConfidential);
        currentTime += 60;
        vm.warp(currentTime);
        vm.prank(miner3);
        uint256 rewardConfidential = aiNative.heartbeat(sessionConfidential);
        assertEq(rewardConfidential, 1 ether); // 1.0x

        // Test Sovereign (1.5x)
        bytes memory quoteSovereign = hex"4444444444444444";
        vm.prank(admin);
        MockAttestation(address(0x0300)).setValidQuote(quoteSovereign, gpuId, uint8(PrivacyLevel.Sovereign));

        bytes32 sessionSovereign = keccak256("session-sovereign");
        address miner4 = makeAddr("miner4");
        vm.prank(miner4);
        aiNative.startSession(sessionSovereign, quoteSovereign);
        currentTime += 60;
        vm.warp(currentTime);
        vm.prank(miner4);
        uint256 rewardSovereign = aiNative.heartbeat(sessionSovereign);
        assertEq(rewardSovereign, 1.5 ether); // 1.5x
    }
}
