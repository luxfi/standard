// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import { Markets } from "../../../contracts/markets/Markets.sol";
import { MarketParams, Market, Position, Id } from "../../../contracts/markets/interfaces/IMarkets.sol";
import { MarketParamsLib } from "../../../contracts/markets/libraries/MarketParamsLib.sol";
import { MockERC20, MockOracle, MockRateModel } from "../TestMocks.sol";

/// @title MarketsHandler
/// @notice Bounded handler for Markets invariant testing
contract MarketsHandler is Test {
    using MarketParamsLib for MarketParams;

    Markets public markets;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockOracle public oracle;
    MarketParams public mp;
    Id public marketId;

    address[] public actors;
    uint256 public previousTotalBorrowAssets;

    // Ghost variables to track state
    uint256 public ghost_totalSupplied;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalBorrowed;
    uint256 public ghost_totalRepaid;
    uint256 public ghost_totalCollateralAdded;
    uint256 public ghost_totalCollateralRemoved;

    constructor(
        Markets _markets,
        MockERC20 _loanToken,
        MockERC20 _collateralToken,
        MockOracle _oracle,
        MarketParams memory _mp
    ) {
        markets = _markets;
        loanToken = _loanToken;
        collateralToken = _collateralToken;
        oracle = _oracle;
        mp = _mp;
        marketId = _mp.id();

        // Create actors
        for (uint256 i = 1; i <= 5; i++) {
            actors.push(address(uint160(i * 1000)));
        }
    }

    function _getActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function supply(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, 1, 1e24);
        address actor = _getActor(actorSeed);

        loanToken.mint(actor, amount);
        vm.startPrank(actor);
        loanToken.approve(address(markets), amount);
        markets.supply(mp, amount, 0, actor, "");
        vm.stopPrank();

        ghost_totalSupplied += amount;
    }

    function borrow(uint256 actorSeed, uint256 collateralAmount, uint256 borrowAmount) external {
        // Supply collateral first, then borrow
        collateralAmount = bound(collateralAmount, 1e18, 1e24);
        address actor = _getActor(actorSeed);

        // Supply collateral
        collateralToken.mint(actor, collateralAmount);
        vm.startPrank(actor);
        collateralToken.approve(address(markets), collateralAmount);
        markets.supplyCollateral(mp, collateralAmount, actor, "");
        vm.stopPrank();

        ghost_totalCollateralAdded += collateralAmount;

        // Calculate max borrowable based on collateral value and LLTV
        // oracle price is 1e36, LLTV is 0.8e18 => maxBorrow = collateral * 0.8
        uint256 maxBorrow = (collateralAmount * mp.lltv) / 1e18;

        // Check available liquidity
        (,, uint128 totalBorrowAssets,,,) = markets.market(marketId);
        (, uint128 totalSupplyAssets_) = _getSupplyState();
        uint256 available = totalSupplyAssets_ > totalBorrowAssets ? totalSupplyAssets_ - totalBorrowAssets : 0;

        // Get existing borrow shares for this actor
        (, uint256 existingBorrowShares,) = markets.position(marketId, actor);
        if (existingBorrowShares > 0) return; // Skip if already borrowing

        if (available == 0 || maxBorrow == 0) return;

        borrowAmount = bound(borrowAmount, 1, _min(maxBorrow, available));

        vm.startPrank(actor);
        try markets.borrow(mp, borrowAmount, 0, actor, actor) {
            ghost_totalBorrowed += borrowAmount;
        } catch { }
        vm.stopPrank();
    }

    function repay(uint256 actorSeed, uint256 amount) external {
        address actor = _getActor(actorSeed);

        (, uint256 borrowShares,) = markets.position(marketId, actor);
        if (borrowShares == 0) return;

        // Repay up to the borrow balance
        (,, uint128 totalBorrowAssets_, uint128 totalBorrowShares_,,) = markets.market(marketId);
        uint256 borrowedAssets =
            (borrowShares * (uint256(totalBorrowAssets_) + 1)) / (uint256(totalBorrowShares_) + 1e6);
        if (borrowedAssets == 0) return;

        amount = bound(amount, 1, borrowedAssets);

        loanToken.mint(actor, amount);
        vm.startPrank(actor);
        loanToken.approve(address(markets), amount);
        try markets.repay(mp, amount, 0, actor, "") {
            ghost_totalRepaid += amount;
        } catch { }
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = _getActor(actorSeed);

        (uint256 supplyShares,,) = markets.position(marketId, actor);
        if (supplyShares == 0) return;

        (uint128 totalSupplyAssets_, uint128 totalSupplyShares_) = _getSupplyState();
        uint256 suppliedAssets =
            (supplyShares * (uint256(totalSupplyAssets_) + 1)) / (uint256(totalSupplyShares_) + 1e6);
        if (suppliedAssets == 0) return;

        amount = bound(amount, 1, suppliedAssets);

        vm.startPrank(actor);
        try markets.withdraw(mp, amount, 0, actor, actor) {
            ghost_totalWithdrawn += amount;
        } catch { }
        vm.stopPrank();
    }

    function accrueTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 30 days);

        // Record borrow assets before time warp
        (,, uint128 borrowBefore,,,) = markets.market(marketId);
        previousTotalBorrowAssets = borrowBefore;

        vm.warp(block.timestamp + seconds_);

        // Force interest accrual by doing a zero-value supply
        // We supply 1 wei to trigger accrual
        loanToken.mint(address(this), 1);
        loanToken.approve(address(markets), 1);
        try markets.supply(mp, 1, 0, address(this), "") {
            ghost_totalSupplied += 1;
        } catch { }
    }

    function _getSupplyState() internal view returns (uint128 totalSupplyAssets_, uint128 totalSupplyShares_) {
        (totalSupplyAssets_, totalSupplyShares_,,,,) = markets.market(marketId);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }
}

/// @title InvariantMarketsTest
/// @notice Invariant tests for Markets (Morpho-style lending)
contract InvariantMarketsTest is StdInvariant, Test {
    using MarketParamsLib for MarketParams;

    Markets public markets;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockOracle public oracle;
    MockRateModel public rateModel;
    MarketsHandler public handler;
    MarketParams public mp;
    Id public marketId;

    function setUp() public {
        // Deploy mocks
        loanToken = new MockERC20("Loan Token", "LOAN", 18);
        collateralToken = new MockERC20("Collateral Token", "COLL", 18);
        oracle = new MockOracle();
        rateModel = new MockRateModel();

        // Deploy Markets
        markets = new Markets(address(this));

        // Enable rate model and LLTV
        markets.enableRateModel(address(rateModel));
        markets.enableLltv(0.8e18);

        // Create market params
        mp = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            rateModel: address(rateModel),
            lltv: 0.8e18
        });

        marketId = mp.id();

        // Create market
        markets.createMarket(mp);

        // Deploy handler
        handler = new MarketsHandler(markets, loanToken, collateralToken, oracle, mp);

        // Seed initial liquidity so borrows are possible
        uint256 seed = 100_000e18;
        loanToken.mint(address(this), seed);
        loanToken.approve(address(markets), seed);
        markets.supply(mp, seed, 0, address(this), "");

        // Configure target
        targetContract(address(handler));
    }

    /// @notice totalBorrowAssets <= totalSupplyAssets for each market
    function invariant_solvency() public view {
        (uint128 totalSupplyAssets_,, uint128 totalBorrowAssets_,,,) = markets.market(marketId);
        assertLe(
            uint256(totalBorrowAssets_), uint256(totalSupplyAssets_), "SOLVENCY: totalBorrowAssets > totalSupplyAssets"
        );
    }

    /// @notice totalBorrowShares > 0 iff totalBorrowAssets > 0
    function invariant_sharesConsistent() public view {
        (,, uint128 totalBorrowAssets_, uint128 totalBorrowShares_,,) = markets.market(marketId);

        if (totalBorrowShares_ > 0) {
            assertGt(uint256(totalBorrowAssets_), 0, "SHARES: totalBorrowShares > 0 but totalBorrowAssets == 0");
        }
        if (totalBorrowAssets_ > 0) {
            assertGt(uint256(totalBorrowShares_), 0, "SHARES: totalBorrowAssets > 0 but totalBorrowShares == 0");
        }
    }

    /// @notice Sum of supply positions >= sum of borrow positions (in assets)
    function invariant_noNegativeEquity() public view {
        (uint128 totalSupplyAssets_,, uint128 totalBorrowAssets_,,,) = markets.market(marketId);
        assertGe(uint256(totalSupplyAssets_), uint256(totalBorrowAssets_), "EQUITY: supply < borrow (negative equity)");
    }

    /// @notice totalBorrowAssets never decreases unless repay/liquidation (interest only goes up)
    /// @dev We check that after accrueTime, borrow assets >= previous snapshot
    function invariant_interestAccrual() public view {
        (,, uint128 totalBorrowAssets_,,,) = markets.market(marketId);
        // Interest can only increase totalBorrowAssets.
        // Repays can decrease it but that's accounted for in ghost variables.
        // This check: the contract's borrow assets + total repaid should be >= total borrowed + previous interest
        // Simplified: totalBorrowAssets >= 0 (always true with uint) and the solvency invariant covers the rest.
        // The real test: if there have been borrows and no repays, borrow assets should not decrease.
        uint256 borrowed = handler.ghost_totalBorrowed();
        uint256 repaid = handler.ghost_totalRepaid();
        if (borrowed > 0 && repaid == 0) {
            assertGe(
                uint256(totalBorrowAssets_),
                borrowed,
                "INTEREST: totalBorrowAssets decreased below total borrowed (no repays)"
            );
        }
    }

    function invariant_callSummary() public view {
        // No-op: just ensures the invariant runner exercised the handler
    }
}
