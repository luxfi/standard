// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {
    LayerZeroAdapter,
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingReceipt,
    MessagingFee,
    Origin
} from "../../contracts/integrations/bridges/LayerZeroAdapter.sol";
import { BridgeParams, BridgeRoute, BridgeStatus } from "../../contracts/interfaces/adapters/IBridgeAdapter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockLZToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

contract MockLZEndpoint is ILayerZeroEndpointV2 {
    uint64 private _nonce;
    uint256 public constant NATIVE_FEE = 0.005 ether;

    function send(MessagingParams calldata, address)
        external
        payable
        override
        returns (MessagingReceipt memory receipt)
    {
        _nonce++;
        receipt.guid = keccak256(abi.encodePacked(_nonce, block.timestamp));
        receipt.nonce = _nonce;
        receipt.fee = MessagingFee({ nativeFee: NATIVE_FEE, lzTokenFee: 0 });
    }

    function quote(MessagingParams calldata, address) external pure override returns (MessagingFee memory fee) {
        fee = MessagingFee({ nativeFee: NATIVE_FEE, lzTokenFee: 0 });
    }

    function setDelegate(address) external override { }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract LayerZeroAdapterTest is Test {
    LayerZeroAdapter public adapter;
    MockLZEndpoint public lzEndpoint;
    MockLZToken public token;

    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);

    uint256 constant ETH_CHAIN_ID = 1;
    uint32 constant ETH_EID = 30101; // Ethereum LZ V2 endpoint ID

    function setUp() public {
        vm.startPrank(admin);
        lzEndpoint = new MockLZEndpoint();
        adapter = new LayerZeroAdapter(address(lzEndpoint), admin);
        token = new MockLZToken();

        // Configure chain
        adapter.addChain(ETH_CHAIN_ID, ETH_EID);

        // Configure token mapping
        adapter.setTokenMapping(address(token), ETH_CHAIN_ID, address(0xDEAD));

        // Set trusted remote
        adapter.setTrustedRemote(ETH_CHAIN_ID, address(0xBEEF));

        // Fund alice
        token.transfer(alice, 10_000e18);
        vm.stopPrank();
    }

    // ─── Deployment ──────────────────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(adapter.protocol(), "LayerZero V2");
        assertEq(adapter.version(), "1.0.0");
        assertEq(adapter.endpoint(), address(lzEndpoint));
        assertEq(adapter.chainId(), block.chainid);
    }

    function test_revert_zeroAddressConstructor() public {
        vm.expectRevert(LayerZeroAdapter.ZeroAddress.selector);
        new LayerZeroAdapter(address(0), admin);

        vm.expectRevert(LayerZeroAdapter.ZeroAddress.selector);
        new LayerZeroAdapter(address(lzEndpoint), address(0));
    }

    // ─── Chain Config ────────────────────────────────────────────────────────

    function test_chainConfig() public view {
        assertEq(adapter.chainIdToEid(ETH_CHAIN_ID), ETH_EID);
        assertEq(adapter.eidToChainId(ETH_EID), ETH_CHAIN_ID);
        uint256[] memory chains = adapter.supportedChains();
        assertEq(chains.length, 1);
        assertEq(chains[0], ETH_CHAIN_ID);
    }

    // ─── Route Support ───────────────────────────────────────────────────────

    function test_isRouteSupported() public view {
        assertTrue(adapter.isRouteSupported(ETH_CHAIN_ID, address(token)));
        assertFalse(adapter.isRouteSupported(999, address(token)));
        assertFalse(adapter.isRouteSupported(ETH_CHAIN_ID, address(0x1)));
    }

    function test_getRoute() public view {
        BridgeRoute memory route = adapter.getRoute(ETH_CHAIN_ID, address(token));
        assertTrue(route.isActive);
        assertEq(route.dstToken, address(0xDEAD));
        assertEq(route.estimatedTime, 60);
        assertEq(route.srcChainId, block.chainid);
    }

    function test_getRoutes_empty() public view {
        BridgeRoute[] memory routes = adapter.getRoutes();
        assertEq(routes.length, 0);
    }

    // ─── Fee Estimation ──────────────────────────────────────────────────────

    function test_estimateFees() public view {
        (uint256 bridgeFee, uint256 protocolFee) = adapter.estimateFees(ETH_CHAIN_ID, address(token), 100e18);
        assertEq(bridgeFee, 0.005 ether);
        assertEq(protocolFee, 0);
    }

    function test_estimateFees_revert_unsupportedChain() public {
        vm.expectRevert(abi.encodeWithSelector(LayerZeroAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.estimateFees(999, address(token), 100e18);
    }

    function test_estimateOutput() public view {
        assertEq(adapter.estimateOutput(ETH_CHAIN_ID, address(token), 100e18), 100e18);
    }

    function test_estimateTime() public view {
        assertEq(adapter.estimateTime(ETH_CHAIN_ID), 60);
    }

    // ─── Bridge ──────────────────────────────────────────────────────────────

    function test_bridge() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 100e18,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge{ value: 0.005 ether }(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(token.balanceOf(alice), 9_900e18);
        assertEq(token.balanceOf(address(adapter)), 100e18);
    }

    function test_bridge_revert_zeroAmount() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID, token: address(token), amount: 0, recipient: alice, minAmountOut: 0, extraData: ""
        });

        vm.expectRevert(LayerZeroAdapter.ZeroAmount.selector);
        adapter.bridge{ value: 0.005 ether }(params);
    }

    function test_bridge_revert_unsupportedChain() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: 999, token: address(token), amount: 100e18, recipient: alice, minAmountOut: 0, extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(LayerZeroAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.bridge{ value: 0.005 ether }(params);
        vm.stopPrank();
    }

    function test_bridge_revert_unsupportedToken() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID,
            token: address(0x1234),
            amount: 100e18,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(LayerZeroAdapter.UnsupportedToken.selector, address(0x1234), ETH_CHAIN_ID)
        );
        adapter.bridge{ value: 0.005 ether }(params);
    }

    // ─── Bridge Status ───────────────────────────────────────────────────────

    function test_getStatus() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 100e18,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge{ value: 0.005 ether }(params);
        vm.stopPrank();

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.srcChainId, block.chainid);
        assertEq(status.dstChainId, ETH_CHAIN_ID);
        assertEq(status.amount, 100e18);
        assertEq(status.sender, alice);
        assertEq(status.recipient, bob);
        assertEq(status.status, 1);
    }

    // ─── LZ Receive ─────────────────────────────────────────────────────────

    function test_lzReceive() public {
        // Fund adapter with tokens to release
        vm.prank(admin);
        token.transfer(address(adapter), 50e18);

        bytes memory payload = abi.encode(bob, address(token), 50e18, bytes(""));
        Origin memory origin = Origin({ srcEid: ETH_EID, sender: bytes32(uint256(uint160(address(0xBEEF)))), nonce: 1 });

        vm.prank(address(lzEndpoint));
        adapter.lzReceive(origin, bytes32(uint256(1)), payload, address(0), "");

        assertEq(token.balanceOf(bob), 50e18);
    }

    function test_lzReceive_revert_onlyEndpoint() public {
        Origin memory origin = Origin({ srcEid: ETH_EID, sender: bytes32(0), nonce: 1 });

        vm.prank(alice);
        vm.expectRevert(LayerZeroAdapter.OnlyEndpoint.selector);
        adapter.lzReceive(origin, bytes32(0), "", address(0), "");
    }

    function test_lzReceive_revert_untrustedSender() public {
        Origin memory origin = Origin({
            srcEid: ETH_EID,
            sender: bytes32(uint256(uint160(address(0xDEAD)))), // not trusted
            nonce: 1
        });

        vm.prank(address(lzEndpoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                LayerZeroAdapter.UntrustedSender.selector, ETH_EID, bytes32(uint256(uint160(address(0xDEAD))))
            )
        );
        adapter.lzReceive(origin, bytes32(0), abi.encode(bob, address(token), 50e18, bytes("")), address(0), "");
    }

    // ─── Admin Access Control ────────────────────────────────────────────────

    function test_onlyAdminCanAddChain() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.addChain(42, 30142);
    }

    function test_onlyAdminCanSetTokenMapping() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setTokenMapping(address(token), 42, address(0x1));
    }

    function test_onlyAdminCanSetTrustedRemote() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setTrustedRemote(42, address(0x1));
    }

    function test_setDefaultGasLimit() public {
        vm.prank(admin);
        adapter.setDefaultGasLimit(500_000);
        assertEq(adapter.defaultGasLimit(), 500_000);
    }

    // ─── Receive native tokens ───────────────────────────────────────────────

    function test_receiveNative() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(adapter).call{ value: 0.1 ether }("");
        assertTrue(ok);
        assertEq(address(adapter).balance, 0.1 ether);
    }

    receive() external payable { }
}
