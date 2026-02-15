// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "./AIRegistry.sol";

/**
 * @title AIRegistrySimple
 * @dev Simple non-upgradeable version of AIRegistry for local testing
 * This version calls initialize in the constructor for easier local deployment
 */
contract AIRegistrySimple is AIRegistry {
    constructor(
        address owner_,
        address shinToken_,
        address aiNft_
    ) {
        // Call parent initialize
        initialize(owner_, shinToken_, aiNft_);
    }
}
