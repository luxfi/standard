// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {FeeGov} from "../../../contracts/treasury/FeeGov.sol";

contract InvariantTreasuryTest is Test {
    FeeGov public feeGov;

    function setUp() public {
        feeGov = new FeeGov(30, 10, 500, address(this)); // 0.3%, 0.1% floor, 5% cap
    }

    /// @notice FeeGov rate always within [floor, cap]
    function invariant_feeRateBounded() public view {
        assertGe(feeGov.rate(), feeGov.floor(), "Rate < floor");
        assertLe(feeGov.rate(), feeGov.cap(), "Rate > cap");
    }

    /// @notice Version is monotonically increasing
    function invariant_versionMonotonic() public view {
        assertGe(feeGov.version(), 1, "Version < 1");
    }
}
