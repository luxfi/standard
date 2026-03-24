// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {
    AxelarAdapter,
    IAxelarGateway,
    IAxelarGasService
} from "../../contracts/integrations/bridges/AxelarAdapter.sol";
import {BridgeParams, BridgeRoute, BridgeStatus} from "../../contracts/interfaces/adapters/IBridgeAdapter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockAxelarToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1_000_000e18);
    }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract MockAxelarGateway is IAxelarGateway {
    bool public callContractWithTokenCalled;
    bool public callContractCalled;
    string public lastDestChain;
    string public lastDestAddress;
    string public lastSymbol;
    uint256 public lastAmount;

    mapping(string => address) private _tokenAddresses;
    mapping(bytes32 => bool) private _validCommands;

    function setTokenAddress(string calldata symbol, address addr) external {
        _tokenAddresses[symbol] = addr;
    }

    function setValidCommand(bytes32 commandId) external {
        _validCommands[commandId] = true;
    }

    function sendToken(string calldata, string calldata, string calldata, uint256) external pure override {
        // no-op for mock
    }

    function callContract(string calldata, string calldata, bytes calldata) external override {
        callContractCalled = true;
    }

    function callContractWithToken(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata,
        string calldata symbol,
        uint256 amount
    ) external override {
        callContractWithTokenCalled = true;
        lastDestChain = destinationChain;
        lastDestAddress = contractAddress;
        lastSymbol = symbol;
        lastAmount = amount;
    }

    function validateContractCall(
        bytes32 commandId,
        string calldata,
        string calldata,
        bytes32
    ) external view override returns (bool) {
        return _validCommands[commandId];
    }

    function validateContractCallAndMint(
        bytes32 commandId,
        string calldata,
        string calldata,
        bytes32,
        string calldata,
        uint256
    ) external view override returns (bool) {
        return _validCommands[commandId];
    }

    function tokenAddresses(string calldata symbol) external view override returns (address) {
        return _tokenAddresses[symbol];
    }

    function isCommandExecuted(bytes32) external pure override returns (bool) {
        return false;
    }
}

contract MockAxelarGasService is IAxelarGasService {
    bool public gasPaymentReceived;
    uint256 public lastGasPayment;

    function payNativeGasForContractCallWithToken(
        address,
        string calldata,
        string calldata,
        bytes calldata,
        string calldata,
        uint256,
        address
    ) external payable override {
        gasPaymentReceived = true;
        lastGasPayment = msg.value;
    }

    function payNativeGasForContractCall(
        address,
        string calldata,
        string calldata,
        bytes calldata,
        address
    ) external payable override {
        gasPaymentReceived = true;
        lastGasPayment = msg.value;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract AxelarAdapterTest is Test {
    AxelarAdapter public adapter;
    MockAxelarGateway public gateway;
    MockAxelarGasService public gasService;
    MockAxelarToken public token;

    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);

    uint256 constant ETH_CHAIN_ID = 1;
    string constant ETH_CHAIN_NAME = "ethereum";

    function setUp() public {
        vm.startPrank(admin);
        gateway = new MockAxelarGateway();
        gasService = new MockAxelarGasService();
        adapter = new AxelarAdapter(address(gateway), address(gasService), admin);
        token = new MockAxelarToken();

        // Configure chain
        adapter.addChain(ETH_CHAIN_ID, ETH_CHAIN_NAME);

        // Configure token mapping and symbol
        adapter.setTokenMapping(address(token), ETH_CHAIN_ID, address(0xDEAD));
        adapter.setTokenSymbol(address(token), "MCK");

        // Set trusted remote
        adapter.setTrustedRemote(ETH_CHAIN_ID, "0x0000000000000000000000000000000000001234");

        // Fund alice
        token.transfer(alice, 10_000e18);
        vm.stopPrank();
    }

    // ─── Deployment ──────────────────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(adapter.protocol(), "Axelar GMP");
        assertEq(adapter.version(), "1.0.0");
        assertEq(adapter.endpoint(), address(gateway));
        assertEq(adapter.chainId(), block.chainid);
    }

    function test_revert_zeroAddressConstructor() public {
        vm.expectRevert(AxelarAdapter.ZeroAddress.selector);
        new AxelarAdapter(address(0), address(gasService), admin);

        vm.expectRevert(AxelarAdapter.ZeroAddress.selector);
        new AxelarAdapter(address(gateway), address(0), admin);

        vm.expectRevert(AxelarAdapter.ZeroAddress.selector);
        new AxelarAdapter(address(gateway), address(gasService), address(0));
    }

    // ─── Chain Config ────────────────────────────────────────────────────────

    function test_chainConfig() public view {
        assertEq(keccak256(bytes(adapter.chainIdToName(ETH_CHAIN_ID))), keccak256(bytes(ETH_CHAIN_NAME)));
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
        assertEq(route.estimatedTime, 180);
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
        vm.expectRevert(abi.encodeWithSelector(AxelarAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.estimateFees(999, address(token), 100e18);
    }

    function test_estimateOutput() public view {
        assertEq(adapter.estimateOutput(ETH_CHAIN_ID, address(token), 100e18), 100e18);
    }

    function test_estimateTime() public view {
        assertEq(adapter.estimateTime(ETH_CHAIN_ID), 180);
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

        bytes32 bridgeId = adapter.bridge{value: 0.01 ether}(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(token.balanceOf(alice), 9_900e18);
        assertTrue(gateway.callContractWithTokenCalled());
        assertTrue(gasService.gasPaymentReceived());
        assertEq(gasService.lastGasPayment(), 0.01 ether);
    }

    function test_bridge_revert_zeroAmount() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        BridgeParams memory params = BridgeParams({
            dstChainId: ETH_CHAIN_ID,
            token: address(token),
            amount: 0,
            recipient: alice,
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(AxelarAdapter.ZeroAmount.selector);
        adapter.bridge{value: 0.01 ether}(params);
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
            minAmountOut: 0,
            extraData: ""
        });

        vm.expectRevert(abi.encodeWithSelector(AxelarAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.bridge{value: 0.01 ether}(params);
        vm.stopPrank();
    }

    function test_bridge_revert_unsupportedToken_noMapping() public {
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

        vm.expectRevert(abi.encodeWithSelector(AxelarAdapter.UnsupportedToken.selector, address(0x1234), ETH_CHAIN_ID));
        adapter.bridge{value: 0.01 ether}(params);
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

        bytes32 bridgeId = adapter.bridge{value: 0.01 ether}(params);
        vm.stopPrank();

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.srcChainId, block.chainid);
        assertEq(status.dstChainId, ETH_CHAIN_ID);
        assertEq(status.amount, 100e18);
        assertEq(status.sender, alice);
        assertEq(status.recipient, bob);
        assertEq(status.status, 1);
    }

    // ─── Execute With Token ──────────────────────────────────────────────────

    function test_executeWithToken() public {
        // Set token address in gateway mock
        gateway.setTokenAddress("MCK", address(token));

        // Fund adapter with tokens to release
        vm.prank(admin);
        token.transfer(address(adapter), 50e18);

        bytes32 commandId = keccak256("cmd1");
        gateway.setValidCommand(commandId);

        bytes memory payload = abi.encode(bob, uint256(50e18), bytes(""));

        adapter.executeWithToken(
            commandId,
            "ethereum",
            "0xSenderAddress",
            payload,
            "MCK",
            50e18
        );

        assertEq(token.balanceOf(bob), 50e18);
    }

    function test_executeWithToken_revert_invalidCommand() public {
        bytes32 commandId = keccak256("invalid");
        bytes memory payload = abi.encode(bob, uint256(50e18), bytes(""));

        vm.expectRevert(AxelarAdapter.InvalidCommand.selector);
        adapter.executeWithToken(
            commandId,
            "ethereum",
            "0xSenderAddress",
            payload,
            "MCK",
            50e18
        );
    }

    function test_execute() public {
        bytes32 commandId = keccak256("cmd2");
        gateway.setValidCommand(commandId);

        bytes memory payload = abi.encode(bob);

        adapter.execute(commandId, "ethereum", "0xSenderAddress", payload);
        // No revert = success
    }

    function test_execute_revert_invalidCommand() public {
        bytes32 commandId = keccak256("invalid");

        vm.expectRevert(AxelarAdapter.InvalidCommand.selector);
        adapter.execute(commandId, "ethereum", "0xSenderAddress", "");
    }

    // ─── Admin Access Control ────────────────────────────────────────────────

    function test_onlyAdminCanAddChain() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.addChain(42, "polygon");
    }

    function test_onlyAdminCanSetTokenMapping() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setTokenMapping(address(token), 42, address(0x1));
    }

    function test_onlyAdminCanSetTokenSymbol() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.setTokenSymbol(address(token), "TST");
    }

    function test_setTokenSymbol_revert_empty() public {
        vm.prank(admin);
        vm.expectRevert(AxelarAdapter.EmptySymbol.selector);
        adapter.setTokenSymbol(address(token), "");
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
