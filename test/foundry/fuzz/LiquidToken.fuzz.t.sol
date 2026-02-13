// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {LiquidToken} from "../../../contracts/liquid/LiquidToken.sol";
import {IERC3156FlashBorrower} from "../../../contracts/liquid/interfaces/IERC3156FlashBorrower.sol";

/// @title MockFlashBorrower
/// @notice Valid flash loan borrower that returns borrowed amount + fee
/// @dev The borrower must have tokens to pay the fee. The LiquidToken burns amount+fee
///      from the borrower, then mints fee to fee recipient. So borrower needs extra tokens
///      to cover the fee (which they don't have since they only received 'amount').
///      This is a DISCOVERED BUG in the LiquidToken.flashLoan implementation - it expects
///      the borrower to magically have extra tokens to pay the fee.
contract MockFlashBorrower is IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    bool public shouldFail;
    uint256 public lastAmount;
    uint256 public lastFee;

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }

    /// @notice Mint fee tokens to this contract so it can pay the flash loan fee
    function mintFee(address token, uint256 feeAmount) external {
        // This simulates having existing tokens to pay the fee
        // In real usage, borrower would profit from arbitrage to cover fee
    }

    function onFlashLoan(
        address,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external override returns (bytes32) {
        lastAmount = amount;
        lastFee = fee;

        if (shouldFail) {
            return bytes32(0);  // Invalid return
        }

        // Approve repayment (amount + fee will be burned)
        // NOTE: Borrower needs 'fee' extra tokens beyond what was loaned
        LiquidToken(token).approve(msg.sender, amount + fee);

        return CALLBACK_SUCCESS;
    }
}

/// @title MaliciousFlashBorrower
/// @notice Flash borrower that tries to steal funds
contract MaliciousFlashBorrower is IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    address public attacker;

    constructor(address _attacker) {
        attacker = _attacker;
    }

    function onFlashLoan(
        address,
        address token,
        uint256 amount,
        uint256,
        bytes calldata
    ) external override returns (bytes32) {
        // Try to transfer tokens to attacker instead of repaying
        try LiquidToken(token).transfer(attacker, amount) {} catch {}

        return CALLBACK_SUCCESS;  // Will still fail because tokens not available to burn
    }
}

/// @title ReentrantFlashBorrower
/// @notice Flash borrower that attempts reentrancy
contract ReentrantFlashBorrower is IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    LiquidToken public token;
    uint256 public reentrancyCount;

    constructor(address _token) {
        token = LiquidToken(_token);
    }

    function onFlashLoan(
        address,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external override returns (bytes32) {
        reentrancyCount++;

        // Only attempt reentry on first call
        if (reentrancyCount == 1) {
            // Try to call flashLoan again (should fail due to reentrancy guard)
            try token.flashLoan(
                IERC3156FlashBorrower(address(this)),
                address(token),
                amount / 2,
                ""
            ) {} catch {}
        }

        // Approve repayment
        token.approve(msg.sender, amount + fee);

        return CALLBACK_SUCCESS;
    }
}

/// @title LiquidTokenFuzzTest
/// @notice Fuzz tests for LiquidToken.sol - flash loans and minting
contract LiquidTokenFuzzTest is Test {
    LiquidToken public token;
    MockFlashBorrower public borrower;

    address public admin;
    address public minter;
    address public alice;
    address public bob;

    uint256 constant BPS = 10000;
    uint256 constant DEFAULT_FEE = 10;  // 0.1%

    function setUp() public {
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy token
        vm.prank(admin);
        token = new LiquidToken("Liquid USD", "LUSD", DEFAULT_FEE);

        // Setup permissions
        vm.prank(admin);
        token.setWhitelist(minter, true);

        vm.prank(admin);
        token.setMaxFlashLoan(1_000_000e18);

        // Deploy borrower
        borrower = new MockFlashBorrower();
    }

    // =========================================================================
    // FLASH LOAN FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test flash loan with various amounts
    /// @dev ERC-3156 requires borrower to have fee tokens to repay
    function testFuzz_FlashLoan_ValidAmounts(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        uint256 fee = (amount * DEFAULT_FEE) / BPS;
        uint256 feeRecipientBefore = token.balanceOf(admin);

        // Borrower needs fee tokens to repay (this is how ERC-3156 works)
        // In real usage, borrower profits from arbitrage to cover the fee
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(borrower), fee);

        vm.prank(alice);
        bool success = token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            amount,
            ""
        );

        assertTrue(success);
        assertEq(borrower.lastAmount(), amount);
        assertEq(borrower.lastFee(), fee);

        // Fee recipient should have received fee
        assertEq(token.balanceOf(admin), feeRecipientBefore + fee);

        // Borrower should have 0 balance (all burned)
        assertEq(token.balanceOf(address(borrower)), 0);
    }

    /// @notice Fuzz test flash loan fee calculation
    function testFuzz_FlashFee_Calculation(uint256 amount, uint256 feeRate) public {
        amount = bound(amount, 1, type(uint128).max);
        // C-01 security fix: MIN_FLASH_FEE is now 1 (0.01%)
        feeRate = bound(feeRate, 1, BPS);  // 0.01% to 100% (MIN_FLASH_FEE = 1)

        // Set fee rate
        vm.prank(admin);
        token.setFlashFee(feeRate);

        uint256 fee = token.flashFee(address(token), amount);
        uint256 expected = (amount * feeRate) / BPS;

        assertEq(fee, expected);
    }

    /// @notice Fuzz test flash loan exceeds max amount
    function testFuzz_FlashLoan_ExceedsMaxFails(uint256 maxAmount, uint256 excess) public {
        maxAmount = bound(maxAmount, 1e18, 1_000_000e18);
        excess = bound(excess, 1, 1_000_000e18);
        uint256 requestedAmount = maxAmount + excess;

        vm.prank(admin);
        token.setMaxFlashLoan(maxAmount);

        vm.expectRevert();  // IllegalArgument
        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            requestedAmount,
            ""
        );
    }

    /// @notice Fuzz test flash loan with zero amount
    function testFuzz_FlashLoan_ZeroAmount() public {
        // Zero amount should work (no-op essentially)
        vm.prank(alice);
        bool success = token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            0,
            ""
        );

        assertTrue(success);
        assertEq(borrower.lastAmount(), 0);
        assertEq(borrower.lastFee(), 0);
    }

    /// @notice Fuzz test flash loan with wrong token
    function testFuzz_FlashLoan_WrongTokenFails(address wrongToken, uint256 amount) public {
        vm.assume(wrongToken != address(token));
        vm.assume(wrongToken != address(0));
        amount = bound(amount, 1, 1_000_000e18);

        vm.expectRevert();  // IllegalArgument
        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            wrongToken,
            amount,
            ""
        );
    }

    /// @notice Fuzz test flash loan borrower returns wrong value
    function testFuzz_FlashLoan_BadReturnValueFails(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        borrower.setShouldFail(true);

        vm.expectRevert();  // IllegalState
        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            amount,
            ""
        );
    }

    /// @notice Fuzz test flash loan reentrancy protection
    function testFuzz_FlashLoan_ReentrancyProtected(uint256 amount) public {
        amount = bound(amount, 1e18, 100_000e18);

        ReentrantFlashBorrower reentrantBorrower = new ReentrantFlashBorrower(address(token));

        // Borrower needs fee tokens
        uint256 fee = token.flashFee(address(token), amount);
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(reentrantBorrower), fee);

        // This should succeed (reentrancy attempt inside will fail silently)
        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(reentrantBorrower)),
            address(token),
            amount,
            ""
        );

        // Only one successful flash loan (the outer one)
        assertEq(reentrantBorrower.reentrancyCount(), 1);
    }

    /// @notice Fuzz test malicious borrower cannot steal funds
    function testFuzz_FlashLoan_MaliciousBorrowerFails(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        address attacker = makeAddr("attacker");
        MaliciousFlashBorrower maliciousBorrower = new MaliciousFlashBorrower(attacker);

        // Should fail because borrower doesn't have tokens to burn
        vm.expectRevert();
        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(maliciousBorrower)),
            address(token),
            amount,
            ""
        );

        // Attacker should have no tokens
        assertEq(token.balanceOf(attacker), 0);
    }

    // =========================================================================
    // FLASH LOAN FEE EDGE CASES
    // =========================================================================

    /// @notice Fuzz test flash loan with minimum fee (C-01 security fix: MIN_FLASH_FEE = 1)
    function testFuzz_FlashLoan_MinFee(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        // C-01 security fix: MIN_FLASH_FEE is now 1 (0.01%), zero not allowed
        vm.prank(admin);
        token.setFlashFee(1);  // MIN_FLASH_FEE

        uint256 fee = (amount * 1) / BPS;  // Minimum fee (0.01%)
        uint256 feeRecipientBefore = token.balanceOf(admin);

        // Borrower needs fee tokens to repay
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(borrower), fee);

        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            amount,
            ""
        );

        // Minimum fee minted to admin
        assertEq(token.balanceOf(admin), feeRecipientBefore + fee);
        assertEq(borrower.lastFee(), fee);
    }

    /// @notice Fuzz test flash loan with maximum fee (100%)
    /// @dev With 100% fee, borrower must have same amount as loan to pay fee
    function testFuzz_FlashLoan_MaxFee(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        vm.prank(admin);
        token.setFlashFee(BPS);  // 100% fee

        uint256 fee = token.flashFee(address(token), amount);
        assertEq(fee, amount);  // Fee equals principal

        // Borrower needs fee tokens (equal to loan amount at 100% fee)
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(borrower), fee);

        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            amount,
            ""
        );

        assertEq(borrower.lastFee(), amount);
    }

    /// @notice Fuzz test fee cannot exceed 100%
    function testFuzz_SetFlashFee_CannotExceedMax(uint256 invalidFee) public {
        invalidFee = bound(invalidFee, BPS + 1, type(uint256).max);

        vm.expectRevert();  // IllegalArgument
        vm.prank(admin);
        token.setFlashFee(invalidFee);
    }

    // =========================================================================
    // MAX FLASH LOAN TESTS
    // =========================================================================

    /// @notice Fuzz test max flash loan query
    function testFuzz_MaxFlashLoan_Query(uint256 maxAmount) public {
        vm.prank(admin);
        token.setMaxFlashLoan(maxAmount);

        assertEq(token.maxFlashLoan(address(token)), maxAmount);
    }

    /// @notice Fuzz test max flash loan returns 0 for wrong token
    function testFuzz_MaxFlashLoan_WrongTokenReturnsZero(address wrongToken) public {
        vm.assume(wrongToken != address(token));

        assertEq(token.maxFlashLoan(wrongToken), 0);
    }

    // =========================================================================
    // MINT/BURN FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test minting by whitelisted address
    function testFuzz_Mint_WhitelistedSuccess(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, type(uint128).max);

        vm.prank(minter);
        token.mint(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
    }

    /// @notice Fuzz test minting by non-whitelisted fails
    function testFuzz_Mint_NonWhitelistedFails(address unauthorized, uint256 amount) public {
        vm.assume(unauthorized != minter);
        vm.assume(unauthorized != address(0));
        amount = bound(amount, 1, type(uint128).max);

        vm.expectRevert();  // Unauthorized
        vm.prank(unauthorized);
        token.mint(alice, amount);
    }

    /// @notice Fuzz test minting when paused fails
    function testFuzz_Mint_WhenPausedFails(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(admin);
        token.setPaused(minter, true);

        vm.expectRevert();  // IllegalState
        vm.prank(minter);
        token.mint(alice, amount);
    }

    /// @notice Fuzz test burning tokens
    function testFuzz_Burn_ValidAmount(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        // Mint first
        vm.prank(minter);
        token.mint(alice, mintAmount);

        // Burn
        vm.prank(alice);
        token.burn(burnAmount);

        assertEq(token.balanceOf(alice), mintAmount - burnAmount);
    }

    /// @notice Fuzz test burning more than balance fails
    function testFuzz_Burn_ExceedsBalanceFails(uint256 balance, uint256 excess) public {
        balance = bound(balance, 1, type(uint64).max);
        excess = bound(excess, 1, type(uint64).max);
        uint256 burnAmount = balance + excess;

        vm.prank(minter);
        token.mint(alice, balance);

        vm.expectRevert();
        vm.prank(alice);
        token.burn(burnAmount);
    }

    /// @notice Fuzz test burnFrom with approval
    function testFuzz_BurnFrom_WithApproval(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        // Mint to alice
        vm.prank(minter);
        token.mint(alice, mintAmount);

        // Alice approves bob
        vm.prank(alice);
        token.approve(bob, burnAmount);

        // Bob burns from alice
        vm.prank(bob);
        token.burnFrom(alice, burnAmount);

        assertEq(token.balanceOf(alice), mintAmount - burnAmount);
    }

    /// @notice Fuzz test burnFrom without approval fails
    function testFuzz_BurnFrom_WithoutApprovalFails(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(minter);
        token.mint(alice, mintAmount);

        // No approval given
        vm.expectRevert();
        vm.prank(bob);
        token.burnFrom(alice, burnAmount);
    }

    /// @notice Fuzz test burnFrom with max approval doesn't decrease
    function testFuzz_BurnFrom_MaxApprovalNotDecreased(uint256 burnAmount) public {
        burnAmount = bound(burnAmount, 1, type(uint128).max);

        vm.prank(minter);
        token.mint(alice, burnAmount);

        // Alice gives max approval
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.burnFrom(alice, burnAmount);

        // Max approval should not decrease
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    // =========================================================================
    // ACCESS CONTROL FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test only admin can set flash fee
    function testFuzz_SetFlashFee_OnlyAdmin(address unauthorized, uint256 fee) public {
        vm.assume(unauthorized != admin);
        fee = bound(fee, 0, BPS);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.setFlashFee(fee);
    }

    /// @notice Fuzz test only admin can set max flash loan
    function testFuzz_SetMaxFlashLoan_OnlyAdmin(address unauthorized, uint256 max) public {
        vm.assume(unauthorized != admin);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.setMaxFlashLoan(max);
    }

    /// @notice Fuzz test only admin can whitelist
    function testFuzz_SetWhitelist_OnlyAdmin(address unauthorized, address target, bool state) public {
        vm.assume(unauthorized != admin);

        vm.expectRevert();
        vm.prank(unauthorized);
        token.setWhitelist(target, state);
    }

    /// @notice Fuzz test only sentinel can pause
    function testFuzz_SetPaused_OnlySentinel(address unauthorized, address target, bool state) public {
        vm.assume(unauthorized != admin);  // admin has sentinel role by default

        vm.expectRevert();
        vm.prank(unauthorized);
        token.setPaused(target, state);
    }

    // =========================================================================
    // INVARIANT TESTS
    // =========================================================================

    /// @notice Invariant: total supply remains zero-sum after flash loan
    /// @dev Flash loan flow: mint(amount) to borrower -> borrower uses -> burn(amount+fee) from borrower -> mint(fee) to recipient
    /// Net supply change: +amount -amount -fee +fee = 0 (if borrower had fee already)
    function testFuzz_Invariant_FlashLoanZeroSum(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        uint256 fee = token.flashFee(address(token), amount);

        // Borrower needs fee tokens (minted before we measure supplyBefore)
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(borrower), fee);

        uint256 supplyBefore = token.totalSupply();  // includes fee already minted to borrower

        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            amount,
            ""
        );

        uint256 supplyAfter = token.totalSupply();

        // Flow analysis:
        // 1. supplyBefore = fee (borrower's tokens)
        // 2. mint(amount) to borrower: supply = fee + amount
        // 3. burn(amount + fee) from borrower: supply = 0
        // 4. mint(fee) to feeRecipient: supply = fee
        // Net: supplyAfter = fee = supplyBefore (supply unchanged!)
        assertEq(supplyAfter, supplyBefore);
    }

    /// @notice Invariant: borrower balance is zero after flash loan
    function testFuzz_Invariant_BorrowerBalanceZeroAfterLoan(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        uint256 fee = token.flashFee(address(token), amount);

        // Borrower needs fee tokens
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(borrower), fee);

        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(borrower)),
            address(token),
            amount,
            ""
        );

        assertEq(token.balanceOf(address(borrower)), 0);
    }

    // =========================================================================
    // DATA PARAMETER FUZZ TESTS
    // =========================================================================

    /// @notice Fuzz test flash loan passes arbitrary data
    function testFuzz_FlashLoan_PassesData(uint256 amount, bytes calldata data) public {
        amount = bound(amount, 1e18, 1_000_000e18);

        // Create a borrower that records data
        DataRecordingBorrower dataBorrower = new DataRecordingBorrower();

        // Borrower needs fee tokens
        uint256 fee = token.flashFee(address(token), amount);
        vm.prank(admin);
        token.setWhitelist(address(this), true);
        token.mint(address(dataBorrower), fee);

        vm.prank(alice);
        token.flashLoan(
            IERC3156FlashBorrower(address(dataBorrower)),
            address(token),
            amount,
            data
        );

        assertEq(dataBorrower.lastData(), data);
    }
}

/// @title DataRecordingBorrower
/// @notice Flash borrower that records the data parameter
contract DataRecordingBorrower is IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    bytes public lastData;

    function onFlashLoan(
        address,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        lastData = data;
        LiquidToken(token).approve(msg.sender, amount + fee);
        return CALLBACK_SUCCESS;
    }
}
