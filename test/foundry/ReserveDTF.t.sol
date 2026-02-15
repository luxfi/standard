// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";

import "../../contracts/dtf/ReserveDTF.sol";
import {MockERC20} from "./TestMocks.sol";

contract ReserveDTFTest is Test {
    MockERC20 internal usdc;
    MockERC20 internal dai;
    MockERC20 internal stEth;
    MockERC20 internal aUsdc;
    MockERC20 internal weth;
    MockERC20 internal wbtc;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal harvester = makeAddr("harvester");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant INITIAL_BALANCE = 10_000e18;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 18);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        stEth = new MockERC20("Staked ETH", "stETH", 18);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 18);

        _mintFor(alice);
        _mintFor(bob);
        _mintFor(harvester);
    }

    function test_StableDTF_MintAndRedeemAgainstBasket() public {
        ReserveDTF stable = new ReserveDTF(
            "Stable DTF",
            "sDTF",
            ReserveDTF.Category.STABLE,
            address(this),
            feeRecipient,
            keccak256("USD"),
            11_000
        );

        stable.addComponent(address(usdc), 6_000, false);
        stable.addComponent(address(dai), 4_000, false);

        (uint256[] memory inAmounts,,) = stable.previewMint(100e18);
        assertEq(inAmounts.length, 2);
        assertEq(inAmounts[0], 60e18);
        assertEq(inAmounts[1], 40e18);
        assertEq(stable.pegReference(), keccak256("USD"));
        assertEq(stable.minCollateralRatioBps(), 11_000);

        vm.startPrank(alice);
        usdc.approve(address(stable), type(uint256).max);
        dai.approve(address(stable), type(uint256).max);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = inAmounts[0];
        maxAmountsIn[1] = inAmounts[1];
        stable.mint(100e18, maxAmountsIn);

        uint256[] memory minAmountsOut = new uint256[](2);
        stable.redeem(50e18, minAmountsOut);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), 50e18);
        assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - 60e18 + 30e18);
        assertEq(dai.balanceOf(alice), INITIAL_BALANCE - 40e18 + 20e18);
    }

    function test_YieldDTF_HarvestAccruesToAllHolders() public {
        ReserveDTF yieldDTF = new ReserveDTF(
            "Yield DTF",
            "yDTF",
            ReserveDTF.Category.YIELD,
            address(this),
            feeRecipient,
            bytes32(0),
            0
        );

        yieldDTF.addComponent(address(stEth), 7_000, true);
        yieldDTF.addComponent(address(aUsdc), 3_000, true);
        yieldDTF.grantRole(yieldDTF.HARVESTER_ROLE(), harvester);

        (uint256[] memory inAmounts,,) = yieldDTF.previewMint(100e18);
        assertEq(inAmounts[0], 70e18);
        assertEq(inAmounts[1], 30e18);

        vm.startPrank(bob);
        stEth.approve(address(yieldDTF), type(uint256).max);
        aUsdc.approve(address(yieldDTF), type(uint256).max);
        yieldDTF.mint(100e18, inAmounts);
        vm.stopPrank();

        vm.startPrank(harvester);
        stEth.approve(address(yieldDTF), 14e18);
        yieldDTF.harvestYield(address(stEth), 14e18);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256[] memory minAmountsOut = new uint256[](2);
        yieldDTF.redeem(100e18, minAmountsOut);
        vm.stopPrank();

        // Bob started with 10_000 of each asset:
        // Deposit: -70 stETH / -30 aUSDC
        // Redeem after harvest: +84 stETH / +30 aUSDC
        assertEq(stEth.balanceOf(bob), INITIAL_BALANCE - 70e18 + 84e18);
        assertEq(aUsdc.balanceOf(bob), INITIAL_BALANCE);
    }

    function test_IndexDTF_ManagementAndMintFeesWithDutchAuctionRebalance() public {
        ReserveDTF indexDTF = new ReserveDTF(
            "Index DTF",
            "iDTF",
            ReserveDTF.Category.INDEX,
            address(this),
            feeRecipient,
            bytes32(0),
            0
        );

        indexDTF.addComponent(address(weth), 5_000, false);
        indexDTF.addComponent(address(wbtc), 5_000, false);
        indexDTF.setFees(50, 200); // 0.5% mint fee, 2% annual management fee

        (uint256[] memory inAmounts, uint256 mintFeeShares,) = indexDTF.previewMint(100e18);
        assertEq(mintFeeShares, 0.5e18);

        vm.startPrank(alice);
        weth.approve(address(indexDTF), type(uint256).max);
        wbtc.approve(address(indexDTF), type(uint256).max);
        indexDTF.mint(100e18, inAmounts);
        vm.stopPrank();

        assertEq(indexDTF.balanceOf(alice), 100e18);
        assertEq(indexDTF.balanceOf(feeRecipient), 0.5e18);

        vm.warp(block.timestamp + 365 days);
        indexDTF.accrueManagementFee();
        assertEq(indexDTF.balanceOf(feeRecipient), 2.51e18);

        indexDTF.startRebalanceAuction(1 days, 500, 50, keccak256("basket-v1"));
        vm.warp(block.timestamp + 12 hours);
        assertEq(indexDTF.currentAuctionPremiumBps(), 275);

        indexDTF.finishRebalanceAuction(keccak256("basket-v2"));
        (bool active,,,,,) = indexDTF.auction();
        assertFalse(active);
    }

    function test_CategoryGuards() public {
        ReserveDTF stable = new ReserveDTF(
            "Stable DTF",
            "sDTF",
            ReserveDTF.Category.STABLE,
            address(this),
            feeRecipient,
            keccak256("USD"),
            11_000
        );
        stable.addComponent(address(usdc), 6_000, false);
        stable.addComponent(address(dai), 4_000, false);

        vm.expectRevert(ReserveDTF.WrongCategory.selector);
        stable.startRebalanceAuction(1 days, 500, 50, keccak256("basket"));

        vm.expectRevert(ReserveDTF.WrongCategory.selector);
        stable.harvestYield(address(usdc), 1e18);
    }

    function _mintFor(address user) internal {
        usdc.mint(user, INITIAL_BALANCE);
        dai.mint(user, INITIAL_BALANCE);
        stEth.mint(user, INITIAL_BALANCE);
        aUsdc.mint(user, INITIAL_BALANCE);
        weth.mint(user, INITIAL_BALANCE);
        wbtc.mint(user, INITIAL_BALANCE);
    }
}
