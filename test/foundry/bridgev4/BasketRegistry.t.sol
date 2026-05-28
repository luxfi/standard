// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { BasketRegistry } from "../../../contracts/bridge/v4/BasketRegistry.sol";

contract BasketRegistryTest is Test {
    BasketRegistry internal registry;
    address internal admin = makeAddr("admin");
    address internal randomUser = makeAddr("random");
    address internal usdt = makeAddr("usdt");
    address internal usdc = makeAddr("usdc");
    address internal dai = makeAddr("dai");

    function setUp() public {
        vm.prank(admin);
        registry = new BasketRegistry(admin);
    }

    function test_AdminCanAddAsset() public {
        vm.prank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        assertTrue(registry.isInBasket(BasketRegistry.BasketClass.USD, usdt));
        assertEq(registry.basketSize(BasketRegistry.BasketClass.USD), 1);
    }

    function test_NonAdminCannotAddAsset() public {
        vm.prank(randomUser);
        vm.expectRevert();
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
    }

    function test_CannotAddZeroAsset() public {
        vm.prank(admin);
        vm.expectRevert(BasketRegistry.BasketRegistry_ZeroAddress.selector);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, address(0), 0);
    }

    function test_CannotDoubleAddAsset() public {
        vm.startPrank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        vm.expectRevert(BasketRegistry.BasketRegistry_AlreadyRegistered.selector);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        vm.stopPrank();
    }

    function test_BasketIteration() public {
        vm.startPrank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdc, 1);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, dai, 2);
        vm.stopPrank();

        address[] memory members = registry.getBasketMembers(BasketRegistry.BasketClass.USD);
        assertEq(members.length, 3);
        assertEq(members[0], usdt);
        assertEq(members[1], usdc);
        assertEq(members[2], dai);

        assertEq(registry.priceFeedIdxOf(BasketRegistry.BasketClass.USD, dai), 2);
    }

    function test_RemoveAssetWithZeroReserve() public {
        vm.startPrank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdc, 1);
        registry.removeAssetFromBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        vm.stopPrank();

        assertFalse(registry.isInBasket(BasketRegistry.BasketClass.USD, usdt));
        assertEq(registry.basketSize(BasketRegistry.BasketClass.USD), 1);
        // After swap-and-pop, usdc should still be at index 0
        address[] memory members = registry.getBasketMembers(BasketRegistry.BasketClass.USD);
        assertEq(members[0], usdc);
    }

    function test_CannotRemoveWithNonZeroReserve() public {
        vm.startPrank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        vm.expectRevert(BasketRegistry.BasketRegistry_NonZeroReserve.selector);
        registry.removeAssetFromBasket(BasketRegistry.BasketClass.USD, usdt, 1_000_000);
        vm.stopPrank();
    }

    function test_CannotRemoveUnregistered() public {
        vm.prank(admin);
        vm.expectRevert(BasketRegistry.BasketRegistry_NotRegistered.selector);
        registry.removeAssetFromBasket(BasketRegistry.BasketClass.USD, usdt, 0);
    }

    function test_priceFeedIdxOfUnregistered_Reverts() public {
        vm.expectRevert(BasketRegistry.BasketRegistry_NotRegistered.selector);
        registry.priceFeedIdxOf(BasketRegistry.BasketClass.USD, usdt);
    }

    function test_DifferentBasketsIsolated() public {
        vm.startPrank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        registry.addAssetToBasket(BasketRegistry.BasketClass.BTC, usdt, 0);
        vm.stopPrank();
        assertTrue(registry.isInBasket(BasketRegistry.BasketClass.USD, usdt));
        assertTrue(registry.isInBasket(BasketRegistry.BasketClass.BTC, usdt));

        vm.prank(admin);
        registry.removeAssetFromBasket(BasketRegistry.BasketClass.USD, usdt, 0);

        assertFalse(registry.isInBasket(BasketRegistry.BasketClass.USD, usdt));
        assertTrue(registry.isInBasket(BasketRegistry.BasketClass.BTC, usdt));
    }

    function test_RemoveLastMemberInBasket() public {
        vm.startPrank(admin);
        registry.addAssetToBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        registry.removeAssetFromBasket(BasketRegistry.BasketClass.USD, usdt, 0);
        vm.stopPrank();

        assertEq(registry.basketSize(BasketRegistry.BasketClass.USD), 0);
        address[] memory members = registry.getBasketMembers(BasketRegistry.BasketClass.USD);
        assertEq(members.length, 0);
    }

    function testFuzz_AddManyAssets(uint8 n) public {
        n = uint8(bound(n, 1, 32));
        vm.startPrank(admin);
        for (uint160 i = 1; i <= n; i++) {
            registry.addAssetToBasket(BasketRegistry.BasketClass.ETH, address(i), uint8(i % 8));
        }
        vm.stopPrank();
        assertEq(registry.basketSize(BasketRegistry.BasketClass.ETH), n);
        for (uint160 i = 1; i <= n; i++) {
            assertTrue(registry.isInBasket(BasketRegistry.BasketClass.ETH, address(i)));
        }
    }
}
