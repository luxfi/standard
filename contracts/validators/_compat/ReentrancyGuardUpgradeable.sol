// SPDX-License-Identifier: MIT
// Vendored from OpenZeppelin Contracts (Upgradeable) v5.0.2
// utils/ReentrancyGuardUpgradeable.sol — preserved here because
// OZ 5.6+ replaced this with ReentrancyGuardTransientUpgradeable,
// which requires EVM Cancun's transient-storage opcodes. The Liquid
// EVM is compiled for evm_version="shanghai" (no MCOPY, no TSTORE),
// so we hold the pre-Cancun ReentrancyGuard pattern as a compat shim
// for the vendored ACP-77 validator-manager stack.
//
// OpenZeppelin Contracts (last updated v5.0.0) is MIT-licensed.

pragma solidity >=0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuardUpgradeable` will make the
 * {nonReentrant} modifier available, which can be applied to functions
 * to make sure there are no nested (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions
 * marked as `nonReentrant` may not call one another. This can be
 * worked around by making those functions `private`, and then adding
 * `external` `nonReentrant` entry points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative
 * ways to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    /// @custom:storage-location erc7201:openzeppelin.storage.ReentrancyGuard
    struct ReentrancyGuardStorage {
        uint256 _status;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    // Slot derived from upstream string; renaming would shift storage layout.
    bytes32 private constant ReentrancyGuardStorageLocation =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    function _getReentrancyGuardStorage() private pure returns (ReentrancyGuardStorage storage $) {
        assembly {
            $.slot := ReentrancyGuardStorageLocation
        }
    }

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        if ($._status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        $._status = ENTERED;
    }

    function _nonReentrantAfter() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        return $._status == ENTERED;
    }
}
