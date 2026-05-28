// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { SolvencyStateMachineV4 } from "../../../contracts/bridge/v4/SolvencyStateMachineV4.sol";
import { SolvencyState } from "../../../contracts/bridge/SolvencyStateMachine.sol";

contract TestSolvency is SolvencyStateMachineV4 {
    function init(uint8 basket) external {
        _initBasketThresholds(basket);
    }

    function update(uint8 basket, uint256 backing, uint256 liabs) external {
        _updateBasketSolvency(basket, backing, liabs);
    }

    function enter(uint8 basket) external {
        _enterBasketRecovery(basket);
    }

    function exit(uint8 basket, uint256 backing, uint256 liabs) external {
        _exitBasketRecovery(basket, backing, liabs);
    }

    function setT(uint8 basket, uint16 h, uint16 e) external {
        _setBasketThresholds(basket, h, e);
    }
}

contract SolvencyV4Test is Test {
    TestSolvency internal s;
    uint8 internal USD = 0;
    uint8 internal BTC = 1;

    function setUp() public {
        s = new TestSolvency();
        s.init(USD);
        s.init(BTC);
    }

    function test_InitDefaults() public {
        assertEq(s.healthyBp(USD), 11_111);
        assertEq(s.emergencyBp(USD), 10_000);
    }

    function test_InitIsIdempotent() public {
        s.init(USD); // second call is a no-op
        assertEq(s.healthyBp(USD), 11_111);
    }

    function test_HealthyToRestrictedAt_111pct_Boundary() public {
        // 111% backing: 11_111/10_000 = 1.1111 — at boundary, still RestrictedMint
        s.update(USD, 1110, 1000); // 111% > 111.11% threshold not met
        // Actually backing * 10_000 = 11_100_000; liabilities * 11_111 = 11_111_000
        // 11_100_000 < 11_111_000 → below healthy → RestrictedMint
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.RestrictedMint));
    }

    function test_HealthyAt_112pct() public {
        // 112% backing — strictly above healthy threshold
        s.update(USD, 1120, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Healthy));
    }

    function test_EmergencyWhenUnderbacked() public {
        s.update(USD, 999, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Emergency));
    }

    function test_PerBasketIndependence() public {
        s.update(USD, 999, 1000); // USD → Emergency
        s.update(BTC, 2000, 1000); // BTC → Healthy
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Emergency));
        assertEq(uint256(s.solvencyState(BTC)), uint256(SolvencyState.Healthy));
    }

    function test_HealthyWhenLiabsZero() public {
        s.update(USD, 0, 0);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Healthy));
    }

    function test_BasketMintAllowed_ReflectsState() public {
        assertTrue(s.basketMintAllowed(USD)); // Healthy by default
        s.update(USD, 999, 1000);
        assertFalse(s.basketMintAllowed(USD));
    }

    function test_BasketReleaseAllowed_ReflectsState() public {
        assertTrue(s.basketReleaseAllowed(USD)); // Healthy
        s.update(USD, 1000, 1000); // exactly 100% → RestrictedMint
        assertTrue(s.basketReleaseAllowed(USD)); // still releases
        s.update(USD, 999, 1000); // Emergency
        assertFalse(s.basketReleaseAllowed(USD));
    }

    function test_EnterRecovery_FromEmergencyOnly() public {
        s.update(USD, 999, 1000); // Emergency
        s.enter(USD);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Recovery));

        // can't enter again from Recovery
        vm.expectRevert(SolvencyStateMachineV4.SolvencyV4_NotEmergency.selector);
        s.enter(USD);
    }

    function test_EnterRecovery_FromHealthy_Reverts() public {
        vm.expectRevert(SolvencyStateMachineV4.SolvencyV4_NotEmergency.selector);
        s.enter(USD);
    }

    function test_ExitRecovery_RequiresBackingGteLiabs() public {
        s.update(USD, 999, 1000);
        s.enter(USD);

        vm.expectRevert(SolvencyStateMachineV4.SolvencyV4_BackingInsufficient.selector);
        s.exit(USD, 999, 1000);

        s.exit(USD, 1000, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.RestrictedMint));
    }

    function test_ExitRecovery_ToHealthy_When_AboveThreshold() public {
        s.update(USD, 999, 1000);
        s.enter(USD);
        s.exit(USD, 1200, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Healthy));
    }

    function test_RecoveryNotAffectedByUpdates() public {
        s.update(USD, 999, 1000);
        s.enter(USD);
        // even if backing recovers, state stays Recovery
        s.update(USD, 5000, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Recovery));
    }

    function test_SetThresholds_RejectsInvalid() public {
        vm.expectRevert(SolvencyStateMachineV4.SolvencyV4_InvalidThreshold.selector);
        s.setT(USD, 0, 0);

        vm.expectRevert(SolvencyStateMachineV4.SolvencyV4_InvalidThreshold.selector);
        s.setT(USD, 9000, 10000); // healthy <= emergency
    }

    function test_SetThresholds_ChangesBoundary() public {
        s.setT(USD, 12_000, 10_000); // 120% healthy threshold
        // 119% backing → RestrictedMint under new threshold
        s.update(USD, 1190, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.RestrictedMint));
        // 121% → Healthy
        s.update(USD, 1210, 1000);
        assertEq(uint256(s.solvencyState(USD)), uint256(SolvencyState.Healthy));
    }

    function testFuzz_OverflowSafe(uint256 backing, uint256 liabilities) public {
        // No matter the inputs, state machine never reverts on update.
        s.update(USD, backing, liabilities);
        SolvencyState st = s.solvencyState(USD);
        assertTrue(
            st == SolvencyState.Healthy || st == SolvencyState.RestrictedMint || st == SolvencyState.Emergency
        );
    }
}
