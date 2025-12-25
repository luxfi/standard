// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/tokens/LUX.sol";
import "../../contracts/bridge/Bridge.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract LUXTest is Test {
    LUX public token;
    Bridge public bridge;
    
    address public owner;
    address public user1;
    address public user2;
    
    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        
        // Deploy contracts
        token = new LUX();
        bridge = new Bridge();
        
        // Configure bridge
        token.configure(address(bridge));
    }
    
    function testTokenMetadata() public {
        assertEq(token.name(), "LUX");
        assertEq(token.symbol(), "LUX");
        assertEq(token.decimals(), 18);
    }
    
    function testBlacklistFunctionality() public {
        // Add user to blacklist
        token.blacklistAddress(user1);
        assertTrue(token.isBlacklisted(user1));
        
        // Check non-blacklisted user
        assertFalse(token.isBlacklisted(user2));
    }
    
    function testTransferBlacklisted() public {
        // Mint tokens to owner
        token.mint(owner, 1000e18);
        
        // Blacklist user1
        token.blacklistAddress(user1);
        
        // Transfer should fail
        vm.expectRevert("Address is on blacklist");
        token.transfer(user1, 100e18);
    }
    
    function testTransferAllowed() public {
        // Mint tokens to owner
        token.mint(owner, 1000e18);
        
        // Transfer should succeed
        token.transfer(user2, 100e18);
        assertEq(token.balanceOf(user2), 100e18);
    }
    
    function testPauseUnpause() public {
        // Pause the contract
        token.pause();
        
        // Mint tokens while paused
        token.mint(owner, 1000e18);
        
        // Transfer should fail while paused (OZ v5 uses custom errors)
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(user1, 100e18);
        
        // Unpause
        token.unpause();
        
        // Transfer should succeed after unpause
        token.transfer(user1, 100e18);
        assertEq(token.balanceOf(user1), 100e18);
    }
    
    function testBridgeMint() public {
        // Only bridge can mint
        vm.prank(address(bridge));
        token.bridgeMint(user1, 1000e18);
        assertEq(token.balanceOf(user1), 1000e18);
        
        // Non-bridge cannot mint
        vm.expectRevert("Caller is not the bridge");
        token.bridgeMint(user1, 1000e18);
    }
    
    function testBridgeBurn() public {
        // Setup: mint tokens first
        vm.prank(address(bridge));
        token.bridgeMint(user1, 1000e18);
        
        // Only bridge can burn
        vm.prank(address(bridge));
        token.bridgeBurn(user1, 500e18);
        assertEq(token.balanceOf(user1), 500e18);
        
        // Non-bridge cannot burn
        vm.expectRevert("Caller is not the bridge");
        token.bridgeBurn(user1, 100e18);
    }
    
    function testAirdrop() public {
        address[] memory addresses = new address[](3);
        addresses[0] = user1;
        addresses[1] = user2;
        addresses[2] = address(0x3);
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;
        
        // Perform airdrop
        uint256 count = token.airdrop(addresses, amounts);
        assertEq(count, 3);
        
        // Check balances
        assertEq(token.balanceOf(user1), 100e18);
        assertEq(token.balanceOf(user2), 200e18);
        assertEq(token.balanceOf(address(0x3)), 300e18);
    }
    
    function testAirdropDone() public {
        // Complete initial airdrop
        token.airdropDone();
        
        // Cannot mint after airdrop is done
        vm.expectRevert("Airdrop cannot be run again after being completed");
        token.mint(user1, 100e18);
        
        // Cannot run airdrop again
        address[] memory addresses = new address[](1);
        addresses[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;
        
        vm.expectRevert("Airdrop cannot be run again after being completed");
        token.airdrop(addresses, amounts);
    }
    
    function testFuzzTransfer(address to, uint256 amount) public {
        // Assume valid recipient
        vm.assume(to != address(0));
        vm.assume(to != owner);
        vm.assume(!token.isBlacklisted(to));
        
        // Bound amount to reasonable range
        amount = bound(amount, 1, 1000000e18);
        
        // Mint tokens
        token.mint(owner, amount);
        
        // Transfer should succeed
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
    }
}