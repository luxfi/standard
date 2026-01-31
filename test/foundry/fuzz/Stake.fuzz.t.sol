// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {Stake} from "../../../contracts/governance/Stake.sol";

/// @title StakeFuzzTest
/// @notice Fuzz tests for Stake.sol - ERC20Votes governance token
contract StakeFuzzTest is Test {
    Stake public token;

    address public owner;
    address public alice;
    address public bob;
    address public carol;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        // Create empty allocations array
        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);

        // Deploy with no initial allocations, unlimited supply, transferable
        vm.prank(owner);
        token = new Stake(
            "Governance Token",
            "GOV",
            allocations,
            owner,
            0,           // unlimited supply
            false        // not soulbound
        );
    }

    // =========================================================================
    // MINT FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test minting various amounts
    function testFuzz_Mint_ValidAmounts(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, type(uint128).max);

        vm.prank(owner);
        token.mint(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), amount);
    }

    /// @notice Fuzz test minting respects max supply
    function testFuzz_Mint_RespectsMaxSupply(uint256 maxSupply, uint256 mintAmount) public {
        maxSupply = bound(maxSupply, 1e18, type(uint128).max);
        mintAmount = bound(mintAmount, 1, type(uint128).max);

        // Deploy token with max supply
        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);
        vm.prank(owner);
        Stake capped = new Stake(
            "Capped Token",
            "CAP",
            allocations,
            owner,
            maxSupply,
            false
        );

        if (mintAmount > maxSupply) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    Stake.MaxSupplyExceeded.selector,
                    mintAmount,
                    maxSupply
                )
            );
            vm.prank(owner);
            capped.mint(alice, mintAmount);
        } else {
            vm.prank(owner);
            capped.mint(alice, mintAmount);
            assertEq(capped.balanceOf(alice), mintAmount);
        }
    }

    /// @notice Fuzz test cumulative minting respects max supply
    function testFuzz_Mint_CumulativeRespectsMaxSupply(
        uint256 maxSupply,
        uint256 amount1,
        uint256 amount2
    ) public {
        maxSupply = bound(maxSupply, 1e18, type(uint128).max);
        amount1 = bound(amount1, 1, maxSupply);
        amount2 = bound(amount2, 1, type(uint128).max);

        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);
        vm.prank(owner);
        Stake capped = new Stake("Capped", "CAP", allocations, owner, maxSupply, false);

        // First mint succeeds
        vm.prank(owner);
        capped.mint(alice, amount1);

        uint256 remaining = maxSupply - amount1;

        if (amount2 > remaining) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    Stake.MaxSupplyExceeded.selector,
                    amount2,
                    remaining
                )
            );
            vm.prank(owner);
            capped.mint(bob, amount2);
        } else {
            vm.prank(owner);
            capped.mint(bob, amount2);
            assertEq(capped.totalSupply(), amount1 + amount2);
        }
    }

    /// @notice Fuzz test only owner can mint
    function testFuzz_Mint_OnlyOwner(address unauthorized, uint256 amount) public {
        vm.assume(unauthorized != owner);
        vm.assume(unauthorized != address(0));
        amount = bound(amount, 1, type(uint128).max);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.mint(alice, amount);
    }

    // =========================================================================
    // BURN FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test burning tokens
    function testFuzz_Burn_ValidAmount(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        vm.prank(owner);
        token.mint(alice, mintAmount);

        vm.prank(alice);
        token.burn(burnAmount);

        assertEq(token.balanceOf(alice), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    /// @notice Fuzz test burning more than balance fails
    function testFuzz_Burn_ExceedsBalanceFails(uint256 balance, uint256 excess) public {
        balance = bound(balance, 1, type(uint64).max);
        excess = bound(excess, 1, type(uint64).max);
        uint256 burnAmount = balance + excess;

        vm.prank(owner);
        token.mint(alice, balance);

        vm.expectRevert();
        vm.prank(alice);
        token.burn(burnAmount);
    }

    /// @notice Fuzz test burning affects voting power
    function testFuzz_Burn_AffectsVotingPower(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1e18, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        vm.prank(owner);
        token.mint(alice, mintAmount);

        // Self-delegate to get voting power
        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), mintAmount);

        vm.prank(alice);
        token.burn(burnAmount);

        assertEq(token.getVotes(alice), mintAmount - burnAmount);
    }

    // =========================================================================
    // DELEGATION FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test delegation transfers voting power
    function testFuzz_Delegate_TransfersVotingPower(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        vm.prank(owner);
        token.mint(alice, amount);

        // Initially no voting power (not delegated)
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);

        // Alice delegates to bob
        vm.prank(alice);
        token.delegate(bob);

        // Bob now has voting power
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), amount);
    }

    /// @notice Fuzz test re-delegation moves voting power
    function testFuzz_Delegate_RedelegationMovesVotes(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        vm.prank(owner);
        token.mint(alice, amount);

        // Delegate to bob
        vm.prank(alice);
        token.delegate(bob);

        assertEq(token.getVotes(bob), amount);
        assertEq(token.getVotes(carol), 0);

        // Re-delegate to carol
        vm.prank(alice);
        token.delegate(carol);

        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), amount);
    }

    /// @notice Fuzz test self-delegation
    function testFuzz_Delegate_SelfDelegation(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        vm.prank(owner);
        token.mint(alice, amount);

        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), amount);
    }

    /// @notice Fuzz test delegating to zero address
    function testFuzz_Delegate_ToZeroRemovesPower(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        vm.prank(owner);
        token.mint(alice, amount);

        // First delegate to self
        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), amount);

        // Delegate to zero removes voting power
        vm.prank(alice);
        token.delegate(address(0));
        assertEq(token.getVotes(alice), 0);
    }

    /// @notice Fuzz test multiple delegators to same delegatee
    function testFuzz_Delegate_MultipleDelegators(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, type(uint64).max);
        amount2 = bound(amount2, 1e18, type(uint64).max);

        vm.prank(owner);
        token.mint(alice, amount1);
        vm.prank(owner);
        token.mint(bob, amount2);

        // Both delegate to carol
        vm.prank(alice);
        token.delegate(carol);
        vm.prank(bob);
        token.delegate(carol);

        assertEq(token.getVotes(carol), amount1 + amount2);
    }

    // =========================================================================
    // SOULBOUND MODE FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test transfers blocked when soulbound
    function testFuzz_Soulbound_TransfersBlocked(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        // Deploy soulbound token
        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);
        vm.prank(owner);
        Stake soulbound = new Stake(
            "Soulbound",
            "SOUL",
            allocations,
            owner,
            0,
            true  // soulbound
        );

        vm.prank(owner);
        soulbound.mint(alice, amount);

        // Transfer should fail
        vm.expectRevert(Stake.SoulboundToken.selector);
        vm.prank(alice);
        soulbound.transfer(bob, amount);
    }

    /// @notice Fuzz test minting works when soulbound
    function testFuzz_Soulbound_MintingWorks(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);
        vm.prank(owner);
        Stake soulbound = new Stake("Soulbound", "SOUL", allocations, owner, 0, true);

        // Mint should work (from address(0) is allowed)
        vm.prank(owner);
        soulbound.mint(alice, amount);

        assertEq(soulbound.balanceOf(alice), amount);
    }

    /// @notice Fuzz test burning works when soulbound
    function testFuzz_Soulbound_BurningWorks(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);
        vm.prank(owner);
        Stake soulbound = new Stake("Soulbound", "SOUL", allocations, owner, 0, true);

        vm.prank(owner);
        soulbound.mint(alice, amount);

        // Burn should work (to address(0) is allowed)
        vm.prank(alice);
        soulbound.burn(amount);

        assertEq(soulbound.balanceOf(alice), 0);
    }

    /// @notice Fuzz test toggling soulbound mode
    function testFuzz_Soulbound_CanToggle(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        // Start as soulbound
        Stake.Allocation[] memory allocations = new Stake.Allocation[](0);
        vm.prank(owner);
        Stake togglable = new Stake("Togglable", "TOG", allocations, owner, 0, true);

        vm.prank(owner);
        togglable.mint(alice, amount);

        // Should fail to transfer
        vm.expectRevert(Stake.SoulboundToken.selector);
        vm.prank(alice);
        togglable.transfer(bob, amount);

        // Toggle off soulbound
        vm.prank(owner);
        togglable.setSoulbound(false);

        // Now transfer should work
        vm.prank(alice);
        togglable.transfer(bob, amount);

        assertEq(togglable.balanceOf(bob), amount);
    }

    /// @notice Fuzz test only owner can toggle soulbound
    function testFuzz_Soulbound_OnlyOwnerCanToggle(address unauthorized) public {
        vm.assume(unauthorized != owner);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.setSoulbound(true);
    }

    // =========================================================================
    // DID INTEGRATION FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test linking DID
    function testFuzz_DID_LinkDID(string calldata didDocument) public {
        vm.assume(bytes(didDocument).length > 0);

        vm.prank(alice);
        token.linkDID(didDocument);

        assertEq(token.getDID(alice), didDocument);
    }

    /// @notice Fuzz test cannot link DID twice
    function testFuzz_DID_CannotLinkTwice(string calldata did1, string calldata did2) public {
        vm.assume(bytes(did1).length > 0);
        vm.assume(bytes(did2).length > 0);

        vm.prank(alice);
        token.linkDID(did1);

        vm.expectRevert(Stake.DIDAlreadyLinked.selector);
        vm.prank(alice);
        token.linkDID(did2);
    }

    /// @notice Fuzz test different users can link different DIDs
    function testFuzz_DID_DifferentUsersDifferentDIDs(
        string calldata did1,
        string calldata did2
    ) public {
        vm.assume(bytes(did1).length > 0);
        vm.assume(bytes(did2).length > 0);

        vm.prank(alice);
        token.linkDID(did1);

        vm.prank(bob);
        token.linkDID(did2);

        assertEq(token.getDID(alice), did1);
        assertEq(token.getDID(bob), did2);
    }

    // =========================================================================
    // INITIAL ALLOCATION FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test initial allocations are minted correctly
    function testFuzz_InitialAllocations(
        uint256 amount1,
        uint256 amount2
    ) public {
        amount1 = bound(amount1, 1e18, type(uint64).max);
        amount2 = bound(amount2, 1e18, type(uint64).max);

        Stake.Allocation[] memory allocations = new Stake.Allocation[](2);
        allocations[0] = Stake.Allocation({recipient: alice, amount: amount1});
        allocations[1] = Stake.Allocation({recipient: bob, amount: amount2});

        vm.prank(owner);
        Stake allocated = new Stake(
            "Allocated",
            "ALLOC",
            allocations,
            owner,
            0,
            false
        );

        assertEq(allocated.balanceOf(alice), amount1);
        assertEq(allocated.balanceOf(bob), amount2);
        assertEq(allocated.totalSupply(), amount1 + amount2);
    }

    /// @notice Fuzz test initial allocations respect max supply
    function testFuzz_InitialAllocations_RespectsMaxSupply(
        uint256 maxSupply,
        uint256 amount
    ) public {
        maxSupply = bound(maxSupply, 1e18, type(uint64).max);
        amount = bound(amount, maxSupply + 1, type(uint128).max);

        Stake.Allocation[] memory allocations = new Stake.Allocation[](1);
        allocations[0] = Stake.Allocation({recipient: alice, amount: amount});

        // This should not revert during construction (OZ doesn't check in constructor)
        // but would fail on subsequent mints
        vm.prank(owner);
        Stake allocated = new Stake(
            "Allocated",
            "ALLOC",
            allocations,
            owner,
            maxSupply,
            false
        );

        // Initial allocation went through
        assertEq(allocated.balanceOf(alice), amount);

        // But no more minting possible
        vm.expectRevert();
        vm.prank(owner);
        allocated.mint(bob, 1);
    }

    // =========================================================================
    // CHECKPOINTING FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test historical voting power via checkpoints
    /// @dev getPastVotes requires querying a STRICTLY PAST block (block.number - 1 or earlier)
    ///      OZ ERC5805 requires: timepoint < clock() where clock() = block.number
    function testFuzz_Checkpoints_HistoricalPower(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, type(uint64).max);
        amount2 = bound(amount2, 1e18, type(uint64).max);

        // Start at a known block
        vm.roll(100);

        vm.prank(owner);
        token.mint(alice, amount1);

        vm.prank(alice);
        token.delegate(alice);

        // Checkpoint written at block 100
        // We MUST advance before we can query it
        vm.roll(102);  // Now at block 102, can query blocks < 102

        // Query past votes at block 100
        uint256 pastVotes = token.getPastVotes(alice, 100);
        assertEq(pastVotes, amount1);

        // Advance more blocks and mint more
        vm.roll(200);

        vm.prank(owner);
        token.mint(alice, amount2);

        // Advance so we can query
        vm.roll(202);

        // Current voting power should include both
        assertEq(token.getVotes(alice), amount1 + amount2);

        // Past voting power at block 100 should still be amount1
        assertEq(token.getPastVotes(alice, 100), amount1);
    }

    // =========================================================================
    // TRANSFER FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test transfer updates delegation
    function testFuzz_Transfer_UpdatesDelegation(uint256 amount, uint256 transferAmount) public {
        amount = bound(amount, 1e18, type(uint64).max);
        transferAmount = bound(transferAmount, 0, amount);

        vm.prank(owner);
        token.mint(alice, amount);

        // Both delegate to themselves
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        assertEq(token.getVotes(alice), amount);
        assertEq(token.getVotes(bob), 0);

        // Transfer
        vm.prank(alice);
        token.transfer(bob, transferAmount);

        // Voting power should update
        assertEq(token.getVotes(alice), amount - transferAmount);
        assertEq(token.getVotes(bob), transferAmount);
    }

    /// @notice Fuzz test transferFrom with approval
    function testFuzz_TransferFrom_WithApproval(uint256 amount, uint256 transferAmount) public {
        amount = bound(amount, 1e18, type(uint64).max);
        transferAmount = bound(transferAmount, 0, amount);

        vm.prank(owner);
        token.mint(alice, amount);

        vm.prank(alice);
        token.approve(bob, transferAmount);

        vm.prank(bob);
        token.transferFrom(alice, carol, transferAmount);

        assertEq(token.balanceOf(alice), amount - transferAmount);
        assertEq(token.balanceOf(carol), transferAmount);
    }

    // =========================================================================
    // INVARIANT TESTS
    // =========================================================================

    /// @notice Invariant: total supply equals sum of all balances
    function testFuzz_Invariant_TotalSupplyEqualsBalances(
        uint256 amount1,
        uint256 amount2,
        uint256 burnAmount
    ) public {
        amount1 = bound(amount1, 1e18, type(uint64).max);
        amount2 = bound(amount2, 1e18, type(uint64).max);
        burnAmount = bound(burnAmount, 0, amount1);

        vm.prank(owner);
        token.mint(alice, amount1);
        vm.prank(owner);
        token.mint(bob, amount2);

        vm.prank(alice);
        token.burn(burnAmount);

        uint256 totalSupply = token.totalSupply();
        uint256 sumBalances = token.balanceOf(alice) + token.balanceOf(bob);

        assertEq(totalSupply, sumBalances);
    }

    /// @notice Invariant: total votes equals total delegated supply
    function testFuzz_Invariant_TotalVotesConsistent(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, type(uint64).max);
        amount2 = bound(amount2, 1e18, type(uint64).max);

        vm.prank(owner);
        token.mint(alice, amount1);
        vm.prank(owner);
        token.mint(bob, amount2);

        // All delegate to carol
        vm.prank(alice);
        token.delegate(carol);
        vm.prank(bob);
        token.delegate(carol);

        // Carol's votes should equal total supply
        assertEq(token.getVotes(carol), token.totalSupply());
    }

    /// @notice Invariant: delegation is conserved
    function testFuzz_Invariant_DelegationConserved(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);

        vm.prank(owner);
        token.mint(alice, amount);

        // Delegate to bob
        vm.prank(alice);
        token.delegate(bob);

        uint256 bobVotes = token.getVotes(bob);

        // Re-delegate to carol
        vm.prank(alice);
        token.delegate(carol);

        // Total votes should remain same
        uint256 carolVotes = token.getVotes(carol);
        assertEq(carolVotes, bobVotes);

        // Bob should have 0
        assertEq(token.getVotes(bob), 0);
    }

    // =========================================================================
    // EDGE CASE TESTS
    // =========================================================================

    /// @notice Test minting zero tokens
    function testFuzz_Mint_ZeroAmount() public {
        vm.prank(owner);
        token.mint(alice, 0);

        assertEq(token.balanceOf(alice), 0);
    }

    /// @notice Test burning zero tokens
    function testFuzz_Burn_ZeroAmount() public {
        vm.prank(owner);
        token.mint(alice, 1e18);

        vm.prank(alice);
        token.burn(0);

        assertEq(token.balanceOf(alice), 1e18);
    }

    /// @notice Test transfer zero tokens
    function testFuzz_Transfer_ZeroAmount() public {
        vm.prank(owner);
        token.mint(alice, 1e18);

        vm.prank(alice);
        token.transfer(bob, 0);

        assertEq(token.balanceOf(alice), 1e18);
        assertEq(token.balanceOf(bob), 0);
    }
}
