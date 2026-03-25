// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {
    CCTPAdapter,
    ITokenMessenger,
    IMessageTransmitter
} from "../../contracts/integrations/bridges/CCTPAdapter.sol";
import { BridgeParams, BridgeRoute, BridgeStatus } from "../../contracts/interfaces/adapters/IBridgeAdapter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000e6); // USDC has 6 decimals
    }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockTokenMessenger is ITokenMessenger {
    uint64 private _nonce;
    bool public depositCalled;
    uint256 public lastAmount;
    uint32 public lastDestDomain;
    bytes32 public lastMintRecipient;
    address public lastBurnToken;
    address public mockTransmitter;

    constructor(address _transmitter) {
        mockTransmitter = _transmitter;
    }

    function depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        external
        override
        returns (uint64 nonce)
    {
        depositCalled = true;
        lastAmount = amount;
        lastDestDomain = destinationDomain;
        lastMintRecipient = mintRecipient;
        lastBurnToken = burnToken;
        nonce = ++_nonce;
    }

    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32
    ) external override returns (uint64 nonce) {
        depositCalled = true;
        lastAmount = amount;
        lastDestDomain = destinationDomain;
        lastMintRecipient = mintRecipient;
        lastBurnToken = burnToken;
        nonce = ++_nonce;
    }

    function localMessageTransmitter() external view override returns (address) {
        return mockTransmitter;
    }
}

contract MockMessageTransmitter is IMessageTransmitter {
    bool public receiveCalled;
    bool public shouldSucceed = true;
    uint64 private _nonce = 1;

    function setSuccess(bool _success) external {
        shouldSucceed = _success;
    }

    function receiveMessage(bytes calldata, bytes calldata) external override returns (bool success) {
        receiveCalled = true;
        return shouldSucceed;
    }

    function nextAvailableNonce() external view override returns (uint64) {
        return _nonce;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract CCTPAdapterTest is Test {
    CCTPAdapter public adapter;
    MockTokenMessenger public tokenMessenger;
    MockMessageTransmitter public messageTransmitter;
    MockUSDC public usdcToken;

    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);

    uint256 constant ARB_CHAIN_ID = 42161;
    uint32 constant ARB_DOMAIN = 3;
    uint256 constant AVAX_CHAIN_ID = 43114;
    uint32 constant AVAX_DOMAIN = 1;

    function setUp() public {
        vm.startPrank(admin);
        messageTransmitter = new MockMessageTransmitter();
        tokenMessenger = new MockTokenMessenger(address(messageTransmitter));
        usdcToken = new MockUSDC();

        adapter = new CCTPAdapter(address(tokenMessenger), address(messageTransmitter), address(usdcToken), admin);

        // Configure chains
        adapter.addChain(ARB_CHAIN_ID, ARB_DOMAIN);
        adapter.addChain(AVAX_CHAIN_ID, AVAX_DOMAIN);

        // Set destination USDC addresses
        adapter.setDestUsdc(ARB_CHAIN_ID, address(0xABCD));
        adapter.setDestUsdc(AVAX_CHAIN_ID, address(0xEF01));

        // Fund alice
        usdcToken.transfer(alice, 100_000e6);
        vm.stopPrank();
    }

    // ─── Deployment ──────────────────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(adapter.protocol(), "Circle CCTP");
        assertEq(adapter.version(), "1.0.0");
        assertEq(adapter.endpoint(), address(tokenMessenger));
        assertEq(adapter.chainId(), block.chainid);
        assertEq(adapter.usdc(), address(usdcToken));
    }

    function test_revert_zeroAddressConstructor() public {
        vm.expectRevert(CCTPAdapter.ZeroAddress.selector);
        new CCTPAdapter(address(0), address(messageTransmitter), address(usdcToken), admin);

        vm.expectRevert(CCTPAdapter.ZeroAddress.selector);
        new CCTPAdapter(address(tokenMessenger), address(0), address(usdcToken), admin);

        vm.expectRevert(CCTPAdapter.ZeroAddress.selector);
        new CCTPAdapter(address(tokenMessenger), address(messageTransmitter), address(0), admin);

        vm.expectRevert(CCTPAdapter.ZeroAddress.selector);
        new CCTPAdapter(address(tokenMessenger), address(messageTransmitter), address(usdcToken), address(0));
    }

    // ─── Chain Config ────────────────────────────────────────────────────────

    function test_chainConfig() public view {
        assertEq(adapter.chainIdToDomain(ARB_CHAIN_ID), ARB_DOMAIN);
        assertEq(adapter.domainToChainId(ARB_DOMAIN), ARB_CHAIN_ID);
        assertEq(adapter.chainIdToDomain(AVAX_CHAIN_ID), AVAX_DOMAIN);
        assertEq(adapter.domainToChainId(AVAX_DOMAIN), AVAX_CHAIN_ID);
        uint256[] memory chains = adapter.supportedChains();
        assertEq(chains.length, 2);
    }

    // ─── Route Support ───────────────────────────────────────────────────────

    function test_isRouteSupported() public view {
        assertTrue(adapter.isRouteSupported(ARB_CHAIN_ID, address(usdcToken)));
        assertTrue(adapter.isRouteSupported(AVAX_CHAIN_ID, address(usdcToken)));
        // Non-USDC token is not supported
        assertFalse(adapter.isRouteSupported(ARB_CHAIN_ID, address(0x1)));
        // Unsupported chain
        assertFalse(adapter.isRouteSupported(999, address(usdcToken)));
    }

    function test_getRoute() public view {
        BridgeRoute memory route = adapter.getRoute(ARB_CHAIN_ID, address(usdcToken));
        assertTrue(route.isActive);
        assertEq(route.dstToken, address(0xABCD));
        assertEq(route.estimatedTime, 780);
        assertEq(route.srcChainId, block.chainid);
    }

    function test_getRoute_inactive_wrongToken() public view {
        BridgeRoute memory route = adapter.getRoute(ARB_CHAIN_ID, address(0x1));
        assertFalse(route.isActive);
    }

    function test_getRoutes_empty() public view {
        BridgeRoute[] memory routes = adapter.getRoutes();
        assertEq(routes.length, 0);
    }

    // ─── Fee Estimation ──────────────────────────────────────────────────────

    function test_estimateFees() public view {
        (uint256 bridgeFee, uint256 protocolFee) = adapter.estimateFees(ARB_CHAIN_ID, address(usdcToken), 1000e6);
        assertEq(bridgeFee, 0);
        assertEq(protocolFee, 0);
    }

    function test_estimateFees_revert_unsupportedChain() public {
        vm.expectRevert(abi.encodeWithSelector(CCTPAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.estimateFees(999, address(usdcToken), 1000e6);
    }

    function test_estimateFees_revert_unsupportedToken() public {
        vm.expectRevert(abi.encodeWithSelector(CCTPAdapter.UnsupportedToken.selector, address(0x1)));
        adapter.estimateFees(ARB_CHAIN_ID, address(0x1), 1000e6);
    }

    function test_estimateOutput() public view {
        assertEq(adapter.estimateOutput(ARB_CHAIN_ID, address(usdcToken), 1000e6), 1000e6);
    }

    function test_estimateTime() public view {
        assertEq(adapter.estimateTime(ARB_CHAIN_ID), 780);
    }

    // ─── Bridge ──────────────────────────────────────────────────────────────

    function test_bridge() public {
        vm.startPrank(alice);
        usdcToken.approve(address(adapter), 1000e6);

        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(usdcToken),
            amount: 1000e6,
            recipient: bob,
            minAmountOut: 1000e6,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(usdcToken.balanceOf(alice), 99_000e6);
        assertTrue(tokenMessenger.depositCalled());
        assertEq(tokenMessenger.lastAmount(), 1000e6);
        assertEq(tokenMessenger.lastDestDomain(), ARB_DOMAIN);
        assertEq(tokenMessenger.lastMintRecipient(), bytes32(uint256(uint160(bob))));
        assertEq(tokenMessenger.lastBurnToken(), address(usdcToken));
    }

    function test_bridge_toAvalanche() public {
        vm.startPrank(alice);
        usdcToken.approve(address(adapter), 5000e6);

        BridgeParams memory params = BridgeParams({
            dstChainId: AVAX_CHAIN_ID,
            token: address(usdcToken),
            amount: 5000e6,
            recipient: bob,
            minAmountOut: 5000e6,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(tokenMessenger.lastDestDomain(), AVAX_DOMAIN);
    }

    function test_bridge_revert_zeroAmount() public {
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(usdcToken),
            amount: 0,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(CCTPAdapter.ZeroAmount.selector);
        adapter.bridge(params);
    }

    function test_bridge_revert_unsupportedToken() public {
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(0x1234), // not USDC
            amount: 1000e6,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(CCTPAdapter.UnsupportedToken.selector, address(0x1234)));
        adapter.bridge(params);
    }

    function test_bridge_revert_unsupportedChain() public {
        vm.startPrank(alice);
        usdcToken.approve(address(adapter), 1000e6);

        BridgeParams memory params = BridgeParams({
            dstChainId: 999, token: address(usdcToken), amount: 1000e6, recipient: alice, minAmountOut: 0, extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(CCTPAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.bridge(params);
        vm.stopPrank();
    }

    // ─── Bridge Status ───────────────────────────────────────────────────────

    function test_getStatus() public {
        vm.startPrank(alice);
        usdcToken.approve(address(adapter), 1000e6);

        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(usdcToken),
            amount: 1000e6,
            recipient: bob,
            minAmountOut: 1000e6,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.srcChainId, block.chainid);
        assertEq(status.dstChainId, ARB_CHAIN_ID);
        assertEq(status.amount, 1000e6);
        assertEq(status.sender, alice);
        assertEq(status.recipient, bob);
        assertEq(status.status, 1);
        assertEq(status.token, address(usdcToken));
    }

    // ─── Receive Message ─────────────────────────────────────────────────────

    function test_receiveMessage() public {
        bytes memory message = hex"deadbeef";
        bytes memory attestation = hex"cafebabe";

        bool success = adapter.receiveMessage(message, attestation);
        assertTrue(success);
        assertTrue(messageTransmitter.receiveCalled());
    }

    function test_receiveMessage_revert_failed() public {
        messageTransmitter.setSuccess(false);

        bytes memory message = hex"deadbeef";
        bytes memory attestation = hex"cafebabe";

        vm.expectRevert(CCTPAdapter.ReceiveFailed.selector);
        adapter.receiveMessage(message, attestation);
    }

    // ─── Admin Access Control ────────────────────────────────────────────────

    function test_onlyAdminCanAddChain() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.addChain(10, 2);
    }

    function test_onlyAdminCanSetDestUsdc() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setDestUsdc(ARB_CHAIN_ID, address(0x1));
    }

    function test_setDestUsdc() public {
        vm.prank(admin);
        adapter.setDestUsdc(ARB_CHAIN_ID, address(0x9999));
        assertEq(adapter.destUsdc(ARB_CHAIN_ID), address(0x9999));
    }

    // ─── Receive native tokens ───────────────────────────────────────────────

    function test_receiveNative() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(adapter).call{ value: 0.1 ether }("");
        assertTrue(ok);
    }

    receive() external payable { }
}
