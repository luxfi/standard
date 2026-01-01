// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @dev Interface for tokens that can be bridged across chains
 */
interface IERC20Bridgable {
    /**
     * @dev Burns tokens from an address (called by bridge during bridge out)
     */
    function bridgeBurn(address from, uint256 amount) external;

    /**
     * @dev Mints tokens to an address (called by bridge during bridge in)
     */
    function bridgeMint(address to, uint256 amount) external;
}
