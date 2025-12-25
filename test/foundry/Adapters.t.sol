// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Adapters
import {sLUXAdapter} from "../../contracts/synths/adapters/sLUXAdapter.sol";
import {YearnTokenAdapter} from "../../contracts/synths/adapters/yearn/YearnTokenAdapter.sol";
import {GMXYieldAdapter} from "../../contracts/core/adapters/gmx/GMXYieldAdapter.sol";
import {CompoundAdapter} from "../../contracts/core/adapters/compound/CompoundAdapter.sol";

// Supporting contracts
import {sLUX} from "../../contracts/staking/sLUX.sol";

// Interfaces
import {ITokenAdapter} from "../../contracts/synths/interfaces/ITokenAdapter.sol";

/**
 * @title Adapters Test Suite
 * @notice Comprehensive tests for all adapter contracts
 */
contract AdaptersTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // MOCK CONTRACTS
    // ═══════════════════════════════════════════════════════════════════════════

    MockERC20 public lux;
    MockERC20 public usdc;
    MockERC20 public weth;
    MocksLUX public mockSLUX;
    MockYearnVault public mockYearnVault;
    MockGMXContracts public mockGMX;
    MockPriceOracle public mockOracle;

    // Adapters
    sLUXAdapter public sluxAdapter;
    YearnTokenAdapter public yearnAdapter;
    GMXYieldAdapter public gmxAdapter;
    CompoundAdapter public compoundAdapter;

    // Test users
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public keeper = address(0xC0FFEE);

    // Constants
    uint256 public constant INITIAL_MINT = 1_000_000e18;
    uint256 public constant STAKE_AMOUNT = 100e18;

    function setUp() public {
        // Deploy mock tokens
        lux = new MockERC20("LUX", "LUX", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        weth = new MockERC20("WETH", "WETH", 18);

        // Deploy sLUX and adapter
        mockSLUX = new MocksLUX(address(lux));
        sluxAdapter = new sLUXAdapter(address(mockSLUX));

        // Deploy Yearn mock and adapter
        mockYearnVault = new MockYearnVault(address(weth));
        yearnAdapter = new YearnTokenAdapter(address(mockYearnVault), address(weth));

        // Deploy GMX mocks and adapter
        mockGMX = new MockGMXContracts(address(weth));
        gmxAdapter = new GMXYieldAdapter(
            address(mockGMX.rewardRouter()),
            address(mockGMX.glpManager()),
            address(mockGMX.glp()),
            address(mockGMX.feeTracker()),
            address(weth)
        );

        // Deploy price oracle and Compound adapter
        mockOracle = new MockPriceOracle();
        compoundAdapter = new CompoundAdapter(address(mockOracle));
        compoundAdapter.initializePool(address(usdc), 1000, 1000); // 10% APR, 10% reserve

        // Fund test users
        lux.mint(alice, INITIAL_MINT);
        lux.mint(bob, INITIAL_MINT);
        weth.mint(alice, INITIAL_MINT);
        weth.mint(bob, INITIAL_MINT);
        usdc.mint(alice, INITIAL_MINT / 1e12); // USDC is 6 decimals
        usdc.mint(bob, INITIAL_MINT / 1e12);

        // Label addresses for traces
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(keeper, "Keeper");
        vm.label(address(sluxAdapter), "sLUXAdapter");
        vm.label(address(yearnAdapter), "YearnAdapter");
        vm.label(address(gmxAdapter), "GMXAdapter");
        vm.label(address(compoundAdapter), "CompoundAdapter");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // sLUX ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_sLUXAdapter_Initialization() public {
        assertEq(sluxAdapter.version(), "1.0.0");
        assertEq(sluxAdapter.token(), address(mockSLUX));
        assertEq(sluxAdapter.underlyingToken(), address(lux));
    }

    function test_sLUXAdapter_Price() public {
        // Initially 1:1
        uint256 price = sluxAdapter.price();
        assertEq(price, 1e18, "Initial price should be 1:1");

        // First stake some LUX to create supply
        vm.startPrank(alice);
        lux.approve(address(sluxAdapter), 100e18);
        sluxAdapter.wrap(100e18, alice);
        vm.stopPrank();

        // After rewards, price increases
        lux.mint(address(mockSLUX), 100e18);
        mockSLUX.simulateRewards(100e18);

        uint256 newPrice = sluxAdapter.price();
        assertGt(newPrice, price, "Price should increase after rewards");
    }

    function test_sLUXAdapter_Wrap() public {
        vm.startPrank(alice);
        lux.approve(address(sluxAdapter), STAKE_AMOUNT);

        uint256 luxBefore = lux.balanceOf(alice);
        uint256 sLuxAmount = sluxAdapter.wrap(STAKE_AMOUNT, alice);

        assertEq(lux.balanceOf(alice), luxBefore - STAKE_AMOUNT);
        assertEq(IERC20(address(mockSLUX)).balanceOf(alice), sLuxAmount);
        assertGt(sLuxAmount, 0, "Should mint sLUX");
        vm.stopPrank();
    }

    function test_sLUXAdapter_Unwrap() public {
        // First wrap
        vm.startPrank(alice);
        lux.approve(address(sluxAdapter), STAKE_AMOUNT);
        uint256 sLuxAmount = sluxAdapter.wrap(STAKE_AMOUNT, alice);

        // Then unwrap
        IERC20(address(mockSLUX)).approve(address(sluxAdapter), sLuxAmount);
        uint256 luxBefore = lux.balanceOf(alice);
        uint256 luxReturned = sluxAdapter.unwrap(sLuxAmount, alice);

        // Should get back roughly same amount (minus 10% penalty)
        assertApproxEqRel(luxReturned, STAKE_AMOUNT * 90 / 100, 0.01e18);
        assertEq(lux.balanceOf(alice), luxBefore + luxReturned);
        vm.stopPrank();
    }

    function testFuzz_sLUXAdapter_WrapUnwrap(uint256 amount) public {
        amount = bound(amount, 1e18, INITIAL_MINT / 10); // Min 1 LUX, max 10% of balance

        vm.startPrank(alice);
        lux.approve(address(sluxAdapter), amount);
        uint256 sLuxAmount = sluxAdapter.wrap(amount, alice);

        IERC20(address(mockSLUX)).approve(address(sluxAdapter), sLuxAmount);
        uint256 luxReturned = sluxAdapter.unwrap(sLuxAmount, alice);

        // Allow 15% slippage for instant unstake penalty
        assertApproxEqRel(luxReturned, amount * 90 / 100, 0.15e18);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // YEARN ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_YearnAdapter_Initialization() public {
        assertEq(yearnAdapter.version(), "2.1.0");
        assertEq(yearnAdapter.token(), address(mockYearnVault));
        assertEq(yearnAdapter.underlyingToken(), address(weth));
    }

    function test_YearnAdapter_Price() public {
        uint256 price = yearnAdapter.price();
        assertEq(price, mockYearnVault.pricePerShare());
    }

    function test_YearnAdapter_Wrap() public {
        vm.startPrank(alice);
        weth.approve(address(yearnAdapter), 10e18);

        uint256 wethBefore = weth.balanceOf(alice);
        uint256 shares = yearnAdapter.wrap(10e18, alice);

        assertEq(weth.balanceOf(alice), wethBefore - 10e18);
        assertEq(mockYearnVault.balanceOf(alice), shares);
        assertGt(shares, 0);
        vm.stopPrank();
    }

    function test_YearnAdapter_Unwrap() public {
        // First deposit
        vm.startPrank(alice);
        weth.approve(address(yearnAdapter), 10e18);
        uint256 shares = yearnAdapter.wrap(10e18, alice);

        // Simulate yield
        weth.mint(address(mockYearnVault), 1e18);

        // Withdraw
        mockYearnVault.approve(address(yearnAdapter), shares);
        uint256 wethBefore = weth.balanceOf(alice);
        uint256 wethReturned = yearnAdapter.unwrap(shares, alice);

        assertEq(weth.balanceOf(alice), wethBefore + wethReturned);
        assertGt(wethReturned, 10e18, "Should get more than deposited due to yield");
        vm.stopPrank();
    }

    function test_YearnAdapter_UnwrapRevertsOnPartialWithdrawal() public {
        vm.startPrank(alice);
        weth.approve(address(yearnAdapter), 10e18);
        uint256 shares = yearnAdapter.wrap(10e18, alice);

        // Make vault unable to withdraw full amount
        mockYearnVault.setWithdrawable(false);

        mockYearnVault.approve(address(yearnAdapter), shares);
        vm.expectRevert();
        yearnAdapter.unwrap(shares, alice);
        vm.stopPrank();
    }

    function testFuzz_YearnAdapter_Deposits(uint256 amount) public {
        amount = bound(amount, 1e18, INITIAL_MINT / 10);

        vm.startPrank(alice);
        weth.approve(address(yearnAdapter), amount);
        uint256 shares = yearnAdapter.wrap(amount, alice);

        assertGt(shares, 0);
        assertEq(mockYearnVault.balanceOf(alice), shares);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GMX ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GMXAdapter_Deposit() public {
        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), 10e18);

        uint256 glpReceived = gmxAdapter.deposit(address(weth), 10e18, 0);

        assertGt(glpReceived, 0, "Should receive GLP");
        (uint256 glpAmount,,,,,, ) = gmxAdapter.getPosition(alice);
        assertEq(glpAmount, glpReceived);
        vm.stopPrank();
    }

    function test_GMXAdapter_Withdraw() public {
        // First deposit
        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), 10e18);
        uint256 glpAmount = gmxAdapter.deposit(address(weth), 10e18, 0);

        // Then withdraw
        uint256 wethBefore = weth.balanceOf(alice);
        uint256 received = gmxAdapter.withdraw(address(weth), glpAmount, 0);

        assertGt(received, 0);
        assertEq(weth.balanceOf(alice), wethBefore + received);
        vm.stopPrank();
    }

    function test_GMXAdapter_ClaimFees() public {
        // Deposit to generate position
        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), 10e18);
        gmxAdapter.deposit(address(weth), 10e18, 0);

        // Simulate fees accrued
        weth.mint(address(mockGMX.feeTracker()), 1e18);
        mockGMX.feeTracker().addRewards(1e18);

        // Claim fees
        uint256 wethBefore = weth.balanceOf(alice);
        uint256 claimed = gmxAdapter.claimFees();

        assertGt(claimed, 0, "Should claim fees");
        assertEq(weth.balanceOf(alice), wethBefore + claimed);
        vm.stopPrank();
    }

    function test_GMXAdapter_IsShariahCompliant() public {
        assertTrue(gmxAdapter.isShariahCompliant());

        (bool compliant, string memory reason,,) = gmxAdapter.shariahCompliance();
        assertTrue(compliant);
        assertTrue(bytes(reason).length > 0);
    }

    function test_GMXAdapter_ProjectYield() public {
        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), 10e18);
        gmxAdapter.deposit(address(weth), 10e18, 0);

        // Simulate some fees
        weth.mint(address(mockGMX.feeTracker()), 1e18);
        mockGMX.feeTracker().addRewards(1e18);
        gmxAdapter.claimFees();

        // Fast forward and project
        vm.warp(block.timestamp + 30 days);
        uint256 projected = gmxAdapter.projectYield(alice, 30 days);

        assertGt(projected, 0, "Should project positive yield");
        vm.stopPrank();
    }

    function testFuzz_GMXAdapter_Deposits(uint256 amount) public {
        amount = bound(amount, 1e18, INITIAL_MINT / 10);

        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), amount);
        uint256 glp = gmxAdapter.deposit(address(weth), amount, 0);

        assertGt(glp, 0);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPOUND ADAPTER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CompoundAdapter_PoolInitialization() public view {
        (IERC20 asset,,,,,,,,) = compoundAdapter.pools(address(usdc));
        assertEq(address(asset), address(usdc));
    }

    function test_CompoundAdapter_Supply() public {
        vm.startPrank(alice);
        usdc.approve(address(compoundAdapter), 1000e6);
        compoundAdapter.supply(address(usdc), 1000e6);

        uint256 balance = compoundAdapter.getSupplyBalance(alice, address(usdc));
        assertEq(balance, 1000e6);
        vm.stopPrank();
    }

    function test_CompoundAdapter_Withdraw() public {
        vm.startPrank(alice);
        usdc.approve(address(compoundAdapter), 1000e6);
        compoundAdapter.supply(address(usdc), 1000e6);

        uint256 usdcBefore = usdc.balanceOf(alice);
        compoundAdapter.withdraw(address(usdc), 500e6);

        assertEq(usdc.balanceOf(alice), usdcBefore + 500e6);
        vm.stopPrank();
    }

    function test_CompoundAdapter_BorrowRepay() public {
        // Alice supplies collateral
        vm.startPrank(alice);
        weth.approve(address(compoundAdapter), 10e18);

        // Bob supplies liquidity
        vm.startPrank(bob);
        usdc.approve(address(compoundAdapter), 10000e6);
        compoundAdapter.supply(address(usdc), 10000e6);
        vm.stopPrank();

        // Alice borrows
        vm.startPrank(alice);
        compoundAdapter.borrow(address(usdc), 500e6, address(weth), 1e18);

        uint256 debt = compoundAdapter.getBorrowBalance(alice, address(usdc));
        assertEq(debt, 500e6);

        // Repay
        usdc.approve(address(compoundAdapter), 600e6);
        compoundAdapter.repay(address(usdc), type(uint256).max);

        debt = compoundAdapter.getBorrowBalance(alice, address(usdc));
        assertEq(debt, 0);
        vm.stopPrank();
    }

    function test_CompoundAdapter_InterestAccrual() public {
        // Supply and borrow
        vm.prank(bob);
        usdc.approve(address(compoundAdapter), 10000e6);
        vm.prank(bob);
        compoundAdapter.supply(address(usdc), 10000e6);

        vm.prank(alice);
        weth.approve(address(compoundAdapter), 10e18);
        vm.prank(alice);
        compoundAdapter.borrow(address(usdc), 500e6, address(weth), 2e18);

        uint256 debtBefore = compoundAdapter.getBorrowBalance(alice, address(usdc));

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        // Force interest accrual by having bob do a tiny supply
        // The view function doesn't accrue interest - need a state change
        usdc.mint(bob, 1);
        vm.prank(bob);
        usdc.approve(address(compoundAdapter), 1);
        vm.prank(bob);
        compoundAdapter.supply(address(usdc), 1);

        uint256 debtAfter = compoundAdapter.getBorrowBalance(alice, address(usdc));
        assertGt(debtAfter, debtBefore, "Debt should increase with interest");
    }

    function test_CompoundAdapter_Liquidation() public {
        // Use WETH pool for both supply and borrow to avoid decimal mismatches
        // Initialize WETH pool
        compoundAdapter.initializePool(address(weth), 1000, 1000); // 10% APR

        // Setup: Bob supplies WETH
        vm.prank(bob);
        weth.approve(address(compoundAdapter), 100e18);
        vm.prank(bob);
        compoundAdapter.supply(address(weth), 100e18);

        // Alice borrows at near-max LTV (75%) against 1 ETH collateral
        // With 1:1 pricing, 1e18 collateral allows max 0.75e18 borrow
        // Borrow 0.7e18 to be close to max
        vm.prank(alice);
        weth.approve(address(compoundAdapter), 1e18);
        vm.prank(alice);
        compoundAdapter.borrow(address(weth), 7e17, address(weth), 1e18); // 70% LTV

        // Fast forward to make position underwater via interest
        // At 10% APR, after ~2 years debt reaches ~0.85e18 > 0.8e18 liquidation threshold
        vm.warp(block.timestamp + 365 days * 3);

        // Force interest accrual
        weth.mint(bob, 1);
        vm.prank(bob);
        weth.approve(address(compoundAdapter), 1);
        vm.prank(bob);
        compoundAdapter.supply(address(weth), 1);

        uint256 healthBefore = compoundAdapter.getHealthFactor(alice, address(weth));
        // Health factor = (collateral * 0.8) / debt
        // After 3 years at 10% APR: debt = 0.7e18 * 1.3 = 0.91e18
        // health = (1e18 * 0.8) / 0.91e18 * 10000 = ~8791
        // This should be < 10000
        assertLt(healthBefore, 10000, "Position should be unhealthy");

        // Bob liquidates
        vm.prank(bob);
        weth.approve(address(compoundAdapter), 4e17);
        vm.prank(bob);
        compoundAdapter.liquidate(alice, address(weth), 4e17);

        uint256 healthAfter = compoundAdapter.getHealthFactor(alice, address(weth));
        assertGt(healthAfter, healthBefore, "Health should improve after liquidation");
    }

    function test_CompoundAdapter_NotShariahCompliant() public {
        assertFalse(compoundAdapter.isShariahCompliant());
        assertTrue(compoundAdapter.hasDebtSpiralRisk());
    }

    function test_CompoundAdapter_ProjectDebt() public {
        vm.prank(bob);
        usdc.approve(address(compoundAdapter), 10000e6);
        vm.prank(bob);
        compoundAdapter.supply(address(usdc), 10000e6);

        vm.prank(alice);
        weth.approve(address(compoundAdapter), 2e18);
        vm.prank(alice);
        compoundAdapter.borrow(address(usdc), 500e6, address(weth), 2e18);

        (uint256 current, uint256 projected, uint256 interest) =
            compoundAdapter.projectDebt(alice, address(usdc), 365 days);

        assertGt(projected, current, "Projected debt should exceed current");
        assertGt(interest, 0, "Interest should accrue");
    }

    function testFuzz_CompoundAdapter_SupplyWithdraw(uint256 amount) public {
        amount = bound(amount, 1e6, 10000e6); // USDC has 6 decimals

        vm.startPrank(alice);
        usdc.approve(address(compoundAdapter), amount);
        compoundAdapter.supply(address(usdc), amount);

        uint256 balance = compoundAdapter.getSupplyBalance(alice, address(usdc));
        assertEq(balance, amount);

        compoundAdapter.withdraw(address(usdc), amount);
        balance = compoundAdapter.getSupplyBalance(alice, address(usdc));
        assertEq(balance, 0);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES & ERROR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_sLUXAdapter_ZeroWrapAllowed() public {
        // sLUXAdapter allows zero wraps (no revert)
        // This is intentional - the underlying sLUX handles the zero case
        vm.prank(alice);
        lux.approve(address(sluxAdapter), 1e18);

        vm.prank(alice);
        uint256 result = sluxAdapter.wrap(0, alice);
        assertEq(result, 0, "Zero wrap should return zero shares");
    }

    function test_GMXAdapter_RevertOnInsufficientGLP() public {
        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), 10e18);
        uint256 glp = gmxAdapter.deposit(address(weth), 10e18, 0);

        vm.expectRevert();
        gmxAdapter.withdraw(address(weth), glp + 1, 0);
        vm.stopPrank();
    }

    function test_CompoundAdapter_RevertOnInsufficientCollateral() public {
        vm.prank(bob);
        usdc.approve(address(compoundAdapter), 10000e6);
        vm.prank(bob);
        compoundAdapter.supply(address(usdc), 10000e6);

        // With 1:1 pricing mock, 1e18 WETH = 1e18 value
        // MAX_LTV is 75%, so max borrow = 0.75e18
        // We try to borrow more than that to trigger revert
        vm.prank(alice);
        weth.approve(address(compoundAdapter), 1e18);

        // Trying to borrow 1e18 USDC (way more than 0.75e18 max)
        // Note: Using raw value since mock has 1:1 pricing regardless of decimals
        vm.expectRevert(); // InsufficientCollateral
        vm.prank(alice);
        compoundAdapter.borrow(address(usdc), 1e18, address(weth), 1e18); // Exceeds max LTV
    }

    function test_CompoundAdapter_RevertLiquidateHealthy() public {
        vm.prank(bob);
        usdc.approve(address(compoundAdapter), 10000e6);
        vm.prank(bob);
        compoundAdapter.supply(address(usdc), 10000e6);

        vm.prank(alice);
        weth.approve(address(compoundAdapter), 10e18);
        vm.prank(alice);
        compoundAdapter.borrow(address(usdc), 100e6, address(weth), 10e18); // Safe position

        vm.expectRevert();
        vm.prank(bob);
        compoundAdapter.liquidate(alice, address(usdc), 50e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Integration_MultipleAdapters() public {
        // Alice uses sLUX adapter
        vm.startPrank(alice);
        lux.approve(address(sluxAdapter), 100e18);
        uint256 sLux = sluxAdapter.wrap(100e18, alice);
        assertGt(sLux, 0);
        vm.stopPrank();

        // Bob uses Yearn adapter
        vm.startPrank(bob);
        weth.approve(address(yearnAdapter), 10e18);
        uint256 yvShares = yearnAdapter.wrap(10e18, bob);
        assertGt(yvShares, 0);
        vm.stopPrank();

        // Alice uses GMX adapter
        vm.startPrank(alice);
        weth.approve(address(gmxAdapter), 5e18);
        uint256 glp = gmxAdapter.deposit(address(weth), 5e18, 0);
        assertGt(glp, 0);
        vm.stopPrank();

        // Bob uses Compound adapter
        vm.startPrank(bob);
        usdc.approve(address(compoundAdapter), 1000e6);
        compoundAdapter.supply(address(usdc), 1000e6);
        uint256 supplied = compoundAdapter.getSupplyBalance(bob, address(usdc));
        assertEq(supplied, 1000e6);
        vm.stopPrank();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MOCK CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MocksLUX is ERC20 {
    IERC20 public immutable lux;
    uint256 public totalStaked;

    constructor(address _lux) ERC20("Mock sLUX", "msLUX") {
        lux = IERC20(_lux);
    }

    function exchangeRate() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalStaked * 1e18) / supply;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return (assets * supply) / totalStaked;
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return (shares * totalStaked) / supply;
    }

    function stake(uint256 amount) external returns (uint256) {
        lux.transferFrom(msg.sender, address(this), amount);
        uint256 shares = previewDeposit(amount);
        totalStaked += amount;
        _mint(msg.sender, shares);
        return shares;
    }

    function instantUnstake(uint256 shares) external returns (uint256) {
        uint256 assets = previewRedeem(shares);
        uint256 afterPenalty = (assets * 90) / 100;
        totalStaked -= afterPenalty;
        _burn(msg.sender, shares);
        lux.transfer(msg.sender, afterPenalty);
        return afterPenalty;
    }

    function simulateRewards(uint256 amount) external {
        totalStaked += amount;
    }
}

contract MockYearnVault is ERC20 {
    IERC20 public immutable underlying;
    bool public withdrawable = true;

    constructor(address _underlying) ERC20("Mock yvToken", "yvMock") {
        underlying = IERC20(_underlying);
    }

    function pricePerShare() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (underlying.balanceOf(address(this)) * 1e18) / supply;
    }

    function deposit(uint256 amount, address recipient) external returns (uint256) {
        underlying.transferFrom(msg.sender, address(this), amount);
        uint256 shares = totalSupply() == 0 ? amount : (amount * totalSupply()) / underlying.balanceOf(address(this));
        _mint(recipient, shares);
        return shares;
    }

    function withdraw(uint256 shares, address recipient, uint256) external returns (uint256) {
        require(withdrawable, "Withdrawal blocked");
        uint256 assets = (shares * underlying.balanceOf(address(this))) / totalSupply();
        _burn(msg.sender, shares);
        underlying.transfer(recipient, assets);
        return assets;
    }

    function setWithdrawable(bool _withdrawable) external {
        withdrawable = _withdrawable;
    }
}

contract MockGLPManager {
    IERC20 public glp;
    IERC20 public token;
    address public rewardRouter;

    constructor(address _glp, address _token) {
        glp = IERC20(_glp);
        token = IERC20(_token);
    }

    function setRewardRouter(address _rewardRouter) external {
        rewardRouter = _rewardRouter;
        // Allow reward router to pull tokens from this contract for withdrawals
        IERC20(token).approve(_rewardRouter, type(uint256).max);
    }

    // Called by RewardRouter to pull tokens using the approval given to this contract
    function pullTokens(address _token, address from, uint256 amount) external {
        require(msg.sender == rewardRouter, "Only reward router");
        IERC20(_token).transferFrom(from, address(this), amount);
    }
}

contract MockFeeTracker is ERC20 {
    IERC20 public weth;
    mapping(address => uint256) public rewards;
    uint256 public totalClaimable;

    constructor(address _weth) ERC20("Fee Tracker", "FEE") {
        weth = IERC20(_weth);
    }

    function claimable(address account) external view returns (uint256) {
        // Return proportional share based on balance
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        return (totalClaimable * balanceOf(account)) / supply;
    }

    function claim(address receiver) external returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        uint256 amount = (totalClaimable * balanceOf(msg.sender)) / supply;
        if (amount > 0) {
            totalClaimable -= amount;
            weth.transfer(receiver, amount);
        }
        return amount;
    }

    // Called by reward router on behalf of an account
    function claimFor(address account) external returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        uint256 amount = (totalClaimable * balanceOf(account)) / supply;
        if (amount > 0) {
            totalClaimable -= amount;
            weth.transfer(account, amount);
        }
        return amount;
    }

    function addRewards(uint256 amount) external {
        // Add to total claimable pool
        totalClaimable += amount;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockRewardRouter {
    MockGLPManager public glpManager;
    MockERC20 public glp;
    MockFeeTracker public feeTracker;
    IERC20 public weth;

    constructor(address _glpManager, address _glp, address _feeTracker) {
        glpManager = MockGLPManager(_glpManager);
        glp = MockERC20(_glp);
        feeTracker = MockFeeTracker(_feeTracker);
        weth = IERC20(glpManager.token());
    }

    function mintAndStakeGlp(address token, uint256 amount, uint256, uint256) external returns (uint256) {
        // Transfer from caller using the allowance they set on glpManager
        // In reality GMX has complex routing, but mocks use glpManager approval
        glpManager.pullTokens(token, msg.sender, amount);
        uint256 glpAmount = amount; // 1:1 for simplicity
        glp.mint(msg.sender, glpAmount);
        feeTracker.mint(msg.sender, glpAmount);
        return glpAmount;
    }

    function unstakeAndRedeemGlp(address tokenOut, uint256 glpAmount, uint256, address receiver) external returns (uint256) {
        // In real GMX, staked GLP is tracked internally not via transfers
        // The adapter holds the GLP tokens; burn them on unstake
        glp.burn(msg.sender, glpAmount);
        // Transfer the underlying token from GLPManager to receiver
        IERC20(tokenOut).transferFrom(address(glpManager), receiver, glpAmount);
        return glpAmount;
    }

    function handleRewards(bool, bool, bool, bool, bool, bool, bool) external {
        // In real GMX, handleRewards claims for the caller and transfers to them
        // Our mock needs to claim on behalf of the caller (adapter)
        feeTracker.claimFor(msg.sender);
    }
}

contract MockGMXContracts {
    MockERC20 public glp;
    MockGLPManager public glpManager;
    MockFeeTracker public feeTracker;
    MockRewardRouter public rewardRouter;

    constructor(address weth) {
        glp = new MockERC20("GLP", "GLP", 18);
        glpManager = new MockGLPManager(address(glp), weth);
        feeTracker = new MockFeeTracker(weth);
        rewardRouter = new MockRewardRouter(address(glpManager), address(glp), address(feeTracker));
        // Set the reward router on glp manager so it can pull tokens
        glpManager.setRewardRouter(address(rewardRouter));
    }
}

contract MockPriceOracle {
    function getPrice(address) external pure returns (uint256) {
        return 1e18; // 1:1 for simplicity
    }
}
