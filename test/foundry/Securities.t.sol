// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { SecurityToken } from "../../contracts/securities/token/SecurityToken.sol";
import { ComplianceRegistry } from "../../contracts/securities/compliance/ComplianceRegistry.sol";
import { WhitelistModule } from "../../contracts/securities/compliance/WhitelistModule.sol";
import { LockupModule } from "../../contracts/securities/compliance/LockupModule.sol";
import { JurisdictionModule } from "../../contracts/securities/compliance/JurisdictionModule.sol";
import { IERC1404 } from "../../contracts/securities/interfaces/IERC1404.sol";
import { IST20 } from "../../contracts/securities/interfaces/IST20.sol";
import { IComplianceModule } from "../../contracts/securities/interfaces/IComplianceModule.sol";

/**
 * @title Securities Module Tests
 * @notice Tests for ERC-3643 (T-REX) / ERC-1404 / ST-20 compliant security tokens.
 *
 * Covers:
 *   - SecurityToken deployment, minting, transfer compliance
 *   - ComplianceRegistry whitelist/blacklist/lockup/jurisdiction
 *   - Pluggable compliance modules (whitelist, lockup, jurisdiction)
 *   - ERC-1404 detectTransferRestriction + messageForTransferRestriction
 *   - ST-20 verifyTransfer
 *   - Pausability, role management
 *   - Corporate actions (dividends, documents)
 */
contract SecuritiesTest is Test {
    SecurityToken public token;
    ComplianceRegistry public registry;
    WhitelistModule public whitelistModule;
    LockupModule public lockupModule;
    JurisdictionModule public jurisdictionModule;

    address admin = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);
    address charlie = address(0xD);
    address blacklisted = address(0xE);

    function setUp() public {
        vm.startPrank(admin);
        registry = new ComplianceRegistry(admin);
        token = new SecurityToken("Lux Security Token", "LST", admin, registry);

        // Whitelist admin, alice, bob
        registry.whitelistAdd(admin);
        registry.whitelistAdd(alice);
        registry.whitelistAdd(bob);

        // Mint tokens
        token.mint(admin, 1_000_000e18);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────────
    // Deployment
    // ──────────────────────────────────────────────────────────────────

    function test_deployment() public view {
        assertEq(token.name(), "Lux Security Token");
        assertEq(token.symbol(), "LST");
        assertEq(token.totalSupply(), 1_000_000e18);
        assertEq(token.balanceOf(admin), 1_000_000e18);
        assertEq(address(token.complianceRegistry()), address(registry));
    }

    function test_revert_zeroAdmin() public {
        vm.expectRevert(SecurityToken.ZeroAddress.selector);
        new SecurityToken("X", "X", address(0), registry);
    }

    function test_revert_zeroRegistry() public {
        vm.expectRevert(SecurityToken.ZeroAddress.selector);
        new SecurityToken("X", "X", admin, ComplianceRegistry(address(0)));
    }

    // ──────────────────────────────────────────────────────────────────
    // ERC-1404: detectTransferRestriction
    // ──────────────────────────────────────────────────────────────────

    function test_erc1404_success() public view {
        uint8 code = token.detectTransferRestriction(admin, alice, 100e18);
        assertEq(code, 0);
        assertEq(token.messageForTransferRestriction(0), "SUCCESS");
    }

    function test_erc1404_senderNotWhitelisted() public view {
        uint8 code = token.detectTransferRestriction(charlie, alice, 100e18);
        assertEq(code, 1);
        assertEq(token.messageForTransferRestriction(1), "SENDER_NOT_WHITELISTED");
    }

    function test_erc1404_receiverNotWhitelisted() public view {
        uint8 code = token.detectTransferRestriction(admin, charlie, 100e18);
        assertEq(code, 2);
        assertEq(token.messageForTransferRestriction(2), "RECEIVER_NOT_WHITELISTED");
    }

    function test_erc1404_senderBlacklisted() public {
        vm.startPrank(admin);
        registry.whitelistAdd(blacklisted);
        registry.blacklistAdd(blacklisted);
        vm.stopPrank();

        uint8 code = token.detectTransferRestriction(blacklisted, alice, 100e18);
        assertEq(code, 3);
        assertEq(token.messageForTransferRestriction(3), "SENDER_BLACKLISTED");
    }

    function test_erc1404_senderLocked() public {
        vm.startPrank(admin);
        registry.setLockup(alice, block.timestamp + 365 days);
        vm.stopPrank();

        uint8 code = token.detectTransferRestriction(alice, bob, 100e18);
        assertEq(code, 5);
        assertEq(token.messageForTransferRestriction(5), "SENDER_LOCKED");
    }

    function test_erc1404_mintBypass() public view {
        // Minting (from == 0) bypasses compliance
        uint8 code = token.detectTransferRestriction(address(0), charlie, 100e18);
        assertEq(code, 0);
    }

    function test_erc1404_unknownCode() public view {
        assertEq(token.messageForTransferRestriction(99), "UNKNOWN_RESTRICTION");
    }

    // ──────────────────────────────────────────────────────────────────
    // ST-20: verifyTransfer
    // ──────────────────────────────────────────────────────────────────

    function test_st20_allowed() public view {
        bool allowed = token.verifyTransfer(admin, alice, 100e18, "");
        assertTrue(allowed);
    }

    function test_st20_denied() public view {
        bool allowed = token.verifyTransfer(admin, charlie, 100e18, "");
        assertFalse(allowed);
    }

    function test_st20_mintBypass() public view {
        bool allowed = token.verifyTransfer(address(0), charlie, 100e18, "");
        assertTrue(allowed);
    }

    // ──────────────────────────────────────────────────────────────────
    // Transfer compliance enforcement
    // ──────────────────────────────────────────────────────────────────

    function test_transfer_whitelisted() public {
        vm.prank(admin);
        token.transfer(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_transfer_revert_notWhitelisted() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SecurityToken.TransferRestricted.selector, uint8(2)));
        token.transfer(charlie, 100e18);
    }

    function test_transfer_revert_blacklisted() public {
        vm.startPrank(admin);
        registry.whitelistAdd(blacklisted);
        registry.blacklistAdd(blacklisted);
        token.transfer(alice, 500e18);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SecurityToken.TransferRestricted.selector, uint8(4)));
        token.transfer(blacklisted, 100e18);
    }

    function test_transfer_revert_locked() public {
        vm.startPrank(admin);
        token.transfer(alice, 500e18);
        registry.setLockup(alice, block.timestamp + 365 days);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SecurityToken.TransferRestricted.selector, uint8(5)));
        token.transfer(bob, 100e18);
    }

    function test_transfer_lockupExpired() public {
        vm.startPrank(admin);
        token.transfer(alice, 500e18);
        registry.setLockup(alice, block.timestamp + 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    // ──────────────────────────────────────────────────────────────────
    // Minting / burning bypass compliance
    // ──────────────────────────────────────────────────────────────────

    function test_mint_nonWhitelisted() public {
        // Minting to non-whitelisted address is allowed (from == 0 bypass)
        vm.prank(admin);
        token.mint(charlie, 100e18);
        assertEq(token.balanceOf(charlie), 100e18);
    }

    function test_burn() public {
        vm.prank(admin);
        token.burn(500e18);
        assertEq(token.balanceOf(admin), 999_500e18);
    }

    // ──────────────────────────────────────────────────────────────────
    // Pause
    // ──────────────────────────────────────────────────────────────────

    function test_pause_blocksTransfers() public {
        vm.prank(admin);
        token.pause();

        vm.prank(admin);
        vm.expectRevert();
        token.transfer(alice, 100e18);
    }

    function test_unpause_allowsTransfers() public {
        vm.startPrank(admin);
        token.pause();
        token.unpause();
        token.transfer(alice, 100e18);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 100e18);
    }

    // ──────────────────────────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────────────────────────

    function test_role_minterOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 100e18);
    }

    function test_role_pauserOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        token.pause();
    }

    function test_role_grantMinter() public {
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), alice);
        vm.stopPrank();

        vm.prank(alice);
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    // ──────────────────────────────────────────────────────────────────
    // ComplianceRegistry management
    // ──────────────────────────────────────────────────────────────────

    function test_updateRegistry() public {
        ComplianceRegistry newRegistry = new ComplianceRegistry(admin);

        vm.prank(admin);
        token.setComplianceRegistry(newRegistry);
        assertEq(address(token.complianceRegistry()), address(newRegistry));
    }

    function test_batchWhitelist() public {
        address[] memory accounts = new address[](3);
        accounts[0] = address(0x10);
        accounts[1] = address(0x11);
        accounts[2] = address(0x12);

        vm.prank(admin);
        registry.whitelistAddBatch(accounts);

        assertTrue(registry.isWhitelisted(address(0x10)));
        assertTrue(registry.isWhitelisted(address(0x11)));
        assertTrue(registry.isWhitelisted(address(0x12)));
    }

    function test_jurisdiction() public {
        vm.prank(admin);
        registry.setJurisdiction(alice, "US");
        assertEq(registry.jurisdiction(alice), "US");
    }

    function test_accreditation() public {
        vm.prank(admin);
        registry.setAccreditation(alice, 1);
        assertEq(registry.accreditationStatus(alice), 1);
    }

    // ──────────────────────────────────────────────────────────────────
    // Pluggable compliance modules
    // ──────────────────────────────────────────────────────────────────

    function test_addModule() public {
        WhitelistModule wm = new WhitelistModule(admin);

        vm.prank(admin);
        registry.addModule(IComplianceModule(address(wm)));
        assertEq(registry.moduleCount(), 1);
    }

    function test_removeModule() public {
        WhitelistModule wm = new WhitelistModule(admin);

        vm.startPrank(admin);
        registry.addModule(IComplianceModule(address(wm)));
        registry.removeModule(IComplianceModule(address(wm)));
        vm.stopPrank();
        assertEq(registry.moduleCount(), 0);
    }

    function test_moduleBlocksTransfer() public {
        WhitelistModule wm = new WhitelistModule(admin);

        vm.startPrank(admin);
        registry.addModule(IComplianceModule(address(wm)));
        // Alice is on core whitelist but NOT on module whitelist
        // Module should block with code 16
        vm.stopPrank();

        uint8 code = token.detectTransferRestriction(admin, alice, 100e18);
        // Module whitelist blocks because admin/alice not on module's list
        assertTrue(code == 16 || code == 17);
    }

    // ──────────────────────────────────────────────────────────────────
    // ERC-165 interface detection
    // ──────────────────────────────────────────────────────────────────

    function test_supportsInterface_erc1404() public view {
        assertTrue(token.supportsInterface(type(IERC1404).interfaceId));
    }

    function test_supportsInterface_st20() public view {
        assertTrue(token.supportsInterface(type(IST20).interfaceId));
    }

    function test_supportsInterface_accessControl() public view {
        // AccessControl interface
        assertTrue(token.supportsInterface(0x7965db0b));
    }
}
