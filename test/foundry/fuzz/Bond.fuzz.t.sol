// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {Bond} from "../../../contracts/treasury/Bond.sol";
import {MockERC20} from "../TestMocks.sol";

/// @title MockMintableToken
/// @notice ERC20 with mint capability for Bond testing
contract MockMintableToken is MockERC20 {
    constructor() MockERC20("Identity Token", "IDENT", 18) {}
}

/// @title BondFuzzTest
/// @notice Fuzz tests for Bond.sol - DAO bond issuance and vesting
contract BondFuzzTest is Test {
    Bond public bond;
    MockERC20 public paymentToken;
    MockMintableToken public identityToken;

    address public owner;
    address public treasury;
    address public alice;
    address public bob;

    uint256 constant BPS = 10000;

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy tokens
        paymentToken = new MockERC20("USDC", "USDC", 6);
        identityToken = new MockMintableToken();

        // Deploy Bond
        bond = new Bond(address(identityToken), treasury, owner);
    }

    // =========================================================================
    // HELPER FUNCTIONS
    // =========================================================================

    function _createBond(
        uint256 targetRaise,
        uint256 tokensToMint,
        uint256 discount,
        uint256 vestingPeriod,
        uint256 minPurchase,
        uint256 maxPurchase
    ) internal returns (uint256 bondId) {
        Bond.BondConfig memory config = Bond.BondConfig({
            paymentToken: address(paymentToken),
            targetRaise: targetRaise,
            tokensToMint: tokensToMint,
            discount: discount,
            vestingPeriod: vestingPeriod,
            startTime: block.timestamp,
            endTime: block.timestamp + 30 days,
            minPurchase: minPurchase,
            maxPurchase: maxPurchase,
            active: true
        });

        vm.prank(owner);
        bondId = bond.createBond(config);
    }

    // =========================================================================
    // PURCHASE FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test purchase with various amounts within valid range
    function testFuzz_Purchase_ValidAmounts(
        uint256 targetRaise,
        uint256 tokensToMint,
        uint256 discount,
        uint256 purchaseAmount
    ) public {
        // Bound inputs to reasonable ranges
        targetRaise = bound(targetRaise, 1000e6, 10_000_000e6);  // 1k to 10M USDC
        tokensToMint = bound(tokensToMint, 1000e18, 10_000_000e18);
        discount = bound(discount, 0, 5000);  // 0-50% discount
        purchaseAmount = bound(purchaseAmount, 100e6, targetRaise);  // min 100 USDC

        uint256 bondId = _createBond(
            targetRaise,
            tokensToMint,
            discount,
            30 days,
            100e6,      // min purchase
            targetRaise // max purchase
        );

        // Fund alice
        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        // Purchase
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);

        // Verify purchase recorded
        (
            uint256 recordedBondId,
            uint256 paymentAmount,
            uint256 tokensOwed,
            uint256 tokensClaimed,
            uint256 vestingStart,
            uint256 vestingEnd
        ) = bond.purchases(bondId, alice);

        assertEq(recordedBondId, bondId);
        assertEq(paymentAmount, purchaseAmount);
        assertGt(tokensOwed, 0);
        assertEq(tokensClaimed, 0);
        assertEq(vestingStart, block.timestamp);
        assertEq(vestingEnd, block.timestamp + 30 days);

        // Verify treasury received payment
        assertEq(paymentToken.balanceOf(treasury), purchaseAmount);
    }

    /// @notice Fuzz test tokens owed calculation with discount
    function testFuzz_Purchase_TokensOwedCalculation(
        uint256 targetRaise,
        uint256 tokensToMint,
        uint256 discount,
        uint256 purchaseAmount
    ) public {
        // Bound inputs
        targetRaise = bound(targetRaise, 10_000e6, 1_000_000e6);
        tokensToMint = bound(tokensToMint, 10_000e18, 1_000_000e18);
        discount = bound(discount, 0, 3000);  // 0-30%
        purchaseAmount = bound(purchaseAmount, 1000e6, targetRaise);

        uint256 bondId = _createBond(
            targetRaise,
            tokensToMint,
            discount,
            30 days,
            1000e6,
            targetRaise
        );

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);

        (, , uint256 tokensOwed, , , ) = bond.purchases(bondId, alice);

        // Expected: (amount * tokensToMint * (10000 + discount)) / (targetRaise * 10000)
        uint256 expectedTokens = (purchaseAmount * tokensToMint * (BPS + discount)) / (targetRaise * BPS);

        assertEq(tokensOwed, expectedTokens);
    }

    /// @notice Fuzz test purchase fails below minimum
    function testFuzz_Purchase_BelowMinimumFails(uint256 minPurchase, uint256 purchaseAmount) public {
        minPurchase = bound(minPurchase, 100e6, 10_000e6);
        purchaseAmount = bound(purchaseAmount, 1, minPurchase - 1);

        uint256 bondId = _createBond(
            100_000e6,  // target raise
            100_000e18, // tokens to mint
            1000,       // 10% discount
            30 days,
            minPurchase,
            100_000e6
        );

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.expectRevert(Bond.AmountTooLow.selector);
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);
    }

    /// @notice Fuzz test purchase fails above maximum
    function testFuzz_Purchase_AboveMaximumFails(uint256 maxPurchase, uint256 excessAmount) public {
        maxPurchase = bound(maxPurchase, 1000e6, 50_000e6);
        excessAmount = bound(excessAmount, 1, 50_000e6);
        uint256 purchaseAmount = maxPurchase + excessAmount;

        uint256 bondId = _createBond(
            100_000e6,  // target raise (above maxPurchase)
            100_000e18,
            1000,
            30 days,
            100e6,
            maxPurchase
        );

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.expectRevert(Bond.AmountTooHigh.selector);
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);
    }

    /// @notice Fuzz test purchase fails when exceeds target
    function testFuzz_Purchase_ExceedsTargetFails(uint256 targetRaise, uint256 excess) public {
        targetRaise = bound(targetRaise, 10_000e6, 100_000e6);
        excess = bound(excess, 1, targetRaise);
        uint256 purchaseAmount = targetRaise + excess;

        uint256 bondId = _createBond(
            targetRaise,
            100_000e18,
            1000,
            30 days,
            100e6,
            purchaseAmount  // max >= purchaseAmount
        );

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.expectRevert(Bond.ExceedsTarget.selector);
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);
    }

    /// @notice Fuzz test duplicate purchase fails
    /// @notice Fuzz test multiple purchases allowed up to maxPurchase (H-07 fix)
    function testFuzz_Purchase_MultiplePurchasesAllowed(uint256 firstAmount, uint256 secondAmount) public {
        uint256 targetRaise = 100_000e6;
        uint256 maxPurchase = 50_000e6;
        firstAmount = bound(firstAmount, 1000e6, 20_000e6);  // Under half of max
        secondAmount = bound(secondAmount, 1000e6, 20_000e6);  // Under half of max

        uint256 bondId = _createBond(
            targetRaise,
            100_000e18,
            1000,
            30 days,
            1000e6,
            maxPurchase
        );

        // First purchase
        paymentToken.mint(alice, firstAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), firstAmount);

        vm.prank(alice);
        bond.purchase(bondId, firstAmount);

        // H-07 fix: Second purchase should succeed (up to maxPurchase total)
        paymentToken.mint(alice, secondAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), secondAmount);

        vm.prank(alice);
        bond.purchase(bondId, secondAmount);

        // Verify total purchase amount accumulated
        (
            ,
            uint256 totalPayment,
            uint256 totalTokens,
            ,
            ,
        ) = bond.purchases(bondId, alice);

        assertEq(totalPayment, firstAmount + secondAmount);
        assertGt(totalTokens, 0);
    }

    /// @notice Fuzz test multiple purchases fail when exceeding maxPurchase
    function testFuzz_Purchase_MultiplePurchasesExceedMax(uint256 firstAmount, uint256 secondAmount) public {
        uint256 targetRaise = 100_000e6;
        uint256 maxPurchase = 50_000e6;
        // First purchase uses most of the max
        firstAmount = bound(firstAmount, 30_000e6, 45_000e6);
        // Second purchase would exceed max
        secondAmount = bound(secondAmount, maxPurchase - firstAmount + 1, 50_000e6);

        uint256 bondId = _createBond(
            targetRaise,
            100_000e18,
            1000,
            30 days,
            1000e6,
            maxPurchase
        );

        // First purchase
        paymentToken.mint(alice, firstAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), firstAmount);

        vm.prank(alice);
        bond.purchase(bondId, firstAmount);

        // Second purchase should fail (exceeds maxPurchase)
        paymentToken.mint(alice, secondAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), secondAmount);

        vm.expectRevert(Bond.AmountTooHigh.selector);
        vm.prank(alice);
        bond.purchase(bondId, secondAmount);
    }

    // =========================================================================
    // CLAIM FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test claiming vested tokens over time
    function testFuzz_Claim_VestingProgression(uint256 purchaseAmount, uint256 timeElapsed) public {
        purchaseAmount = bound(purchaseAmount, 1000e6, 50_000e6);
        uint256 vestingPeriod = 30 days;
        timeElapsed = bound(timeElapsed, 0, vestingPeriod * 2);

        uint256 bondId = _createBond(
            100_000e6,
            100_000e18,
            1000,  // 10% discount
            vestingPeriod,
            1000e6,
            100_000e6
        );

        // Purchase
        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);

        (, , uint256 tokensOwed, , , ) = bond.purchases(bondId, alice);

        // Fast forward time
        skip(timeElapsed);

        // Calculate expected claimable
        uint256 expectedClaimable;
        if (timeElapsed >= vestingPeriod) {
            expectedClaimable = tokensOwed;
        } else {
            expectedClaimable = (tokensOwed * timeElapsed) / vestingPeriod;
        }

        uint256 actualClaimable = bond.claimable(bondId, alice);
        assertEq(actualClaimable, expectedClaimable);
    }

    /// @notice Fuzz test claim returns nothing before purchase
    function testFuzz_Claim_NothingBeforePurchase(uint256 bondId) public {
        // Create a bond first
        _createBond(100_000e6, 100_000e18, 1000, 30 days, 1000e6, 100_000e6);

        // Alice hasn't purchased anything
        uint256 claimable = bond.claimable(bondId, alice);
        assertEq(claimable, 0);

        // Claim should revert
        vm.expectRevert(Bond.NothingToClaim.selector);
        vm.prank(alice);
        bond.claim(bondId);
    }

    /// @notice Fuzz test multiple partial claims
    function testFuzz_Claim_MultiplePartialClaims(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 10_000e6, 50_000e6);
        uint256 vestingPeriod = 30 days;

        uint256 bondId = _createBond(
            100_000e6,
            100_000e18,
            1000,
            vestingPeriod,
            1000e6,
            100_000e6
        );

        // Purchase
        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);

        (, , uint256 tokensOwed, , , ) = bond.purchases(bondId, alice);

        uint256 totalClaimed = 0;

        // Claim at 25% vested
        skip(vestingPeriod / 4);
        uint256 claimable1 = bond.claimable(bondId, alice);
        if (claimable1 > 0) {
            vm.prank(alice);
            bond.claim(bondId);
            totalClaimed += claimable1;
        }

        // Claim at 50% vested
        skip(vestingPeriod / 4);
        uint256 claimable2 = bond.claimable(bondId, alice);
        if (claimable2 > 0) {
            vm.prank(alice);
            bond.claim(bondId);
            totalClaimed += claimable2;
        }

        // Claim at 100% vested
        skip(vestingPeriod / 2);
        uint256 claimable3 = bond.claimable(bondId, alice);
        if (claimable3 > 0) {
            vm.prank(alice);
            bond.claim(bondId);
            totalClaimed += claimable3;
        }

        // Total claimed should equal tokens owed
        assertEq(totalClaimed, tokensOwed);

        // Nothing left to claim
        assertEq(bond.claimable(bondId, alice), 0);
    }

    // =========================================================================
    // EDGE CASE AND INVARIANT TESTS
    // =========================================================================

    /// @notice Invariant: total raised never exceeds target
    function testFuzz_Invariant_TotalRaisedNeverExceedsTarget(
        uint256 amount1,
        uint256 amount2
    ) public {
        uint256 targetRaise = 100_000e6;
        amount1 = bound(amount1, 1000e6, 40_000e6);
        amount2 = bound(amount2, 1000e6, 40_000e6);

        uint256 bondId = _createBond(
            targetRaise,
            100_000e18,
            1000,
            30 days,
            1000e6,
            50_000e6
        );

        // Alice purchases
        paymentToken.mint(alice, amount1);
        vm.prank(alice);
        paymentToken.approve(address(bond), amount1);
        vm.prank(alice);
        bond.purchase(bondId, amount1);

        // Bob purchases (may fail if exceeds remaining)
        paymentToken.mint(bob, amount2);
        vm.prank(bob);
        paymentToken.approve(address(bond), amount2);

        if (amount1 + amount2 <= targetRaise) {
            vm.prank(bob);
            bond.purchase(bondId, amount2);
        }

        // Invariant check
        assertLe(bond.totalRaised(bondId), targetRaise);
    }

    /// @notice Test edge case: zero discount
    function testFuzz_Purchase_ZeroDiscount(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 1000e6, 50_000e6);

        uint256 bondId = _createBond(
            100_000e6,
            100_000e18,
            0,  // zero discount
            30 days,
            1000e6,
            100_000e6
        );

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);

        (, , uint256 tokensOwed, , , ) = bond.purchases(bondId, alice);

        // With 0% discount, tokens = amount * tokensToMint / targetRaise
        uint256 expected = (purchaseAmount * 100_000e18) / 100_000e6;
        assertEq(tokensOwed, expected);
    }

    /// @notice Test edge case: maximum discount
    function testFuzz_Purchase_MaxDiscount(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 1000e6, 50_000e6);

        uint256 bondId = _createBond(
            100_000e6,
            100_000e18,
            5000,  // 50% discount
            30 days,
            1000e6,
            100_000e6
        );

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);

        (, , uint256 tokensOwed, , , ) = bond.purchases(bondId, alice);

        // With 50% discount, user gets 150% of base tokens
        uint256 baseTokens = (purchaseAmount * 100_000e18) / 100_000e6;
        uint256 expected = (baseTokens * 15000) / 10000;  // 150%
        assertEq(tokensOwed, expected);
    }

    /// @notice Test bond not active
    function testFuzz_Purchase_InactiveBondFails(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 1000e6, 50_000e6);

        uint256 bondId = _createBond(
            100_000e6,
            100_000e18,
            1000,
            30 days,
            1000e6,
            100_000e6
        );

        // Close bond
        vm.prank(owner);
        bond.closeBond(bondId);

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.expectRevert(Bond.BondNotActive.selector);
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);
    }

    /// @notice Test bond before start time
    function testFuzz_Purchase_BeforeStartFails(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 1000e6, 50_000e6);

        Bond.BondConfig memory config = Bond.BondConfig({
            paymentToken: address(paymentToken),
            targetRaise: 100_000e6,
            tokensToMint: 100_000e18,
            discount: 1000,
            vestingPeriod: 30 days,
            startTime: block.timestamp + 1 days,  // starts in future
            endTime: block.timestamp + 31 days,
            minPurchase: 1000e6,
            maxPurchase: 100_000e6,
            active: true
        });

        vm.prank(owner);
        uint256 bondId = bond.createBond(config);

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.expectRevert(Bond.BondNotStarted.selector);
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);
    }

    /// @notice Test bond after end time
    function testFuzz_Purchase_AfterEndFails(uint256 purchaseAmount) public {
        purchaseAmount = bound(purchaseAmount, 1000e6, 50_000e6);

        uint256 bondId = _createBond(
            100_000e6,
            100_000e18,
            1000,
            30 days,
            1000e6,
            100_000e6
        );

        // Fast forward past end time
        skip(31 days);

        paymentToken.mint(alice, purchaseAmount);
        vm.prank(alice);
        paymentToken.approve(address(bond), purchaseAmount);

        vm.expectRevert(Bond.BondExpired.selector);
        vm.prank(alice);
        bond.purchase(bondId, purchaseAmount);
    }
}
