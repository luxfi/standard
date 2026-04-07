// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/LuxBridge.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 100_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LuxBridgeTest is Test {
    LuxBridge bridge;
    MockToken token;

    address admin;
    uint256 mpcKey;
    address mpcSigner;
    address user;

    function setUp() public {
        admin = address(this);
        mpcKey = 0xA11CE;
        mpcSigner = vm.addr(mpcKey);
        user = address(0xBEEF);

        bridge = new LuxBridge(mpcSigner, 100); // 1% fee
        token = new MockToken();

        // Register token with 1M daily limit
        bridge.registerToken(address(token), 1_000_000e18);

        // Fund the bridge vault so mints can transfer out
        token.transfer(address(bridge), 10_000_000e18);

        // Fund user
        token.transfer(user, 1_000_000e18);
    }

    // -------------------------------------------------------
    // Initialization
    // -------------------------------------------------------

    function test_initialize_setsAdmin() public view {
        assertEq(bridge.admin(), admin);
    }

    function test_initialize_setsMpcSigner() public view {
        assertEq(bridge.mpcSigner(), mpcSigner);
    }

    function test_initialize_setsFeeBps() public view {
        assertEq(bridge.feeBps(), 100);
    }

    function test_initialize_notPaused() public view {
        assertFalse(bridge.paused());
    }

    function test_initialize_revertsFeeAbove500() public {
        vm.expectRevert("Fee too high");
        new LuxBridge(mpcSigner, 501);
    }

    // -------------------------------------------------------
    // Lock
    // -------------------------------------------------------

    function test_lock_transfersTokens() public {
        uint256 amount = 10_000e18;
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.lockAndBridge(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();

        // Fee is 1% = 100e18, bridge amount = 9900e18
        // User started with 1M, spent 10k
        assertEq(token.balanceOf(user), 1_000_000e18 - amount);
    }

    function test_lock_incrementsNonce() public {
        vm.startPrank(user);
        token.approve(address(bridge), 20_000e18);
        bridge.lockAndBridge(address(token), 10_000e18, 1, bytes32(uint256(1)));
        assertEq(bridge.outboundNonce(), 1);
        bridge.lockAndBridge(address(token), 10_000e18, 1, bytes32(uint256(1)));
        assertEq(bridge.outboundNonce(), 2);
        vm.stopPrank();
    }

    function test_lock_updatesTotalLocked() public {
        uint256 amount = 10_000e18;
        uint256 fee = (amount * 100) / 10_000; // 1%
        uint256 bridgeAmount = amount - fee;

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.lockAndBridge(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();

        assertEq(bridge.totalLocked(), bridgeAmount);
    }

    function test_lock_revertsZeroAmount() public {
        vm.startPrank(user);
        token.approve(address(bridge), 1e18);
        vm.expectRevert("Zero amount");
        bridge.lockAndBridge(address(token), 0, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    function test_lock_revertsUnregisteredToken() public {
        MockToken unregistered = new MockToken();
        vm.startPrank(user);
        unregistered.approve(address(bridge), 1e18);
        vm.expectRevert("Token not registered");
        bridge.lockAndBridge(address(unregistered), 1e18, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    function test_lock_emitsEvent() public {
        uint256 amount = 10_000e18;
        uint256 fee = (amount * 100) / 10_000;
        uint256 bridgeAmount = amount - fee;

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectEmit(true, true, false, true);
        emit LuxBridge.Lock(
            bridge.CHAIN_ID(), 1, 1, address(token), user, bytes32(uint256(1)), bridgeAmount, fee
        );
        bridge.lockAndBridge(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    // -------------------------------------------------------
    // Mint with ecrecover
    // -------------------------------------------------------

    function _signMint(
        address _token,
        uint64 sourceChainId,
        uint64 nonce,
        address recipient,
        uint256 amount
    ) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(
            "LUX_BRIDGE_MINT", sourceChainId, nonce, recipient, _token, amount
        ));
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function test_mint_validSignature() public {
        uint64 sourceChain = 1;
        uint64 nonce = 1;
        address recipient = user;
        uint256 amount = 5_000e18;

        bytes memory sig = _signMint(address(token), sourceChain, nonce, recipient, amount);

        uint256 balBefore = token.balanceOf(recipient);
        bridge.mintBridged(address(token), sourceChain, nonce, recipient, amount, sig);
        assertEq(token.balanceOf(recipient) - balBefore, amount);
    }

    function test_mint_marksNonceProcessed() public {
        uint64 sourceChain = 1;
        uint64 nonce = 42;
        uint256 amount = 1_000e18;

        bytes memory sig = _signMint(address(token), sourceChain, nonce, user, amount);
        bridge.mintBridged(address(token), sourceChain, nonce, user, amount, sig);

        assertTrue(bridge.processedNonces(sourceChain, nonce));
    }

    function test_mint_revertsReplayedNonce() public {
        uint64 sourceChain = 1;
        uint64 nonce = 1;
        uint256 amount = 1_000e18;

        bytes memory sig = _signMint(address(token), sourceChain, nonce, user, amount);
        bridge.mintBridged(address(token), sourceChain, nonce, user, amount, sig);

        vm.expectRevert("Nonce processed");
        bridge.mintBridged(address(token), sourceChain, nonce, user, amount, sig);
    }

    function test_mint_revertsInvalidSignature() public {
        uint64 sourceChain = 1;
        uint64 nonce = 1;
        uint256 amount = 1_000e18;

        // Sign with wrong key
        uint256 wrongKey = 0xBAD;
        bytes32 digest = keccak256(abi.encodePacked(
            "LUX_BRIDGE_MINT", sourceChain, nonce, user, address(token), amount
        ));
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid signature");
        bridge.mintBridged(address(token), sourceChain, nonce, user, amount, sig);
    }

    function test_mint_revertsZeroAmount() public {
        bytes memory sig = _signMint(address(token), 1, 1, user, 0);
        vm.expectRevert("Zero amount");
        bridge.mintBridged(address(token), 1, 1, user, 0, sig);
    }

    // -------------------------------------------------------
    // Burn
    // -------------------------------------------------------

    function test_burn_transfersTokensToContract() public {
        uint256 amount = 5_000e18;
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.burnBridged(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();

        assertEq(bridge.totalBurned(), amount);
    }

    function test_burn_incrementsNonce() public {
        vm.startPrank(user);
        token.approve(address(bridge), 10_000e18);
        bridge.burnBridged(address(token), 5_000e18, 1, bytes32(uint256(1)));
        assertEq(bridge.outboundNonce(), 1);
        bridge.burnBridged(address(token), 5_000e18, 1, bytes32(uint256(1)));
        assertEq(bridge.outboundNonce(), 2);
        vm.stopPrank();
    }

    function test_burn_revertsZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert("Zero amount");
        bridge.burnBridged(address(token), 0, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    function test_burn_emitsEvent() public {
        uint256 amount = 5_000e18;
        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectEmit(true, true, false, true);
        emit LuxBridge.Burn(
            bridge.CHAIN_ID(), 1, 1, address(token), user, bytes32(uint256(1)), amount
        );
        bridge.burnBridged(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    // -------------------------------------------------------
    // Pause
    // -------------------------------------------------------

    function test_pause_blocksLock() public {
        bridge.pause();
        assertTrue(bridge.paused());

        vm.startPrank(user);
        token.approve(address(bridge), 1e18);
        vm.expectRevert("Paused");
        bridge.lockAndBridge(address(token), 1e18, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    function test_pause_blocksMint() public {
        bridge.pause();
        bytes memory sig = _signMint(address(token), 1, 1, user, 1e18);
        vm.expectRevert("Paused");
        bridge.mintBridged(address(token), 1, 1, user, 1e18, sig);
    }

    function test_pause_blocksBurn() public {
        bridge.pause();
        vm.startPrank(user);
        vm.expectRevert("Paused");
        bridge.burnBridged(address(token), 1e18, 1, bytes32(uint256(1)));
        vm.stopPrank();
    }

    function test_unpause_resumesOperations() public {
        bridge.pause();
        bridge.unpause();
        assertFalse(bridge.paused());

        vm.startPrank(user);
        token.approve(address(bridge), 10_000e18);
        bridge.lockAndBridge(address(token), 10_000e18, 1, bytes32(uint256(1)));
        vm.stopPrank();
        assertEq(bridge.outboundNonce(), 1);
    }

    function test_pause_revertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert("Not admin");
        bridge.pause();
    }

    // -------------------------------------------------------
    // Fee update
    // -------------------------------------------------------

    function test_setFee_updatesFeeBps() public {
        bridge.setFee(250); // 2.5%
        assertEq(bridge.feeBps(), 250);
    }

    function test_setFee_revertsAboveMax() public {
        vm.expectRevert();
        bridge.setFee(501);
    }

    function test_setFee_revertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert("Not admin");
        bridge.setFee(200);
    }

    function test_setFee_affectsLock() public {
        bridge.setFee(500); // 5%
        uint256 amount = 10_000e18;

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.lockAndBridge(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();

        // 5% fee: bridgeAmount = 10000 - 500 = 9500
        assertEq(bridge.totalLocked(), 9_500e18);
    }

    function test_setFee_zeroFeeNoDeduction() public {
        bridge.setFee(0);
        uint256 amount = 10_000e18;

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.lockAndBridge(address(token), amount, 1, bytes32(uint256(1)));
        vm.stopPrank();

        assertEq(bridge.totalLocked(), amount);
    }
}

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
