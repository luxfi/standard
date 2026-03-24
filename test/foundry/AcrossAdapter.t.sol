// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {
    AcrossAdapter,
    ISpokePool
} from "../../contracts/integrations/bridges/AcrossAdapter.sol";
import {BridgeParams, BridgeRoute, BridgeStatus} from "../../contracts/interfaces/adapters/IBridgeAdapter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockAcrossToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1_000_000e18);
    }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract MockSpokePool is ISpokePool {
    bool public depositCalled;
    address public lastDepositor;
    address public lastRecipient;
    address public lastInputToken;
    address public lastOutputToken;
    uint256 public lastInputAmount;
    uint256 public lastOutputAmount;
    uint256 public lastDestChainId;
    uint32 public lastFillDeadline;

    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address,
        uint32,
        uint32 fillDeadline,
        uint32,
        bytes calldata
    ) external payable override {
        depositCalled = true;
        lastDepositor = depositor;
        lastRecipient = recipient;
        lastInputToken = inputToken;
        lastOutputToken = outputToken;
        lastInputAmount = inputAmount;
        lastOutputAmount = outputAmount;
        lastDestChainId = destinationChainId;
        lastFillDeadline = fillDeadline;
    }

    function getCurrentTime() external view override returns (uint256) {
        return block.timestamp;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract AcrossAdapterTest is Test {
    AcrossAdapter public adapter;
    MockSpokePool public spokePool;
    MockAcrossToken public token;

    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);

    uint256 constant ARB_CHAIN_ID = 42161;

    function setUp() public {
        vm.startPrank(admin);
        spokePool = new MockSpokePool();
        adapter = new AcrossAdapter(address(spokePool), admin);
        token = new MockAcrossToken();

        // Configure chain
        adapter.addChain(ARB_CHAIN_ID);

        // Configure token mapping
        adapter.setTokenMapping(address(token), ARB_CHAIN_ID, address(0xDEAD));

        // Fund alice
        token.transfer(alice, 10_000e18);
        vm.stopPrank();
    }

    // ─── Deployment ──────────────────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(adapter.protocol(), "Across V3");
        assertEq(adapter.version(), "1.0.0");
        assertEq(adapter.endpoint(), address(spokePool));
        assertEq(adapter.chainId(), block.chainid);
    }

    function test_revert_zeroAddressConstructor() public {
        vm.expectRevert(AcrossAdapter.ZeroAddress.selector);
        new AcrossAdapter(address(0), admin);

        vm.expectRevert(AcrossAdapter.ZeroAddress.selector);
        new AcrossAdapter(address(spokePool), address(0));
    }

    // ─── Chain Config ────────────────────────────────────────────────────────

    function test_chainConfig() public view {
        assertTrue(adapter.isSupportedChain(ARB_CHAIN_ID));
        assertFalse(adapter.isSupportedChain(999));
        uint256[] memory chains = adapter.supportedChains();
        assertEq(chains.length, 1);
        assertEq(chains[0], ARB_CHAIN_ID);
    }

    function test_removeChain() public {
        vm.prank(admin);
        adapter.removeChain(ARB_CHAIN_ID);
        assertFalse(adapter.isSupportedChain(ARB_CHAIN_ID));
    }

    // ─── Route Support ───────────────────────────────────────────────────────

    function test_isRouteSupported() public view {
        assertTrue(adapter.isRouteSupported(ARB_CHAIN_ID, address(token)));
        assertFalse(adapter.isRouteSupported(999, address(token)));
        assertFalse(adapter.isRouteSupported(ARB_CHAIN_ID, address(0x1)));
    }

    function test_getRoute() public view {
        BridgeRoute memory route = adapter.getRoute(ARB_CHAIN_ID, address(token));
        assertTrue(route.isActive);
        assertEq(route.dstToken, address(0xDEAD));
        assertEq(route.estimatedTime, 120);
    }

    function test_getRoutes_empty() public view {
        BridgeRoute[] memory routes = adapter.getRoutes();
        assertEq(routes.length, 0);
    }

    // ─── Fee Estimation ──────────────────────────────────────────────────────

    function test_estimateFees() public view {
        // 0.1% of 100e18 = 0.1e18
        (uint256 bridgeFee, uint256 protocolFee) = adapter.estimateFees(ARB_CHAIN_ID, address(token), 100e18);
        assertEq(bridgeFee, 0.1e18);
        assertEq(protocolFee, 0);
    }

    function test_estimateFees_revert_unsupportedChain() public {
        vm.expectRevert(abi.encodeWithSelector(AcrossAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.estimateFees(999, address(token), 100e18);
    }

    function test_estimateOutput() public view {
        // 100e18 - 0.1% = 99.9e18
        assertEq(adapter.estimateOutput(ARB_CHAIN_ID, address(token), 100e18), 99.9e18);
    }

    function test_estimateTime() public view {
        assertEq(adapter.estimateTime(ARB_CHAIN_ID), 120);
    }

    // ─── Bridge ──────────────────────────────────────────────────────────────

    function test_bridge() public {
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 99e18,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(token.balanceOf(alice), 9_900e18);
        assertTrue(spokePool.depositCalled());
        assertEq(spokePool.lastRecipient(), bob);
        assertEq(spokePool.lastInputAmount(), 100e18);
        // 100e18 - 0.1% = 99.9e18
        assertEq(spokePool.lastOutputAmount(), 99.9e18);
        assertEq(spokePool.lastDestChainId(), ARB_CHAIN_ID);
    }

    function test_bridge_revert_zeroAmount() public {
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(token),
            amount: 0,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(AcrossAdapter.ZeroAmount.selector);
        adapter.bridge(params);
    }

    function test_bridge_revert_unsupportedChain() public {
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: 999,
            token: address(token),
            amount: 100e18,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(AcrossAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.bridge(params);
        vm.stopPrank();
    }

    function test_bridge_revert_unsupportedToken() public {
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(0x1234),
            amount: 100e18,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(AcrossAdapter.UnsupportedToken.selector, address(0x1234), ARB_CHAIN_ID));
        adapter.bridge(params);
    }

    function test_bridge_revert_belowMinOutput() public {
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 100e18, // 100e18 > 99.9e18 output
            extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(AcrossAdapter.BelowMinOutput.selector, 99.9e18, 100e18));
        adapter.bridge(params);
        vm.stopPrank();
    }

    // ─── Bridge Status ───────────────────────────────────────────────────────

    function test_getStatus() public {
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ARB_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 99e18,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.srcChainId, block.chainid);
        assertEq(status.dstChainId, ARB_CHAIN_ID);
        assertEq(status.amount, 100e18);
        assertEq(status.sender, alice);
        assertEq(status.recipient, bob);
        assertEq(status.status, 1);
    }

    // ─── Admin Access Control ────────────────────────────────────────────────

    function test_onlyAdminCanAddChain() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.addChain(42);
    }

    function test_onlyAdminCanRemoveChain() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.removeChain(ARB_CHAIN_ID);
    }

    function test_onlyAdminCanSetTokenMapping() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setTokenMapping(address(token), 42, address(0x1));
    }

    function test_setFillDeadlineOffset() public {
        vm.prank(admin);
        adapter.setFillDeadlineOffset(3600);
        assertEq(adapter.defaultFillDeadlineOffset(), 3600);
    }

    function test_setRelayerFeeBps() public {
        vm.prank(admin);
        adapter.setRelayerFeeBps(50); // 0.5%
        assertEq(adapter.defaultRelayerFeeBps(), 50);
    }

    // ─── Receive native tokens ───────────────────────────────────────────────

    function test_receiveNative() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(adapter).call{value: 0.1 ether}("");
        assertTrue(ok);
    }

    receive() external payable {}
}
