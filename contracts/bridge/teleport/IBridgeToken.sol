// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBridgeToken
 * @notice Interface for tokens that can be bridged
 */
interface IBridgeToken is IERC20 {
    /**
     * @notice Mint tokens to an account (bridge only)
     * @param account Account to mint to
     * @param amount Amount to mint
     */
    function bridgeMint(address account, uint256 amount) external returns (bool);

    /**
     * @notice Burn tokens from an account (bridge only)
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function bridgeBurn(address account, uint256 amount) external returns (bool);
}
