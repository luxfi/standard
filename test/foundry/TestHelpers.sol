// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

contract TestHelpers is Test {
    // Common test addresses
    address constant ZERO_ADDRESS = address(0);
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // Common test amounts
    uint256 constant ONE_TOKEN = 1e18;
    uint256 constant TEN_TOKENS = 10e18;
    uint256 constant HUNDRED_TOKENS = 100e18;
    uint256 constant THOUSAND_TOKENS = 1000e18;
    
    // Generate deterministic addresses
    function makeAddr(string memory name) internal returns (address) {
        address addr = address(uint160(uint256(keccak256(abi.encodePacked(name)))));
        vm.label(addr, name);
        return addr;
    }
    
    // Generate array of addresses
    function makeAddresses(uint256 count) internal returns (address[] memory) {
        address[] memory addresses = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            addresses[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
        return addresses;
    }
    
    // Generate array of amounts
    function makeAmounts(uint256 count, uint256 baseAmount) internal pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            amounts[i] = baseAmount * (i + 1);
        }
        return amounts;
    }
    
    // Skip time
    function skipTime(uint256 seconds_) internal {
        skip(seconds_);
    }
    
    // Skip blocks
    function skipBlocks(uint256 blocks_) internal {
        vm.roll(block.number + blocks_);
    }
    
    // Deal ETH to address
    function dealETH(address to, uint256 amount) internal {
        vm.deal(to, amount);
    }
    
    // Expect event with specific data
    function expectEmit() internal {
        vm.expectEmit(true, true, true, true);
    }
    
    // Assert approximately equal (within 1%)
    function assertApproxEq(uint256 a, uint256 b) internal {
        uint256 tolerance = b / 100; // 1% tolerance
        if (a > b) {
            assertLe(a - b, tolerance);
        } else {
            assertLe(b - a, tolerance);
        }
    }
}