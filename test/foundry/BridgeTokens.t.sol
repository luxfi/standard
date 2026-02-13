// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "../../contracts/bridge/LRC20B.sol";
import "../../contracts/liquid/tokens/LETH.sol";
import "../../contracts/liquid/tokens/LBTC.sol";
import "../../contracts/liquid/tokens/LUSD.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title BridgeTokensTest
 * @notice Comprehensive tests for MPC-controlled bridge tokens (L* prefix)
 * @dev Tests cover admin-only minting/burning, role management, transfers, and edge cases
 * @dev Zoo tokens (Z* prefix) are tested in the @zooai/contracts package
 */
contract BridgeTokensTest is Test {
    // Lux bridge tokens
    LuxETH public leth;
    LuxBTC public lbtc;
    LuxUSD public lusd;

    // Test accounts
    address public deployer;
    address public admin1;
    address public admin2;
    address public mpcBridge;
    address public user1;
    address public user2;
    address public attacker;

    // Events to test
    event BridgeMint(address indexed account, uint amount);
    event BridgeBurn(address indexed account, uint amount);
    event AdminGranted(address to);
    event AdminRevoked(address to);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        // Setup test accounts
        deployer = address(this);
        admin1 = makeAddr("admin1");
        admin2 = makeAddr("admin2");
        mpcBridge = makeAddr("mpcBridge");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");

        // Deploy Lux bridge tokens
        leth = new LuxETH();
        lbtc = new LuxBTC();
        lusd = new LuxUSD();

        // Grant admin role to MPC bridge
        leth.grantAdmin(mpcBridge);
        lbtc.grantAdmin(mpcBridge);
        lusd.grantAdmin(mpcBridge);

        // Grant minter role to MPC bridge (C-03 security fix requires separate MINTER_ROLE)
        leth.grantMinter(mpcBridge);
        lbtc.grantMinter(mpcBridge);
        lusd.grantMinter(mpcBridge);
    }

    /*//////////////////////////////////////////////////////////////
                            METADATA TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LuxTokenMetadata() public view {
        assertEq(leth.name(), "Liquid ETH");
        assertEq(leth.symbol(), "LETH");
        assertEq(leth.decimals(), 18);

        assertEq(lbtc.name(), "Liquid BTC");
        assertEq(lbtc.symbol(), "LBTC");
        assertEq(lbtc.decimals(), 18);

        assertEq(lusd.name(), "Liquid Dollar");
        assertEq(lusd.symbol(), "LUSD");
        assertEq(lusd.decimals(), 18);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_DeployerHasAdminRole() public view {
        assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), deployer));
    }

    function test_GrantAdminRole() public {
        vm.expectEmit(true, false, false, true);
        emit AdminGranted(admin1);
        leth.grantAdmin(admin1);

        assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admin1));
    }

    function test_GrantAdminRole_MultipleAdmins() public {
        leth.grantAdmin(admin1);
        leth.grantAdmin(admin2);

        assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admin1));
        assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admin2));
    }

    function test_RevokeAdminRole() public {
        leth.grantAdmin(admin1);

        vm.expectEmit(true, false, false, true);
        emit AdminRevoked(admin1);
        leth.revokeAdmin(admin1);

        assertFalse(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admin1));
    }

    function testRevert_RevokeNonAdmin() public {
        vm.expectRevert("LRC20B: not an admin");
        leth.revokeAdmin(user1);
    }

    function testRevert_GrantAdmin_Unauthorized() public {
        vm.prank(attacker);
        vm.expectRevert("LRC20B: caller is not admin");
        leth.grantAdmin(admin1);
    }

    function testRevert_RevokeAdmin_Unauthorized() public {
        leth.grantAdmin(admin1);

        vm.prank(attacker);
        vm.expectRevert("LRC20B: caller is not admin");
        leth.revokeAdmin(admin1);
    }

    /*//////////////////////////////////////////////////////////////
                        MINTING TESTS (ADMIN ONLY)
    //////////////////////////////////////////////////////////////*/

    function test_MintByAdmin() public {
        uint256 amount = 100e18;

        vm.prank(mpcBridge);
        leth.mint(user1, amount);

        assertEq(leth.balanceOf(user1), amount);
        assertEq(leth.totalSupply(), amount);
    }

    function test_BridgeMintByAdmin() public {
        uint256 amount = 50e18;

        vm.expectEmit(true, false, false, true);
        emit BridgeMint(user1, amount);

        vm.prank(mpcBridge);
        bool success = leth.bridgeMint(user1, amount);

        assertTrue(success);
        assertEq(leth.balanceOf(user1), amount);
    }

    function test_MintMultipleTokens() public {
        vm.startPrank(mpcBridge);

        leth.mint(user1, 10e18);
        lbtc.mint(user1, 20e18);
        lusd.mint(user1, 30e18);

        vm.stopPrank();

        assertEq(leth.balanceOf(user1), 10e18);
        assertEq(lbtc.balanceOf(user1), 20e18);
        assertEq(lusd.balanceOf(user1), 30e18);
    }

    function test_MintToMultipleAddresses() public {
        vm.startPrank(mpcBridge);

        leth.mint(user1, 100e18);
        leth.mint(user2, 200e18);

        vm.stopPrank();

        assertEq(leth.balanceOf(user1), 100e18);
        assertEq(leth.balanceOf(user2), 200e18);
        assertEq(leth.totalSupply(), 300e18);
    }

    function testRevert_MintByNonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert("LRC20B: caller is not admin");
        leth.mint(user1, 100e18);
    }

    function testRevert_BridgeMintByNonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert("LRC20B: caller is not minter");
        leth.bridgeMint(user1, 100e18);
    }

    function testRevert_MintToZeroAddress() public {
        vm.prank(mpcBridge);
        vm.expectRevert(); // ERC20 reverts on mint to zero address
        leth.mint(address(0), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        BURNING TESTS (ADMIN ONLY)
    //////////////////////////////////////////////////////////////*/

    function test_BurnByAdmin() public {
        // Setup: mint tokens first
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        // Burn tokens
        vm.prank(mpcBridge);
        leth.burn(user1, 50e18);

        assertEq(leth.balanceOf(user1), 50e18);
        assertEq(leth.totalSupply(), 50e18);
    }

    function test_BridgeBurnByAdmin() public {
        // Setup: mint tokens first
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        // H-02 fix: bridgeBurn now requires allowance when burning from another address
        vm.prank(user1);
        leth.approve(mpcBridge, 60e18);

        vm.expectEmit(true, false, false, true);
        emit BridgeBurn(user1, 60e18);

        // Bridge burn
        vm.prank(mpcBridge);
        bool success = leth.bridgeBurn(user1, 60e18);

        assertTrue(success);
        assertEq(leth.balanceOf(user1), 40e18);
    }

    function test_BurnEntireBalance() public {
        vm.startPrank(mpcBridge);
        leth.mint(user1, 100e18);
        leth.burn(user1, 100e18);
        vm.stopPrank();

        assertEq(leth.balanceOf(user1), 0);
        assertEq(leth.totalSupply(), 0);
    }

    function testRevert_BurnByNonAdmin() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        vm.prank(attacker);
        vm.expectRevert("LRC20B: caller is not admin");
        leth.burn(user1, 50e18);
    }

    function testRevert_BridgeBurnByNonAdmin() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        vm.prank(attacker);
        vm.expectRevert("LRC20B: caller is not admin");
        leth.bridgeBurn(user1, 50e18);
    }

    function testRevert_BurnInsufficientBalance() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 50e18);

        vm.prank(mpcBridge);
        vm.expectRevert(); // ERC20 reverts on insufficient balance
        leth.burn(user1, 100e18);
    }

    function testRevert_BurnFromZeroAddress() public {
        vm.prank(mpcBridge);
        vm.expectRevert(); // ERC20 reverts on burn from zero address
        leth.burn(address(0), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferByUser() public {
        // Setup: mint tokens to user1
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        // User transfers tokens
        vm.prank(user1);
        leth.transfer(user2, 40e18);

        assertEq(leth.balanceOf(user1), 60e18);
        assertEq(leth.balanceOf(user2), 40e18);
    }

    function test_TransferFrom() public {
        // Setup: mint and approve
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        vm.prank(user1);
        leth.approve(user2, 50e18);

        // User2 transfers from user1
        vm.prank(user2);
        leth.transferFrom(user1, user2, 30e18);

        assertEq(leth.balanceOf(user1), 70e18);
        assertEq(leth.balanceOf(user2), 30e18);
        assertEq(leth.allowance(user1, user2), 20e18);
    }

    function test_MultipleTransfers() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 1000e18);

        vm.startPrank(user1);
        leth.transfer(user2, 100e18);
        leth.transfer(user2, 200e18);
        leth.transfer(user2, 300e18);
        vm.stopPrank();

        assertEq(leth.balanceOf(user1), 400e18);
        assertEq(leth.balanceOf(user2), 600e18);
    }

    function testRevert_TransferInsufficientBalance() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 50e18);

        vm.prank(user1);
        vm.expectRevert(); // ERC20 reverts on insufficient balance
        leth.transfer(user2, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN COORDINATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CrossChainMintBurn_LuxBridge() public {
        // Simulate cross-chain transfer from external chain to Lux
        uint256 amount = 10e18;

        // Step 1: External deposit verified by MPC, mint LETH on Lux
        vm.prank(mpcBridge);
        leth.mint(user1, amount);
        assertEq(leth.balanceOf(user1), amount);

        // Step 2: User withdraws LETH (burns for external release)
        vm.prank(mpcBridge);
        leth.burn(user1, amount);
        assertEq(leth.balanceOf(user1), 0);
    }

    function test_MultiTokenBridge() public {
        uint256 ethAmount = 5e18;
        uint256 btcAmount = 1e18;
        uint256 usdAmount = 1000e18;

        vm.startPrank(mpcBridge);

        // Mint multiple token types
        leth.mint(user1, ethAmount);
        lbtc.mint(user1, btcAmount);
        lusd.mint(user1, usdAmount);

        vm.stopPrank();

        // Verify balances
        assertEq(leth.balanceOf(user1), ethAmount);
        assertEq(lbtc.balanceOf(user1), btcAmount);
        assertEq(lusd.balanceOf(user1), usdAmount);

        vm.startPrank(mpcBridge);

        // Burn for withdrawal
        leth.burn(user1, ethAmount);
        lbtc.burn(user1, btcAmount);
        lusd.burn(user1, usdAmount);

        vm.stopPrank();

        // Verify balances are zero
        assertEq(leth.balanceOf(user1), 0);
        assertEq(lbtc.balanceOf(user1), 0);
        assertEq(lusd.balanceOf(user1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintZeroAmount() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 0);

        assertEq(leth.balanceOf(user1), 0);
        assertEq(leth.totalSupply(), 0);
    }

    function test_BurnZeroAmount() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        vm.prank(mpcBridge);
        leth.burn(user1, 0);

        assertEq(leth.balanceOf(user1), 100e18);
    }

    function test_TransferZeroAmount() public {
        vm.prank(mpcBridge);
        leth.mint(user1, 100e18);

        vm.prank(user1);
        leth.transfer(user2, 0);

        assertEq(leth.balanceOf(user1), 100e18);
        assertEq(leth.balanceOf(user2), 0);
    }

    function test_MultipleAdminsCanMint() public {
        leth.grantAdmin(admin1);
        leth.grantAdmin(admin2);

        vm.prank(admin1);
        leth.mint(user1, 100e18);

        vm.prank(admin2);
        leth.mint(user2, 200e18);

        assertEq(leth.balanceOf(user1), 100e18);
        assertEq(leth.balanceOf(user2), 200e18);
    }

    function test_RevokedAdminCannotMint() public {
        leth.grantAdmin(admin1);
        leth.revokeAdmin(admin1);

        vm.prank(admin1);
        vm.expectRevert("LRC20B: caller is not admin");
        leth.mint(user1, 100e18);
    }

    function test_LargeAmountMinting() public {
        uint256 largeAmount = type(uint256).max / 2;

        vm.prank(mpcBridge);
        leth.mint(user1, largeAmount);

        assertEq(leth.balanceOf(user1), largeAmount);
        assertEq(leth.totalSupply(), largeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_MintAmount(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2);

        vm.prank(mpcBridge);
        leth.mint(user1, amount);

        assertEq(leth.balanceOf(user1), amount);
        assertEq(leth.totalSupply(), amount);
    }

    function testFuzz_BurnAmount(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(mintAmount < type(uint256).max / 2);
        vm.assume(burnAmount <= mintAmount);

        vm.startPrank(mpcBridge);
        leth.mint(user1, mintAmount);
        leth.burn(user1, burnAmount);
        vm.stopPrank();

        assertEq(leth.balanceOf(user1), mintAmount - burnAmount);
        assertEq(leth.totalSupply(), mintAmount - burnAmount);
    }

    function testFuzz_TransferAmount(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(mintAmount < type(uint256).max / 2);
        vm.assume(transferAmount <= mintAmount);

        vm.prank(mpcBridge);
        leth.mint(user1, mintAmount);

        vm.prank(user1);
        leth.transfer(user2, transferAmount);

        assertEq(leth.balanceOf(user1), mintAmount - transferAmount);
        assertEq(leth.balanceOf(user2), transferAmount);
    }

    function testFuzz_MultipleAdmins(uint8 adminCount) public {
        vm.assume(adminCount > 0 && adminCount <= 50);

        address[] memory admins = new address[](adminCount);

        // Grant admin roles
        for (uint8 i = 0; i < adminCount; i++) {
            admins[i] = address(uint160(1000 + i));
            leth.grantAdmin(admins[i]);
            assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admins[i]));
        }

        // Each admin can mint
        for (uint8 i = 0; i < adminCount; i++) {
            address recipient = address(uint160(2000 + i));
            vm.prank(admins[i]);
            leth.mint(recipient, 100e18);
            assertEq(leth.balanceOf(recipient), 100e18);
        }
    }

    function testFuzz_CrossChainMintBurn(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2);

        vm.startPrank(mpcBridge);

        // Lux: mint and burn
        leth.mint(user1, amount);
        leth.burn(user1, amount);
        assertEq(leth.balanceOf(user1), 0);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    OWNER/DEPLOYER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeployerIsOwner() public view {
        assertEq(leth.owner(), deployer);
    }

    function test_OwnerHasDefaultAdminRole() public view {
        assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), deployer));
    }

    function test_OwnerCanGrantAdmin() public {
        // Deployer (owner) can grant admin
        leth.grantAdmin(admin1);
        assertTrue(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admin1));
    }

    function test_OwnerCanRevokeAdmin() public {
        leth.grantAdmin(admin1);
        leth.revokeAdmin(admin1);
        assertFalse(leth.hasRole(leth.DEFAULT_ADMIN_ROLE(), admin1));
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FullBridgeWorkflow() public {
        uint256 depositAmount = 10e18;
        uint256 withdrawAmount = 7e18;

        vm.startPrank(mpcBridge);

        // 1. User deposits ETH on external chain, MPC mints LETH
        leth.mint(user1, depositAmount);
        assertEq(leth.balanceOf(user1), depositAmount);

        // 2. User transfers some to user2
        vm.stopPrank();
        vm.prank(user1);
        leth.transfer(user2, 3e18);

        // 3. User1 withdraws remaining to external chain
        vm.prank(mpcBridge);
        leth.burn(user1, withdrawAmount);
        assertEq(leth.balanceOf(user1), 0);
        assertEq(leth.balanceOf(user2), 3e18);

        vm.stopPrank();
    }

    function test_MultiUserBridging() public {
        vm.startPrank(mpcBridge);

        // User1 deposits on Lux
        leth.mint(user1, 5e18);
        lbtc.mint(user1, 1e18);

        // User2 deposits on Lux
        leth.mint(user2, 10e18);
        lusd.mint(user2, 1000e18);

        vm.stopPrank();

        // Verify final state
        assertEq(leth.balanceOf(user1), 5e18);
        assertEq(leth.balanceOf(user2), 10e18);
        assertEq(lbtc.balanceOf(user1), 1e18);
        assertEq(lusd.balanceOf(user2), 1000e18);
    }
}
