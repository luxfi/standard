// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.x compatibility shim
// Counters was removed in OZ 5.x - use uint256 directly instead
pragma solidity ^0.8.0;

/// @notice Counters compatibility shim for OZ 4.x contracts
/// @dev Counters was removed in OZ 5.x. Consider using uint256 directly.
library Counters {
    struct Counter {
        uint256 _value;
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}
