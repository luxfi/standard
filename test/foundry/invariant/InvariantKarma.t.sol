// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {Karma} from "../../../contracts/governance/Karma.sol";

contract KarmaHandler is Test {
    Karma public karma;
    address[] public users;
    uint256 public totalMinted;
    uint256 public totalBurned;

    constructor(Karma _karma) {
        karma = _karma;
        for (uint256 i = 0; i < 10; i++) {
            users.push(address(uint160(0x2000 + i)));
        }
    }

    function mint(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        amount = bound(amount, 1e18, 200e18);
        // Respect MAX_KARMA cap
        uint256 current = karma.balanceOf(user);
        if (current + amount > karma.MAX_KARMA()) {
            amount = karma.MAX_KARMA() - current;
        }
        if (amount == 0) return;
        karma.mint(user, amount, bytes32(0));
        totalMinted += amount;
    }

    function burn(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        uint256 bal = karma.balanceOf(user);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        karma.burn(user, amount, bytes32(0));
        totalBurned += amount;
    }

    function slash(uint256 userSeed, uint256 percentage) external {
        address user = users[userSeed % users.length];
        uint256 bal = karma.balanceOf(user);
        if (bal == 0) return;
        percentage = bound(percentage, 100, 2500); // 1% to 25%
        uint256 slashAmount = bal * percentage / 10000;
        if (slashAmount == 0) return;
        karma.burn(user, slashAmount, bytes32("slash"));
        totalBurned += slashAmount;
    }
}

contract InvariantKarmaTest is Test {
    Karma public karma;
    KarmaHandler public handler;

    function setUp() public {
        karma = new Karma(address(this));
        handler = new KarmaHandler(karma);
        // Grant ATTESTOR_ROLE to handler for minting
        karma.grantRole(karma.ATTESTOR_ROLE(), address(handler));
        // Grant SLASHER_ROLE to handler for burning
        karma.grantRole(karma.SLASHER_ROLE(), address(handler));

        targetContract(address(handler));
    }

    /// @notice No account ever exceeds MAX_KARMA
    function invariant_maxKarmaCap() public view {
        for (uint256 i = 0; i < 10; i++) {
            address user = address(uint160(0x2000 + i));
            assertLe(karma.balanceOf(user), karma.MAX_KARMA(), "Exceeds cap");
        }
    }

    /// @notice Karma is soul-bound (non-transferable) — totalSupply == sum of all balances
    function invariant_supplyMatchesBalances() public view {
        uint256 sum = 0;
        for (uint256 i = 0; i < 10; i++) {
            sum += karma.balanceOf(address(uint160(0x2000 + i)));
        }
        assertEq(karma.totalSupply(), sum, "Supply != sum of balances");
    }

    /// @notice totalMinted - totalBurned == totalSupply
    function invariant_mintBurnAccounting() public view {
        assertEq(
            handler.totalMinted() - handler.totalBurned(),
            karma.totalSupply(),
            "Accounting mismatch"
        );
    }
}
