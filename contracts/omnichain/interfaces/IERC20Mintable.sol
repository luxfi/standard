// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";

/**
 * @dev Interface for ERC20 tokens with additional mint method
 */
interface IERC20Mintable is IERC20 {
    /**
     * @dev Mints `amount` of tokens to `to`
     */
    function mint(address to, uint256 amount) external;
}
