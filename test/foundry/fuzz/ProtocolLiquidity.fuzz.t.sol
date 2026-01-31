// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {ProtocolLiquidity} from "../../../contracts/treasury/ProtocolLiquidity.sol";
import {MockERC20} from "../TestMocks.sol";

/// @title MockLiquidityPool
/// @notice Mock Uniswap-style LP token for ProtocolLiquidity testing
contract MockLiquidityPool is MockERC20 {
    address public token0;
    address public token1;
    uint112 public reserve0;
    uint112 public reserve1;

    constructor(
        address _token0,
        address _token1
    ) MockERC20("LP Token", "LP", 18) {
        token0 = _token0;
        token1 = _token1;
        reserve0 = 1_000_000e18;
        reserve1 = 1_000_000e18;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }
}

/// @title MockPriceOracle
/// @notice Mock oracle for ProtocolLiquidity testing
contract MockPriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token] == 0 ? 1e18 : prices[token];
    }
}

/// @title MockMintableProtocolToken
/// @notice Protocol token with mint capability
contract MockMintableProtocolToken is MockERC20 {
    constructor() MockERC20("ASHA", "ASHA", 18) {}
}

/// @title ProtocolLiquidityFuzzTest
/// @notice Fuzz tests for ProtocolLiquidity.sol - POL building and bonding
contract ProtocolLiquidityFuzzTest is Test {
    ProtocolLiquidity public pol;
    MockMintableProtocolToken public protocolToken;
    MockERC20 public token0;
    MockERC20 public token1;
    MockLiquidityPool public lpToken;
    MockPriceOracle public oracle;

    address public owner;
    address public treasury;
    address public alice;
    address public bob;

    uint256 constant BPS = 10000;
    uint256 constant MAX_DISCOUNT = 3000;

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy tokens
        protocolToken = new MockMintableProtocolToken();
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        lpToken = new MockLiquidityPool(address(token0), address(token1));

        // Deploy oracle
        oracle = new MockPriceOracle();
        oracle.setPrice(address(token0), 1e18);      // $1
        oracle.setPrice(address(token1), 1e18);      // $1
        oracle.setPrice(address(protocolToken), 1e18); // $1

        // Deploy ProtocolLiquidity
        pol = new ProtocolLiquidity(
            address(protocolToken),
            treasury,
            address(oracle),
            owner
        );

        // Mint LP tokens to mock pool total supply
        lpToken.mint(address(lpToken), 1_000_000e18);
    }

    // =========================================================================
    // HELPER FUNCTIONS
    // =========================================================================

    function _addPool(
        uint256 discount,
        uint256 vestingPeriod,
        uint256 maxCapacity
    ) internal returns (uint256 poolId) {
        vm.prank(owner);
        poolId = pol.addPool(
            address(lpToken),
            discount,
            vestingPeriod,
            maxCapacity
        );
    }

    function _addSingleSided(
        address token,
        uint256 discount,
        uint256 vestingPeriod,
        uint256 maxCapacity
    ) internal returns (uint256 configId) {
        vm.prank(owner);
        configId = pol.addSingleSided(
            token,
            discount,
            vestingPeriod,
            maxCapacity,
            address(lpToken)
        );
    }

    // =========================================================================
    // BOND LP FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test LP bonding with various amounts
    function testFuzz_BondLP_ValidAmounts(uint256 lpAmount, uint256 discount) public {
        lpAmount = bound(lpAmount, 1e15, 100_000e18);  // 0.001 to 100k LP
        discount = bound(discount, 0, MAX_DISCOUNT);

        uint256 poolId = _addPool(discount, 30 days, type(uint256).max);

        // Fund alice with LP tokens
        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        uint256 positionId = pol.bondLP(poolId, lpAmount);

        // Verify position created
        (
            uint256 totalOwed,
            uint256 claimed,
            uint256 vestingStart,
            uint256 vestingEnd
        ) = pol.positions(alice, positionId);

        assertGt(totalOwed, 0);
        assertEq(claimed, 0);
        assertEq(vestingStart, block.timestamp);
        assertEq(vestingEnd, block.timestamp + 30 days);

        // Verify LP transferred to treasury
        assertEq(lpToken.balanceOf(treasury), lpAmount);
    }

    /// @notice Fuzz test ASHA owed calculation with discount
    function testFuzz_BondLP_ASHAOwedCalculation(uint256 lpAmount, uint256 discount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);
        discount = bound(discount, 0, MAX_DISCOUNT);

        uint256 poolId = _addPool(discount, 30 days, type(uint256).max);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);

        // LP value = (reserve0 + reserve1) * lpAmount / totalSupply
        // With equal reserves of 1M each and 1M totalSupply:
        // lpValue = 2M * lpAmount / 1M = 2 * lpAmount (in sats)
        // ashaOwed = lpValue * (BPS + discount) / ashaPrice
        uint256 lpValue = 2 * lpAmount;  // simplified for equal reserves
        uint256 expected = (lpValue * (BPS + discount)) / 1e18;  // ashaPrice = 1e18

        // Allow 1% tolerance due to rounding
        assertApproxEqRel(totalOwed, expected, 0.01e18);
    }

    /// @notice Fuzz test LP bonding fails when exceeds capacity
    function testFuzz_BondLP_ExceedsCapacityFails(uint256 capacity, uint256 excess) public {
        capacity = bound(capacity, 100e18, 10_000e18);
        excess = bound(excess, 1, capacity);
        uint256 lpAmount = capacity + excess;

        uint256 poolId = _addPool(1000, 30 days, capacity);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.expectRevert(ProtocolLiquidity.ExceedsCapacity.selector);
        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);
    }

    /// @notice Fuzz test LP bonding fails on inactive pool
    function testFuzz_BondLP_InactivePoolFails(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);

        uint256 poolId = _addPool(1000, 30 days, type(uint256).max);

        // Deactivate pool
        vm.prank(owner);
        pol.setPoolActive(poolId, false);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.expectRevert(ProtocolLiquidity.PoolNotActive.selector);
        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);
    }

    // =========================================================================
    // DEPOSIT SINGLE SIDED FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test single-sided deposit with various amounts
    function testFuzz_DepositSingleSided_ValidAmounts(uint256 amount, uint256 discount) public {
        amount = bound(amount, 1e15, 100_000e18);
        discount = bound(discount, 0, MAX_DISCOUNT);

        uint256 configId = _addSingleSided(
            address(token0),
            discount,
            30 days,
            type(uint256).max
        );

        token0.mint(alice, amount);
        vm.prank(alice);
        token0.approve(address(pol), amount);

        vm.prank(alice);
        uint256 positionId = pol.depositSingleSided(configId, amount);

        // Verify position created
        (uint256 totalOwed, , , ) = pol.positions(alice, positionId);
        assertGt(totalOwed, 0);

        // Verify token transferred to treasury
        assertEq(token0.balanceOf(treasury), amount);
    }

    /// @notice Fuzz test single-sided ASHA calculation
    /// @dev value = (amount * tokenPrice) / 1e18, ashaOwed = (value * (BPS + discount)) / ashaPrice
    function testFuzz_DepositSingleSided_ASHACalculation(uint256 amount, uint256 discount) public {
        amount = bound(amount, 1e18, 10_000e18);
        discount = bound(discount, 0, MAX_DISCOUNT);

        uint256 configId = _addSingleSided(
            address(token0),
            discount,
            30 days,
            type(uint256).max
        );

        token0.mint(alice, amount);
        vm.prank(alice);
        token0.approve(address(pol), amount);

        vm.prank(alice);
        pol.depositSingleSided(configId, amount);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);

        // Contract calculation:
        // value = (amount * tokenPrice) / 1e18 = (amount * 1e18) / 1e18 = amount
        // ashaOwed = (value * (BPS + discount)) / ashaPrice = (amount * (BPS + discount)) / 1e18
        uint256 expected = (amount * (BPS + discount)) / 1e18;

        assertEq(totalOwed, expected);
    }

    /// @notice Fuzz test single-sided deposit fails when exceeds capacity
    function testFuzz_DepositSingleSided_ExceedsCapacityFails(uint256 capacity, uint256 excess) public {
        capacity = bound(capacity, 100e18, 10_000e18);
        excess = bound(excess, 1, capacity);
        uint256 amount = capacity + excess;

        uint256 configId = _addSingleSided(address(token0), 500, 30 days, capacity);

        token0.mint(alice, amount);
        vm.prank(alice);
        token0.approve(address(pol), amount);

        vm.expectRevert(ProtocolLiquidity.ExceedsCapacity.selector);
        vm.prank(alice);
        pol.depositSingleSided(configId, amount);
    }

    // =========================================================================
    // CLAIM FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test vesting progression
    function testFuzz_Claim_VestingProgression(uint256 lpAmount, uint256 timeElapsed) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);
        uint256 vestingPeriod = 30 days;
        timeElapsed = bound(timeElapsed, 0, vestingPeriod * 2);

        uint256 poolId = _addPool(1000, vestingPeriod, type(uint256).max);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        uint256 positionId = pol.bondLP(poolId, lpAmount);

        (uint256 totalOwed, , , ) = pol.positions(alice, positionId);

        // Fast forward
        skip(timeElapsed);

        // Calculate expected claimable
        uint256 expectedClaimable;
        if (timeElapsed >= vestingPeriod) {
            expectedClaimable = totalOwed;
        } else {
            expectedClaimable = (totalOwed * timeElapsed) / vestingPeriod;
        }

        uint256 actualClaimable = pol.claimable(alice, positionId);
        assertEq(actualClaimable, expectedClaimable);
    }

    /// @notice Fuzz test claiming at various times
    function testFuzz_Claim_AtVestingMilestones(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 10e18, 1_000e18);
        uint256 vestingPeriod = 30 days;

        uint256 poolId = _addPool(1500, vestingPeriod, type(uint256).max);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        uint256 positionId = pol.bondLP(poolId, lpAmount);

        (uint256 totalOwed, , , ) = pol.positions(alice, positionId);

        // At 0% - nothing to claim
        assertEq(pol.claimable(alice, positionId), 0);

        // At 50%
        skip(vestingPeriod / 2);
        uint256 expected50 = totalOwed / 2;
        uint256 actual50 = pol.claimable(alice, positionId);
        assertApproxEqAbs(actual50, expected50, 1);  // allow 1 wei rounding

        // At 100%
        skip(vestingPeriod / 2);
        uint256 expected100 = totalOwed;
        uint256 actual100 = pol.claimable(alice, positionId);
        assertEq(actual100, expected100);

        // At 150% (fully vested, no extra)
        skip(vestingPeriod / 2);
        assertEq(pol.claimable(alice, positionId), totalOwed);
    }

    /// @notice Fuzz test claim all positions
    function testFuzz_ClaimAll_MultiplePositions(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, 1_000e18);
        amount2 = bound(amount2, 1e18, 1_000e18);

        uint256 poolId = _addPool(1000, 30 days, type(uint256).max);

        // First position
        lpToken.mint(alice, amount1);
        vm.prank(alice);
        lpToken.approve(address(pol), amount1);
        vm.prank(alice);
        pol.bondLP(poolId, amount1);

        // Second position
        lpToken.mint(alice, amount2);
        vm.prank(alice);
        lpToken.approve(address(pol), amount2);
        vm.prank(alice);
        pol.bondLP(poolId, amount2);

        // Fast forward to full vesting
        skip(30 days);

        uint256 totalClaimable = pol.totalClaimable(alice);
        assertGt(totalClaimable, 0);

        // Claim all
        vm.prank(alice);
        pol.claimAll();

        // Nothing left
        assertEq(pol.totalClaimable(alice), 0);
    }

    // =========================================================================
    // ADMIN FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test discount update bounded by MAX_DISCOUNT
    function testFuzz_SetPoolDiscount_BoundedByMax(uint256 discount) public {
        uint256 poolId = _addPool(1000, 30 days, type(uint256).max);

        if (discount > MAX_DISCOUNT) {
            vm.expectRevert(ProtocolLiquidity.InvalidDiscount.selector);
            vm.prank(owner);
            pol.setPoolDiscount(poolId, discount);
        } else {
            vm.prank(owner);
            pol.setPoolDiscount(poolId, discount);

            (,,, uint256 actualDiscount,,,,) = pol.pools(poolId);
            assertEq(actualDiscount, discount);
        }
    }

    /// @notice Fuzz test capacity update
    function testFuzz_SetPoolCapacity(uint256 newCapacity) public {
        uint256 poolId = _addPool(1000, 30 days, 1_000_000e18);

        vm.prank(owner);
        pol.setPoolCapacity(poolId, newCapacity);

        (,,,,, uint256 actualCapacity,,) = pol.pools(poolId);
        assertEq(actualCapacity, newCapacity);
    }

    // =========================================================================
    // INVARIANT TESTS
    // =========================================================================

    /// @notice Invariant: total POL value tracked correctly
    function testFuzz_Invariant_TotalPOLValueTracked(uint256 lpAmount1, uint256 lpAmount2) public {
        lpAmount1 = bound(lpAmount1, 1e18, 100_000e18);
        lpAmount2 = bound(lpAmount2, 1e18, 100_000e18);

        uint256 poolId = _addPool(1500, 30 days, type(uint256).max);

        // First bond
        lpToken.mint(alice, lpAmount1);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount1);
        vm.prank(alice);
        pol.bondLP(poolId, lpAmount1);

        uint256 polAfter1 = pol.totalPOLValue();
        assertGt(polAfter1, 0);

        // Second bond
        lpToken.mint(bob, lpAmount2);
        vm.prank(bob);
        lpToken.approve(address(pol), lpAmount2);
        vm.prank(bob);
        pol.bondLP(poolId, lpAmount2);

        uint256 polAfter2 = pol.totalPOLValue();
        assertGt(polAfter2, polAfter1);
    }

    /// @notice Invariant: total ASHA bonded tracked correctly
    function testFuzz_Invariant_TotalASHABondedTracked(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);

        uint256 poolId = _addPool(1000, 30 days, type(uint256).max);

        uint256 ashaBefore = pol.totalASHABonded();
        assertEq(ashaBefore, 0);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);
        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);

        uint256 ashaAfter = pol.totalASHABonded();
        assertGt(ashaAfter, ashaBefore);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);
        assertEq(ashaAfter, totalOwed);
    }

    /// @notice Invariant: pool total deposited never exceeds capacity
    function testFuzz_Invariant_PoolDepositedNeverExceedsCapacity(
        uint256 capacity,
        uint256 amount1,
        uint256 amount2
    ) public {
        capacity = bound(capacity, 1_000e18, 100_000e18);
        amount1 = bound(amount1, 1e18, capacity);
        amount2 = bound(amount2, 1e18, capacity);

        uint256 poolId = _addPool(1000, 30 days, capacity);

        // First deposit
        lpToken.mint(alice, amount1);
        vm.prank(alice);
        lpToken.approve(address(pol), amount1);
        vm.prank(alice);
        pol.bondLP(poolId, amount1);

        // Second deposit (may fail)
        if (amount1 + amount2 > capacity) {
            lpToken.mint(bob, amount2);
            vm.prank(bob);
            lpToken.approve(address(pol), amount2);

            vm.expectRevert(ProtocolLiquidity.ExceedsCapacity.selector);
            vm.prank(bob);
            pol.bondLP(poolId, amount2);
        }

        // Check invariant
        (,,,,,, uint256 totalDeposited,) = pol.pools(poolId);
        assertLe(totalDeposited, capacity);
    }

    // =========================================================================
    // EDGE CASE TESTS
    // =========================================================================

    /// @notice Test with zero discount
    function testFuzz_BondLP_ZeroDiscount(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);

        uint256 poolId = _addPool(0, 30 days, type(uint256).max);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);
        assertGt(totalOwed, 0);  // Should still get tokens, just at market rate
    }

    /// @notice Test with maximum allowed discount
    function testFuzz_BondLP_MaxDiscount(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);

        uint256 poolId = _addPool(MAX_DISCOUNT, 30 days, type(uint256).max);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);

        // With 30% discount, should get 130% of base
        // Verify it's more than with zero discount
        uint256 poolId2 = _addPool(0, 30 days, type(uint256).max);
        lpToken.mint(bob, lpAmount);
        vm.prank(bob);
        lpToken.approve(address(pol), lpAmount);
        vm.prank(bob);
        pol.bondLP(poolId2, lpAmount);

        (uint256 bobOwed, , , ) = pol.positions(bob, 0);

        assertGt(totalOwed, bobOwed);
    }

    /// @notice Test very short vesting period
    function testFuzz_BondLP_ShortVesting(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);

        uint256 poolId = _addPool(1000, 1, type(uint256).max);  // 1 second vesting

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);

        // Skip 1 second
        skip(1);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);
        assertEq(pol.claimable(alice, 0), totalOwed);
    }

    /// @notice Test very long vesting period
    function testFuzz_BondLP_LongVesting(uint256 lpAmount) public {
        lpAmount = bound(lpAmount, 1e18, 10_000e18);
        uint256 longVesting = 365 days;

        uint256 poolId = _addPool(1000, longVesting, type(uint256).max);

        lpToken.mint(alice, lpAmount);
        vm.prank(alice);
        lpToken.approve(address(pol), lpAmount);

        vm.prank(alice);
        pol.bondLP(poolId, lpAmount);

        // After half the vesting period
        skip(longVesting / 2);

        (uint256 totalOwed, , , ) = pol.positions(alice, 0);
        uint256 claimable = pol.claimable(alice, 0);

        assertApproxEqRel(claimable, totalOwed / 2, 0.001e18);  // within 0.1%
    }
}
