// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { BridgeAdapter, IMintBurnable } from "../../contracts/integrations/bridges/BridgeAdapter.sol";
import { BridgeParams, BridgeRoute, BridgeStatus } from "../../contracts/interfaces/adapters/IBridgeAdapter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockBridgeToken is ERC20, AccessControl, IMintBurnable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Mock Bridge Token", "MBT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract MockLockToken is ERC20 {
    constructor() ERC20("Mock Lock Token", "MLT") {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

contract BridgeAdapterTest is Test {
    BridgeAdapter public adapter;
    MockBridgeToken public mintToken;
    MockLockToken public lockToken;

    address admin = address(0xA);
    address oracle = address(0xB); // ATS MPC wallet
    address alice = address(0xC);
    address bob = address(0xD);

    uint256 constant DST_CHAIN = 96369; // Mainnet
    uint256 constant DST_CHAIN2 = 96368; // Testnet

    function setUp() public {
        vm.startPrank(admin);

        adapter = new BridgeAdapter(admin, oracle, 0); // 0 = instant finality
        mintToken = new MockBridgeToken();
        lockToken = new MockLockToken();

        // Configure chains
        adapter.addChain(DST_CHAIN);
        adapter.addChain(DST_CHAIN2);

        // Configure tokens
        adapter.configureToken(
            address(mintToken),
            DST_CHAIN,
            address(0xDEAD),
            BridgeAdapter.BridgeMode.MintBurn,
            0 // unlimited
        );
        adapter.configureToken(
            address(lockToken),
            DST_CHAIN,
            address(0xBEEF),
            BridgeAdapter.BridgeMode.LockRelease,
            500_000e18 // 500K daily limit
        );

        // Grant MINTER_ROLE to adapter so it can burn
        mintToken.grantRole(mintToken.MINTER_ROLE(), address(adapter));

        // Fund alice
        mintToken.transfer(alice, 10_000e18);
        lockToken.transfer(alice, 10_000e18);

        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────
    // Deployment
    // ──────────────────────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(adapter.protocol(), "Liquidity ATS");
        assertEq(adapter.version(), "1.0.0");
        assertEq(adapter.endpoint(), address(adapter));
        assertEq(adapter.challengePeriod(), 0);
    }

    function test_revert_zeroAdmin() public {
        vm.expectRevert(BridgeAdapter.ZeroAddress.selector);
        new BridgeAdapter(address(0), oracle, 0);
    }

    function test_revert_zeroOracle() public {
        vm.expectRevert(BridgeAdapter.ZeroAddress.selector);
        new BridgeAdapter(admin, address(0), 0);
    }

    // ──────────────────────────────────────────────────────────────
    // Chain config
    // ──────────────────────────────────────────────────────────────

    function test_chainConfig() public view {
        assertTrue(adapter.isChainSupported(DST_CHAIN));
        assertTrue(adapter.isChainSupported(DST_CHAIN2));
        assertFalse(adapter.isChainSupported(999));
        assertEq(adapter.supportedChains().length, 2);
    }

    function test_removeChain() public {
        vm.prank(admin);
        adapter.removeChain(DST_CHAIN2);
        assertFalse(adapter.isChainSupported(DST_CHAIN2));
        assertEq(adapter.supportedChains().length, 1);
    }

    function test_isRouteSupported() public view {
        assertTrue(adapter.isRouteSupported(DST_CHAIN, address(mintToken)));
        assertTrue(adapter.isRouteSupported(DST_CHAIN, address(lockToken)));
        assertFalse(adapter.isRouteSupported(DST_CHAIN, address(0x1)));
        assertFalse(adapter.isRouteSupported(999, address(mintToken)));
    }

    function test_getRoute() public view {
        BridgeRoute memory route = adapter.getRoute(DST_CHAIN, address(mintToken));
        assertTrue(route.isActive);
        assertEq(route.dstToken, address(0xDEAD));
        assertEq(route.estimatedTime, 3); // instant optimistic
    }

    // ──────────────────────────────────────────────────────────────
    // Bridge: Mint/Burn mode
    // ──────────────────────────────────────────────────────────────

    function test_bridge_mintBurn() public {
        vm.startPrank(alice);
        mintToken.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: DST_CHAIN,
            token: address(mintToken),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 100e18,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        assertTrue(bridgeId != bytes32(0));
        assertEq(mintToken.balanceOf(alice), 9_900e18);
        // Tokens were burned (not held by adapter)
        assertEq(mintToken.balanceOf(address(adapter)), 0);

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.status, 1); // confirmed
        assertEq(status.sender, alice);
        assertEq(status.recipient, bob);
    }

    // ──────────────────────────────────────────────────────────────
    // Bridge: Lock/Release mode
    // ──────────────────────────────────────────────────────────────

    function test_bridge_lockRelease() public {
        vm.startPrank(alice);
        lockToken.approve(address(adapter), 100e18);

        BridgeParams memory params = BridgeParams({
            dstChainId: DST_CHAIN,
            token: address(lockToken),
            amount: 100e18,
            recipient: bob,
            minAmountOut: 100e18,
            extraData: ""
        });

        bytes32 bridgeId = adapter.bridge(params);
        vm.stopPrank();

        assertEq(lockToken.balanceOf(alice), 9_900e18);
        assertEq(lockToken.balanceOf(address(adapter)), 100e18);
        assertEq(adapter.lockedBalance(address(lockToken)), 100e18);

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.status, 1);
    }

    // ──────────────────────────────────────────────────────────────
    // Oracle: fill (mint)
    // ──────────────────────────────────────────────────────────────

    function test_fill_mint() public {
        // First bridge (burn on source)
        vm.startPrank(alice);
        mintToken.approve(address(adapter), 100e18);
        bytes32 bridgeId = adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(mintToken),
                amount: 100e18,
                recipient: bob,
                minAmountOut: 100e18,
                extraData: ""
            })
        );
        vm.stopPrank();

        // Oracle fills on destination (same contract in test, simulates dest chain)
        vm.prank(oracle);
        adapter.fill(bridgeId, address(mintToken), bob, 100e18, block.chainid, 0, BridgeAdapter.BridgeMode.MintBurn);

        assertEq(mintToken.balanceOf(bob), 100e18);
        assertTrue(adapter.filled(bridgeId));

        BridgeStatus memory status = adapter.getStatus(bridgeId);
        assertEq(status.status, 2); // completed
    }

    // ──────────────────────────────────────────────────────────────
    // Oracle: fill (release)
    // ──────────────────────────────────────────────────────────────

    function test_fill_release() public {
        // Lock tokens
        vm.startPrank(alice);
        lockToken.approve(address(adapter), 100e18);
        bytes32 bridgeId = adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(lockToken),
                amount: 100e18,
                recipient: bob,
                minAmountOut: 100e18,
                extraData: ""
            })
        );
        vm.stopPrank();

        // Oracle releases
        vm.prank(oracle);
        adapter.fill(bridgeId, address(lockToken), bob, 100e18, block.chainid, 0, BridgeAdapter.BridgeMode.LockRelease);

        assertEq(lockToken.balanceOf(bob), 100e18);
        assertEq(adapter.lockedBalance(address(lockToken)), 0);
    }

    // ──────────────────────────────────────────────────────────────
    // Oracle: batch fill
    // ──────────────────────────────────────────────────────────────

    function test_fillBatch() public {
        vm.startPrank(alice);
        mintToken.approve(address(adapter), 300e18);

        bytes32 id1 = adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(mintToken),
                amount: 100e18,
                recipient: bob,
                minAmountOut: 100e18,
                extraData: ""
            })
        );
        bytes32 id2 = adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(mintToken),
                amount: 200e18,
                recipient: alice,
                minAmountOut: 200e18,
                extraData: ""
            })
        );
        vm.stopPrank();

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;
        address[] memory tokens = new address[](2);
        tokens[0] = address(mintToken);
        tokens[1] = address(mintToken);
        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = alice;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        uint256[] memory origins = new uint256[](2);
        origins[0] = block.chainid;
        origins[1] = block.chainid;
        uint256[] memory nonces = new uint256[](2);
        nonces[0] = 0;
        nonces[1] = 1;
        BridgeAdapter.BridgeMode[] memory modes = new BridgeAdapter.BridgeMode[](2);
        modes[0] = BridgeAdapter.BridgeMode.MintBurn;
        modes[1] = BridgeAdapter.BridgeMode.MintBurn;

        vm.prank(oracle);
        adapter.fillBatch(ids, tokens, recipients, amounts, origins, nonces, modes);

        assertEq(mintToken.balanceOf(bob), 100e18);
        // alice started with 10K, burned 300, got 200 back
        assertEq(mintToken.balanceOf(alice), 9_700e18 + 200e18);
    }

    // ──────────────────────────────────────────────────────────────
    // Reverts
    // ──────────────────────────────────────────────────────────────

    function test_revert_unsupportedChain() public {
        vm.startPrank(alice);
        mintToken.approve(address(adapter), 100e18);
        vm.expectRevert(abi.encodeWithSelector(BridgeAdapter.UnsupportedChain.selector, uint256(999)));
        adapter.bridge(
            BridgeParams({
                dstChainId: 999,
                token: address(mintToken),
                amount: 100e18,
                recipient: bob,
                minAmountOut: 100e18,
                extraData: ""
            })
        );
        vm.stopPrank();
    }

    function test_revert_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(BridgeAdapter.ZeroAmount.selector);
        adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(mintToken),
                amount: 0,
                recipient: bob,
                minAmountOut: 0,
                extraData: ""
            })
        );
    }

    function test_revert_doubleFill() public {
        vm.startPrank(alice);
        mintToken.approve(address(adapter), 100e18);
        bytes32 bridgeId = adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(mintToken),
                amount: 100e18,
                recipient: bob,
                minAmountOut: 100e18,
                extraData: ""
            })
        );
        vm.stopPrank();

        vm.prank(oracle);
        adapter.fill(bridgeId, address(mintToken), bob, 100e18, block.chainid, 0, BridgeAdapter.BridgeMode.MintBurn);

        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(BridgeAdapter.AlreadyFilled.selector, bridgeId));
        adapter.fill(bridgeId, address(mintToken), bob, 100e18, block.chainid, 0, BridgeAdapter.BridgeMode.MintBurn);
    }

    function test_revert_nonOracleFill() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.fill(bytes32(0), address(mintToken), bob, 100e18, block.chainid, 0, BridgeAdapter.BridgeMode.MintBurn);
    }

    // ──────────────────────────────────────────────────────────────
    // Daily limits
    // ──────────────────────────────────────────────────────────────

    function test_dailyLimit() public {
        vm.startPrank(admin);
        lockToken.mint(alice, 1_000_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        lockToken.approve(address(adapter), 600_000e18);

        // First bridge: 400K (under 500K limit)
        adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(lockToken),
                amount: 400_000e18,
                recipient: bob,
                minAmountOut: 400_000e18,
                extraData: ""
            })
        );

        // Second bridge: 200K (would exceed 500K daily)
        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeAdapter.DailyLimitExceeded.selector, address(lockToken), 200_000e18, 100_000e18
            )
        );
        adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(lockToken),
                amount: 200_000e18,
                recipient: bob,
                minAmountOut: 200_000e18,
                extraData: ""
            })
        );
        vm.stopPrank();
    }

    function test_dailyLimit_resets() public {
        vm.startPrank(admin);
        lockToken.mint(alice, 1_000_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        lockToken.approve(address(adapter), 1_000_000e18);

        adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(lockToken),
                amount: 400_000e18,
                recipient: bob,
                minAmountOut: 400_000e18,
                extraData: ""
            })
        );

        // Warp 1 day forward — limit resets
        vm.warp(block.timestamp + 1 days + 1);

        adapter.bridge(
            BridgeParams({
                dstChainId: DST_CHAIN,
                token: address(lockToken),
                amount: 400_000e18,
                recipient: bob,
                minAmountOut: 400_000e18,
                extraData: ""
            })
        );
        vm.stopPrank();

        assertEq(lockToken.balanceOf(address(adapter)), 800_000e18);
    }

    // ──────────────────────────────────────────────────────────────
    // Estimation
    // ──────────────────────────────────────────────────────────────

    function test_estimateFees() public view {
        (uint256 bridgeFee, uint256 protocolFee) = adapter.estimateFees(DST_CHAIN, address(mintToken), 100e18);
        assertEq(bridgeFee, 0);
        assertEq(protocolFee, 0);
    }

    function test_estimateOutput() public view {
        assertEq(adapter.estimateOutput(DST_CHAIN, address(mintToken), 100e18), 100e18);
    }

    function test_estimateTime_instant() public view {
        assertEq(adapter.estimateTime(DST_CHAIN), 3); // instant with 0 challenge period
    }

    function test_estimateTime_withChallenge() public {
        BridgeAdapter challenged = new BridgeAdapter(admin, oracle, 600);
        assertEq(challenged.estimateTime(DST_CHAIN), 600);
    }

    // ──────────────────────────────────────────────────────────────
    // Access control
    // ──────────────────────────────────────────────────────────────

    function test_onlyAdminCanConfigure() public {
        vm.prank(alice);
        vm.expectRevert();
        adapter.addChain(42);
    }

    function test_onlyOracleCanFill() public {
        vm.prank(admin);
        vm.expectRevert();
        adapter.fill(bytes32(0), address(mintToken), bob, 100e18, 1, 0, BridgeAdapter.BridgeMode.MintBurn);
    }

    // ──────────────────────────────────────────────────────────────
    // Challenge period
    // ──────────────────────────────────────────────────────────────

    function test_setChallengePeriod() public {
        vm.prank(admin);
        adapter.setChallengePeriod(3600);
        assertEq(adapter.challengePeriod(), 3600);
    }

    receive() external payable { }
}
