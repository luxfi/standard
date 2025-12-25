// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "./HanzoRegistry.sol";

/**
 * @title HanzoRegistrySimple
 * @dev Simple non-upgradeable version of HanzoRegistry for local testing
 * This version calls initialize in the constructor for easier local deployment
 */
contract HanzoRegistrySimple is HanzoRegistry {
    constructor(
        address owner_,
        address shinToken_,
        address hanzoNft_
    ) {
        // Call parent initialize
        initialize(owner_, shinToken_, hanzoNft_);
    }
}
