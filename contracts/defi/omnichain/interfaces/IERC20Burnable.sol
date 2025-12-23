// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import "./IERC20Mintable.sol";

interface IERC20Burnable is IERC20Mintable {
    function burn(uint256 _amount) external;
    function burnFrom(address _from, uint256 _amount) external;
}
