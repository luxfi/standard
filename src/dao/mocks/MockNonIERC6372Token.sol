// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

contract MockNonIERC6372Token {
    // This contract deliberately does not implement IERC6372.
    // It can have other functions, but not CLOCK_MODE() or clock() from that interface.
    function someOtherFunction() external pure returns (bool) {
        return true;
    }
}
