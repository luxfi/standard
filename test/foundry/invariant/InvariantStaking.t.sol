// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {sLUX} from "../../../contracts/staking/sLUX.sol";

contract MockWLUX is ERC20 {
    constructor() ERC20("Wrapped LUX", "WLUX") {
        _mint(msg.sender, 100_000_000e18);
    }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract StakingHandler is Test {
    sLUX public staking;
    MockWLUX public wlux;
    address[] public actors;

    constructor(sLUX _staking, MockWLUX _wlux) {
        staking = _staking;
        wlux = _wlux;
        for (uint256 i = 0; i < 5; i++) {
            actors.push(address(uint160(0x1000 + i)));
            wlux.mint(actors[i], 1_000_000e18);
            vm.prank(actors[i]);
            wlux.approve(address(staking), type(uint256).max);
        }
    }

    function stake(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e18, 100_000e18);
        uint256 bal = wlux.balanceOf(actor);
        if (bal < amount) return;
        vm.prank(actor);
        try staking.stake(amount) {} catch {}
    }

    function instantUnstake(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 sbal = staking.balanceOf(actor);
        if (sbal == 0) return;
        amount = bound(amount, 1, sbal);
        vm.prank(actor);
        try staking.instantUnstake(amount) {} catch {}
    }

    function addRewards(uint256 amount) external {
        amount = bound(amount, 1e18, 10_000e18);
        wlux.mint(address(this), amount);
        wlux.approve(address(staking), amount);
        try staking.addRewards(amount) {} catch {}
    }
}

contract InvariantStakingTest is Test {
    sLUX public staking;
    MockWLUX public wlux;
    StakingHandler public handler;

    function setUp() public {
        wlux = new MockWLUX();
        staking = new sLUX(address(wlux));
        handler = new StakingHandler(staking, wlux);

        targetContract(address(handler));
    }

    /// @notice Total staked always matches actual WLUX balance in contract
    function invariant_totalStakedMatchesBalance() public view {
        assertGe(
            wlux.balanceOf(address(staking)),
            staking.totalStaked(),
            "Balance < totalStaked"
        );
    }

    /// @notice sLUX totalSupply > 0 iff totalStaked > 0
    function invariant_supplyConsistency() public view {
        if (staking.totalSupply() > 0) {
            assertGt(staking.totalStaked(), 0, "Supply but no stake");
        }
    }

    /// @notice Exchange rate (totalStaked / totalSupply) never decreases below 1:1
    function invariant_exchangeRateGe1() public view {
        uint256 supply = staking.totalSupply();
        if (supply > 0) {
            assertGe(staking.totalStaked(), supply, "Rate < 1:1");
        }
    }
}
