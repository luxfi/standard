// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { CCIPAdapter } from "../../contracts/integrations/bridges/CCIPAdapter.sol";
import { IRouterClient } from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import { BridgeParams, BridgeRoute, BridgeStatus } from "../../contracts/interfaces/adapters/IBridgeAdapter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

contract MockCCIPRouter is IRouterClient {
    bytes32 public lastMessageId;
    uint256 private _nonce;

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0.01 ether;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage calldata) external payable returns (bytes32) {
        lastMessageId = keccak256(abi.encodePacked(_nonce++, block.timestamp));
        return lastMessageId;
    }
}

contract CCIPAdapterTest is Test {
    CCIPAdapter public adapter;
    MockCCIPRouter public router;
    MockToken public token;

    address admin = address(0xA);
    address alice = address(0xB);

    uint256 constant ETH_CHAIN_ID = 1;
    uint64 constant ETH_SELECTOR = 5009297550715157269; // Ethereum mainnet CCIP selector

    function setUp() public {
        vm.startPrank(admin);
        router = new MockCCIPRouter();
        adapter = new CCIPAdapter(address(router), admin);
        token = new MockToken();

        // Configure chain
        adapter.addChain(ETH_CHAIN_ID, ETH_SELECTOR);

        // Configure token mapping
        adapter.setTokenMapping(address(token), ETH_CHAIN_ID, address(0xDEAD)); // dest token

        // Fund alice
        token.transfer(alice, 10_000e18);
        vm.stopPrank();
    }

    function test_deployment() public view {
        assertEq(adapter.protocol(), "Chainlink CCIP");
        assertEq(adapter.version(), "1.0.0");
        assertEq(adapter.endpoint(), address(router));
    }

    function test_chainConfig() public view {
        assertEq(adapter.chainIdToSelector(ETH_CHAIN_ID), ETH_SELECTOR);
        assertEq(adapter.selectorToChainId(ETH_SELECTOR), ETH_CHAIN_ID);
        uint256[] memory chains = adapter.supportedChains();
        assertEq(chains.length, 1);
        assertEq(chains[0], ETH_CHAIN_ID);
    }

    function test_isRouteSupported() public view {
        assertTrue(adapter.isRouteSupported(ETH_CHAIN_ID, address(token)));
        assertFalse(adapter.isRouteSupported(999, address(token)));
        assertFalse(adapter.isRouteSupported(ETH_CHAIN_ID, address(0x1)));
    }

    function test_estimateFees() public view {
        (uint256 bridgeFee,) = adapter.estimateFees(ETH_CHAIN_ID, address(token), 100e18);
        assertEq(bridgeFee, 0.01 ether);
    }

    function test_estimateOutput() public view {
        assertEq(adapter.estimateOutput(ETH_CHAIN_ID, address(token), 100e18), 100e18);
    }

    function test_bridge() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: alice,
            minAmountOut: 100e18,
            extraData: abi.encode(alice)
        });

        bytes32 bridgeId = adapter.bridge{ value: 0.01 ether }(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(token.balanceOf(alice), 9_900e18);
    }

    function test_bridge_revert_unsupportedChain() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: 999,
            token: address(token),
            amount: 100e18,
            recipient: alice,
            minAmountOut: 100e18,
            extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(CCIPAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.bridge{ value: 0.01 ether }(params);
        vm.stopPrank();
    }

    function test_bridge_revert_zeroAmount() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID, token: address(token), amount: 0, recipient: alice, minAmountOut: 0, extraData: ""
        });

        vm.expectRevert(CCIPAdapter.ZeroAmount.selector);
        adapter.bridge{ value: 0.01 ether }(params);
    }

    function test_getStatus() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID,
            token: address(token),
            amount: 100e18,
            recipient: alice,
            minAmountOut: 100e18,
            extraData: abi.encode(alice)
        });

        bytes32 bridgeId = adapter.bridge{ value: 0.01 ether }(params);
        vm.stopPrank();

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.srcChainId, block.chainid);
        assertEq(status.dstChainId, ETH_CHAIN_ID);
        assertEq(status.amount, 100e18);
        assertEq(status.sender, alice);
        assertEq(status.recipient, alice);
        assertEq(status.status, 1); // confirmed
    }

    function test_getRoute() public view {
        BridgeRoute memory route = adapter.getRoute(ETH_CHAIN_ID, address(token));
        assertTrue(route.isActive);
        assertEq(route.dstToken, address(0xDEAD));
        assertEq(route.estimatedTime, 900);
    }

    function test_supportsInterface() public view {
        // IAny2EVMMessageReceiver
        assertTrue(
            adapter.supportsInterface(
                bytes4(keccak256("ccipReceive((bytes32,uint64,bytes,bytes,(address,uint256)[]))"))
            )
        );
    }

    function test_onlyAdminCanConfigure() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.addChain(42, 123);
    }

    receive() external payable { }
}
