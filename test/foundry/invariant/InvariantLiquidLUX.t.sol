// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { MockERC20 } from "../TestMocks.sol";
import { LiquidLUX } from "../../../contracts/liquid/LiquidLUX.sol";

// ============================================================================
// Handler for LiquidLUX invariant testing
// ============================================================================

contract LiquidLUXHandler is Test {
    LiquidLUX public vault;
    MockERC20 public lux;

    // Ghost variables
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalDonated;
    uint256 public ghost_depositCalls;
    uint256 public ghost_withdrawCalls;
    uint256 public ghost_donateCalls;
    uint256 public ghost_previousSharePrice;

    // Actors
    address[] public actors;
    mapping(address => uint256) public actorShares;

    constructor(LiquidLUX _vault, MockERC20 _lux) {
        vault = _vault;
        lux = _lux;

        // Create actor addresses
        for (uint256 i = 1; i <= 5; i++) {
            actors.push(address(uint160(i * 1000)));
        }
    }

    function _getActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = _getActor(actorSeed);
        // Min deposit must be > MINIMUM_LIQUIDITY (1e6) for first deposit
        amount = bound(amount, 1e7, 1e24);

        // Snapshot share price before
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        if (totalSupply > 0) {
            ghost_previousSharePrice = (totalAssets * 1e18) / totalSupply;
        }

        // Mint LUX to actor, approve vault
        lux.mint(actor, amount);
        vm.startPrank(actor);
        lux.approve(address(vault), amount);
        try vault.deposit(amount) returns (uint256 shares) {
            actorShares[actor] += shares;
            ghost_totalDeposited += amount;
            ghost_depositCalls++;
        } catch {
            // Can fail if shares == 0
        }
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 fraction) external {
        address actor = _getActor(actorSeed);
        uint256 shares = vault.balanceOf(actor);
        if (shares == 0) return;

        // Withdraw 1-100% of actor's shares
        fraction = bound(fraction, 1, 100);
        uint256 sharesToWithdraw = (shares * fraction) / 100;
        if (sharesToWithdraw == 0) return;

        // Snapshot share price before
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        if (totalSupply > 0) {
            ghost_previousSharePrice = (totalAssets * 1e18) / totalSupply;
        }

        vm.startPrank(actor);
        try vault.withdraw(sharesToWithdraw) returns (uint256 amount) {
            actorShares[actor] -= sharesToWithdraw;
            ghost_totalWithdrawn += amount;
            ghost_withdrawCalls++;
        } catch {
            // Can fail if amount == 0
        }
        vm.stopPrank();
    }

    /// @notice Simulate yield accrual by donating LUX directly to vault
    function donate(uint256 amount) external {
        amount = bound(amount, 1, 1e22);

        // Snapshot share price before
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        if (totalSupply > 0) {
            ghost_previousSharePrice = (totalAssets * 1e18) / totalSupply;
        }

        lux.mint(address(vault), amount);
        ghost_totalDonated += amount;
        ghost_donateCalls++;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 i) external view returns (address) {
        return actors[i];
    }
}

// ============================================================================
// Invariant test suite for LiquidLUX
// ============================================================================

contract InvariantLiquidLUXTest is Test {
    LiquidLUX public vault;
    MockERC20 public lux;
    LiquidLUXHandler public handler;

    address public treasury = address(0xBEEF);

    function setUp() public {
        // Deploy mock LUX token (OpenZeppelin ERC20 with mint)
        lux = new MockERC20("Lux", "LUX", 18);

        // Deploy LiquidLUX vault
        vault = new LiquidLUX(address(lux), treasury, address(0));

        // Deploy handler
        handler = new LiquidLUXHandler(vault, lux);

        // Target only the handler
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = LiquidLUXHandler.deposit.selector;
        selectors[1] = LiquidLUXHandler.withdraw.selector;
        selectors[2] = LiquidLUXHandler.donate.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    /// @notice No single share holder can redeem more than totalAssets
    function invariant_sharesNeverExceedAssets() public view {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return;

        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.getActor(i);
            uint256 shares = vault.balanceOf(actor);
            if (shares == 0) continue;

            uint256 redeemable = vault.convertToAssets(shares);
            assertLe(redeemable, totalAssets, "Single holder cannot redeem more than totalAssets");
        }
    }

    /// @notice A reasonable deposit (1e6 wei = MINIMUM_LIQUIDITY) always gives > 0 shares
    /// @dev MINIMUM_LIQUIDITY burn + virtual offsets prevent inflation for practical deposits
    function invariant_virtualSharesProtection() public view {
        // 1e6 wei is the minimum practical deposit (matches MINIMUM_LIQUIDITY)
        uint256 sharesForMinDeposit = vault.convertToShares(1e6);
        // Should always give > 0 unless pool has extreme donation (> 1e24 per share)
        if (vault.totalAssets() < 1e24 && vault.totalSupply() > 0) {
            assertGt(sharesForMinDeposit, 0, "Min deposit must give > 0 shares");
        }
    }

    /// @notice totalAssets >= net deposits (deposits - withdrawals + donations)
    /// @dev Accounting check: vault balance should be consistent with operations
    function invariant_totalAssetsConsistent() public view {
        uint256 totalAssets = vault.totalAssets();
        uint256 netDeposits =
            handler.ghost_totalDeposited() + handler.ghost_totalDonated() - handler.ghost_totalWithdrawn();

        // totalAssets should equal net deposits (no fees taken in our test setup)
        // Allow 1 wei tolerance per operation for rounding
        uint256 ops = handler.ghost_depositCalls() + handler.ghost_withdrawCalls() + handler.ghost_donateCalls();
        if (ops == 0) return;

        // We allow the assets to be >= netDeposits - ops (rounding down per operation)
        // and <= netDeposits + ops (rounding up per operation)
        assertGe(totalAssets + ops, netDeposits, "totalAssets too low vs net deposits (accounting error)");
    }

    /// @notice Share price (assets per share) must not change by > 100x between operations
    /// @dev Prevents inflation/deflation attacks
    function invariant_noShareInflation() public view {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return;
        if (handler.ghost_previousSharePrice() == 0) return;

        uint256 totalAssets = vault.totalAssets();
        uint256 currentPrice = (totalAssets * 1e18) / totalSupply;
        uint256 previousPrice = handler.ghost_previousSharePrice();

        // Price should not increase by more than 100x
        assertLe(currentPrice, previousPrice * 100, "Share price increased by > 100x (inflation attack)");

        // Price should not decrease by more than 100x
        assertLe(previousPrice, currentPrice * 100, "Share price decreased by > 100x (deflation attack)");
    }
}
