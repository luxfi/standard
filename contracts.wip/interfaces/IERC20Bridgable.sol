// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import "./IERC20Mintable.sol";
import "./IERC20Burnable.sol";

interface IERC20Bridgable is IERC20Mintable, IERC20Burnable {
    function bridgeBurn(address _to, uint256 _amount) external;
    function bridgeMint(address _from, uint256 _amount) external;
}
