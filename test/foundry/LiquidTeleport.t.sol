// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/liquid/teleport/TeleportVault.sol";
import "../../contracts/liquid/teleport/LiquidVault.sol";
import "../../contracts/yield/IYieldStrategy.sol";

/**
 * @title LiquidTeleportTest
 * @notice Tests for LiquidVault and TeleportVault contracts
 */
contract LiquidTeleportTest is Test {
    LiquidVault public vault;

    address public owner = address(0x1);
    uint256 public mpcPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public mpc;
    address public user = address(0x3);
    address public luxRecipient = address(0x4);

    uint256 public constant INITIAL_BALANCE = 100 ether;

    function setUp() public {
        // Derive MPC address from private key
        mpc = vm.addr(mpcPrivateKey);

        vm.startPrank(owner);
        vault = new LiquidVault(mpc);
        vm.stopPrank();

        // Fund user
        vm.deal(user, INITIAL_BALANCE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function _signRelease(address recipient, uint256 amount, uint256 withdrawNonce) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            "RELEASE",
            recipient,
            amount,
            withdrawNonce,
            block.chainid
        ));
        bytes32 ethSignedHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcPrivateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DepositETH() public {
        uint256 depositAmount = 1 ether;

        vm.prank(user);
        uint256 nonce = vault.depositETH{value: depositAmount}(luxRecipient);

        assertEq(nonce, 1, "First deposit should have nonce 1");
        assertEq(vault.totalDeposited(), depositAmount, "Total deposited should match");
        assertEq(address(vault).balance, depositAmount, "Vault should hold ETH");
    }

    function test_DepositETH_MultipleTimes() public {
        vm.startPrank(user);

        uint256 nonce1 = vault.depositETH{value: 1 ether}(luxRecipient);
        uint256 nonce2 = vault.depositETH{value: 2 ether}(luxRecipient);
        uint256 nonce3 = vault.depositETH{value: 3 ether}(luxRecipient);

        vm.stopPrank();

        assertEq(nonce1, 1, "First nonce");
        assertEq(nonce2, 2, "Second nonce");
        assertEq(nonce3, 3, "Third nonce");
        assertEq(vault.totalDeposited(), 6 ether, "Total deposited");
    }

    function test_DepositETH_RevertOnZero() public {
        vm.prank(user);
        vm.expectRevert(TeleportVault.ZeroAmount.selector);
        vault.depositETH{value: 0}(luxRecipient);
    }

    function test_DepositETH_RevertOnZeroRecipient() public {
        vm.prank(user);
        vm.expectRevert(TeleportVault.ZeroAddress.selector);
        vault.depositETH{value: 1 ether}(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RELEASE TESTS (MPC-controlled)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ReleaseETH() public {
        // First deposit
        vm.prank(user);
        vault.depositETH{value: 10 ether}(luxRecipient);

        uint256 recipientBalanceBefore = user.balance;
        uint256 totalDepositedBefore = vault.totalDeposited();

        // Create MPC signature for release
        bytes memory signature = _signRelease(user, 5 ether, 1);

        // Anyone can call releaseETH with valid MPC signature
        vault.releaseETH(user, 5 ether, 1, signature);

        assertEq(user.balance - recipientBalanceBefore, 5 ether, "User should receive ETH");
        assertEq(vault.totalDeposited(), totalDepositedBefore - 5 ether, "Total deposited should decrease");
        assertTrue(vault.isWithdrawProcessed(1), "Withdraw nonce should be marked processed");
    }

    function test_ReleaseETH_RevertInvalidSignature() public {
        vm.prank(user);
        vault.depositETH{value: 10 ether}(luxRecipient);

        // Invalid signature (random bytes)
        bytes memory invalidSig = new bytes(65);

        vm.expectRevert();
        vault.releaseETH(user, 5 ether, 1, invalidSig);
    }

    function test_ReleaseETH_RevertReplayAttack() public {
        vm.prank(user);
        vault.depositETH{value: 10 ether}(luxRecipient);

        bytes memory signature = _signRelease(user, 1 ether, 1);

        // First release succeeds
        vault.releaseETH(user, 1 ether, 1, signature);

        // Replay with same nonce should fail
        vm.expectRevert(TeleportVault.NonceAlreadyProcessed.selector);
        vault.releaseETH(user, 1 ether, 1, signature);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRATEGY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddStrategy() public {
        address mockStrategy = address(0x100);

        vm.prank(owner);
        vault.addStrategy(mockStrategy);

        LiquidVault.Strategy memory strategy = vault.getStrategy(0);
        assertEq(strategy.adapter, mockStrategy, "Strategy adapter should match");
        assertTrue(strategy.active, "Strategy should be active");
    }

    function test_RemoveStrategy() public {
        address mockStrategy = address(0x100);

        vm.prank(owner);
        vault.addStrategy(mockStrategy);

        vm.prank(owner);
        vault.removeStrategy(0);

        LiquidVault.Strategy memory strategy = vault.getStrategy(0);
        assertFalse(strategy.active, "Strategy should be inactive");
    }

    function test_AddStrategy_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TeleportVault.ZeroAddress.selector);
        vault.addStrategy(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BUFFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CurrentBuffer() public {
        vm.prank(user);
        vault.depositETH{value: 10 ether}(luxRecipient);

        uint256 buffer = vault.currentBuffer();
        assertEq(buffer, 10 ether, "All ETH should be in buffer initially");
    }

    function test_RequiredBuffer() public {
        vm.prank(user);
        vault.depositETH{value: 100 ether}(luxRecipient);

        // Default buffer is 20% (2000 bps)
        uint256 required = vault.requiredBuffer();
        assertEq(required, 20 ether, "Required buffer should be 20% of deposits");
    }

    function test_SetBufferBps() public {
        vm.prank(owner);
        vault.setBufferBps(3000); // 30%

        vm.prank(user);
        vault.depositETH{value: 100 ether}(luxRecipient);

        assertEq(vault.requiredBuffer(), 30 ether, "Required buffer should be 30%");
    }

    function test_SetBufferBps_RevertTooLow() public {
        vm.prank(owner);
        vm.expectRevert(LiquidVault.BufferTooLow.selector);
        vault.setBufferBps(500); // 5% - below minimum 10%
    }

    function test_SetBufferBps_RevertTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(LiquidVault.BufferTooHigh.selector);
        vault.setBufferBps(10001); // Over 100%
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OnlyAdminCanAddStrategy() public {
        address mockStrategy = address(0x100);

        // Non-admin should fail
        vm.prank(user);
        vm.expectRevert();
        vault.addStrategy(mockStrategy);

        // Admin should succeed
        vm.prank(owner);
        vault.addStrategy(mockStrategy);
    }

    function test_MPCOracleManagement() public {
        address newMPC = address(0x999);

        vm.prank(owner);
        vault.setMPCOracle(newMPC, true);

        assertTrue(vault.isMPCOracle(newMPC), "New MPC should be active");

        vm.prank(owner);
        vault.setMPCOracle(newMPC, false);

        assertFalse(vault.isMPCOracle(newMPC), "MPC should be deactivated");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_DepositETH(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(user);
        uint256 nonce = vault.depositETH{value: amount}(luxRecipient);

        assertEq(nonce, 1, "Nonce should be 1");
        assertEq(vault.totalDeposited(), amount, "Total deposited should match");
    }

    function testFuzz_MultipleDeposits(uint256 count) public {
        count = bound(count, 1, 10);
        uint256 perDeposit = 1 ether;

        vm.startPrank(user);
        for (uint256 i = 0; i < count; i++) {
            vault.depositETH{value: perDeposit}(luxRecipient);
        }
        vm.stopPrank();

        assertEq(vault.totalDeposited(), count * perDeposit, "Total should match");
        assertEq(vault.depositNonce(), count, "Nonce should match count");
    }
}
